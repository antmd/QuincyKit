/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *
 * Copyright (c) 2011 Andreas Linde & Kent Sutherland.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "BWQuincyManager.h"
#import "BWQuincyUI.h"
#import <sys/sysctl.h>

#define SDK_NAME @"Quincy"
#define SDK_VERSION @"2.1.6"

#undef LOG_DEBUG
#undef LOG_INFO
#undef LOG_WARN
#undef LOG_ERROR
#define _STRINGIFY(VALUE) #VALUE
#define STRINGIFY(VALUE) _STRINGIFY(VALUE)

#define LIBRARY_NAME QuincyKit
#ifdef DEBUG
#define LOG_DEBUG(_format, ...)                                                                    \
    [self _logAtLevel:BW_LOG_LEVEL_DEBUG                                                           \
                message:[NSString stringWithFormat:@"%s %s: %@", STRINGIFY(LIBRARY_NAME),          \
                                                   __PRETTY_FUNCTION__,                            \
                                                   [NSString stringWithFormat:_format,             \
                                                                              ##__VA_ARGS__]]]
#else
#define LOG_DEBUG
#endif
#define _LOG(_level, _prefix, _format, ...)                                                        \
    [self _logAtLevel:_level                                                                       \
                message:[@_prefix stringByAppendingString:                                         \
                                          [NSString stringWithFormat:_format, ##__VA_ARGS__]]]
#define LOG_INFO(format, ...)                                                                      \
    _LOG(BW_LOG_LEVEL_INFO, STRINGIFY(LIBRARY_NAME) ": ", format, ##__VA_ARGS__)
#define LOG_WARN(format, ...)                                                                      \
    _LOG(BW_LOG_LEVEL_WARN, STRINGIFY(LIBRARY_NAME) ": ", format, ##__VA_ARGS__)
#define LOG_ERROR(format, ...)                                                                     \
    _LOG(BW_LOG_LEVEL_ERROR, STRINGIFY(LIBRARY_NAME) ": ", format, ##__VA_ARGS__)


@interface BWQuincyManager (private)
- (void)startManager;

- (void)_postXML:(NSString *)xml toURL:(NSURL *)url;
- (void)searchCrashLogFile:(NSString *)path;
- (BOOL)hasPendingCrashReport;
- (void)returnToMainApplication;
@end


@implementation BWQuincyManager {
  CrashReportStatus _serverResult;
  NSInteger         _statusCode;
  NSMutableString   *_contentOfProperty;
  NSString   *_crashFile;
  BWQuincyUI *_quincyUI;
  NSMutableData  *_receivedData;
    NSURLConnection *_urlConnection;
}

@synthesize delegate = _delegate;
@synthesize submissionURL = _submissionURL;
@synthesize companyName = _companyName;
@synthesize appIdentifier = _appIdentifier;
@synthesize autoSubmitCrashReport = _autoSubmitCrashReport;


- (id)initWithDelegate:(id<BWQuincyManagerDelegate>)delegate applicationBundle:(NSBundle *)bundle reportBundle:(NSBundle *)pluginBundle
{
    if ((self = [super init])) {
        self.delegate = delegate;
        LOG_DEBUG(@"Initialising...");
        _serverResult = CrashReportStatusFailureDatabaseNotAvailable;
        _quincyUI = nil;

        _submissionURL = nil;
        _appIdentifier = nil;

        _crashFile = nil;
        _applicationBundle = bundle;
        _reportBundle = pluginBundle;

        self.companyName = @"";
    }
    return self;
}

- (id)initWithDelegate:(id<BWQuincyManagerDelegate>)delegate applicationBundle:(NSBundle *)bundle
{
    return [self initWithDelegate:nil applicationBundle:bundle reportBundle:bundle ];
}
- (id)init { return [self initWithDelegate:nil applicationBundle:NSBundle.mainBundle]; }


- (void)searchCrashLogFile:(NSString *)path
{
    NSFileManager *fman = [NSFileManager defaultManager];

    NSError *error;
    NSMutableArray *filesWithModificationDate = [NSMutableArray array];
    NSArray *crashLogFiles = [fman contentsOfDirectoryAtPath:path error:&error];
    NSEnumerator *filesEnumerator = [crashLogFiles objectEnumerator];
    NSString *crashFile;
    while ((crashFile = [filesEnumerator nextObject])) {
        NSString *crashLogPath = [path stringByAppendingPathComponent:crashFile];
        NSDate *modDate = [[[NSFileManager defaultManager]
                                   attributesOfItemAtPath:crashLogPath
                                                    error:&error] fileModificationDate];
        [filesWithModificationDate
                addObject:[NSDictionary dictionaryWithObjectsAndKeys:crashFile, @"name",
                                                                     crashLogPath, @"path", modDate,
                                                                     @"modDate", nil]];
    }

    NSSortDescriptor *dateSortDescriptor =
            [[NSSortDescriptor alloc] initWithKey:@"modDate" ascending:YES];
    NSArray *sortedFiles = [filesWithModificationDate
            sortedArrayUsingDescriptors:[NSArray arrayWithObject:dateSortDescriptor]];

    NSPredicate *filterPredicate = [NSPredicate
            predicateWithFormat:@"name BEGINSWITH %@", [self applicationName]];
    NSArray *filteredFiles = [sortedFiles filteredArrayUsingPredicate:filterPredicate];

    _crashFile = [[[filteredFiles valueForKeyPath:@"path"] lastObject] copy];
}


- (void)setAppIdentifier:(NSString *)anAppIdentifier
{
    if (_appIdentifier != anAppIdentifier) {
        _appIdentifier = [anAppIdentifier copy];
    }

    [self setSubmissionURL:@"https://rink.hockeyapp.net/"];
}

- (void)storeLastCrashDate:(NSDate *)date
{
    [NSUserDefaults.standardUserDefaults setValue:date forKey:@"CrashReportSender.lastCrashDate"];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (NSDate *)loadLastCrashDate
{
    NSDate *date = [[NSUserDefaults standardUserDefaults]
            valueForKey:@"CrashReportSender.lastCrashDate"];
    return date ?: [NSDate distantPast];
}

- (void)storeAppVersion:(NSString *)version
{
    [NSUserDefaults.standardUserDefaults setValue:version forKey:@"CrashReportSender.appVersion"];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (NSString *)loadAppVersion
{
    NSString *appVersion = [[NSUserDefaults standardUserDefaults]
            valueForKey:@"CrashReportSender.appVersion"];
    return appVersion ?: nil;
}

#pragma mark -
#pragma mark GetCrashData

- (BOOL)hasPendingCrashReport
{
    BOOL returnValue = NO;

    NSString *appVersion = [self loadAppVersion];
    NSDate *lastCrashDate = [self loadLastCrashDate];

    // If this is the first run, or the application version has changed since we last ran, then just
    // record the new app version, and return
    if (!appVersion || ![appVersion isEqualToString:self.applicationVersion] ||
        [lastCrashDate isEqualToDate:NSDate.distantPast]) {
        [self storeAppVersion:self.applicationVersion];
        [self storeLastCrashDate:NSDate.date];
        return NO;
    }

    NSArray *libraryDirectories =
            NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, TRUE);
    // Snow Leopard is having the log files in another location
    [self searchCrashLogFile:[[libraryDirectories lastObject]
                                     stringByAppendingPathComponent:@"Logs/DiagnosticReports"]];
    if (_crashFile == nil) {
        [self searchCrashLogFile:[[libraryDirectories lastObject]
                                         stringByAppendingPathComponent:@"Logs/CrashReporter"]];
        if (_crashFile == nil) {
            NSString *sandboxFolder = [NSString
                    stringWithFormat:@"/Containers/%@/Data/Library", self.applicationIdentifier];
            if ([libraryDirectories.lastObject rangeOfString:sandboxFolder].location !=
                NSNotFound) {
                NSString *libFolderName = [[libraryDirectories lastObject]
                        stringByReplacingOccurrencesOfString:sandboxFolder
                                                  withString:@""];
                [self searchCrashLogFile:
                                [libFolderName
                                        stringByAppendingPathComponent:@"Logs/DiagnosticReports"]];
            }
        }
        // Search machine diagnostic reports directory
        if (_crashFile == nil) {
            NSArray *libraryDirectories = NSSearchPathForDirectoriesInDomains(
                    NSLibraryDirectory, NSLocalDomainMask, TRUE);
            [self searchCrashLogFile:
                            [[libraryDirectories lastObject]
                                    stringByAppendingPathComponent:@"Logs/DiagnosticReports"]];
            if (_crashFile == nil) {
                [self searchCrashLogFile:
                                [[libraryDirectories lastObject]
                                        stringByAppendingPathComponent:@"Logs/CrashReporter"]];
            }
        }
    }

    if (_crashFile) {
        NSError *error;

        NSDate *
        crashLogModificationDate = [[[NSFileManager defaultManager]
                                            attributesOfItemAtPath:_crashFile
                                                             error:&error] fileModificationDate];
        unsigned long long crashLogFileSize =
                [[[NSFileManager defaultManager] attributesOfItemAtPath:_crashFile
                                                                  error:&error] fileSize];
        if ([crashLogModificationDate compare:lastCrashDate] == NSOrderedDescending &&
            crashLogFileSize > 0) {
            [self storeLastCrashDate:crashLogModificationDate];
            returnValue = YES;
        }
        else {
            _crashFile = nil;
        }
    }

    return returnValue;
}

- (void)returnToMainApplication
{
    if (self.delegate != nil && [self.delegate
                                        respondsToSelector:@selector(showMainApplicationWindow)])
        [self.delegate showMainApplicationWindow];
}

- (void)startManager
{
    LOG_DEBUG(@"Starting:\n\tApplication { name = %@, version = %@, identifier = %@ },\n\tReport Bundle { name = %@, version = %@, identifier = %@ }",self.applicationName,self.applicationVersion,self.applicationIdentifier,self.reportBundleName,self.reportBundleVersion,self.reportBundleIdentifier);
    
    BOOL hasValidPendingCrashReport = [self hasPendingCrashReport];
    if (hasValidPendingCrashReport) {
        if ([self.delegate respondsToSelector:@selector(diagnosticReportFileIsValid:)]) {
            hasValidPendingCrashReport = [self.delegate diagnosticReportFileIsValid:_crashFile];
        }
    }
    
    
    if (hasValidPendingCrashReport) {
        if (!self.autoSubmitCrashReport) {
            // Present 'Send Crash Report' query window
            _quincyUI = [[BWQuincyUI alloc] initWithManager:self
                                                  crashFile:_crashFile
                                                companyName:_companyName
                                            applicationName:self.reportBundleName];
            if ([self.delegate respondsToSelector:@selector(uiWillBeShown)]) {
                [self.delegate uiWillBeShown];
            }
            [_quincyUI askCrashReportDetails];
            return; // QuincyUI will call 'returnToMainApplication'
        }
        else {
            // Auto-submit crash report
            NSError *error = nil;
            NSString *crashLogs = [NSString stringWithContentsOfFile:_crashFile
                                                            encoding:NSUTF8StringEncoding
                                                               error:&error];
            if (!error) {
                NSString *
                lastCrash = [[crashLogs componentsSeparatedByString:@"**********\n\n"] lastObject];

                NSString *description = @"";

                if (_delegate && [_delegate respondsToSelector:@selector(crashReportDescription)]) {
                    description = [_delegate crashReportDescription];
                }

                [self sendReportCrash:lastCrash description:description];
                return; // sendReportCrash:description: will call 'returnToMainApplication'
            }
        }
    }
    [self returnToMainApplication];
}

- (NSString *)modelVersion
{
    NSString *modelString = nil;
    int modelInfo[2] = {CTL_HW, HW_MODEL};
    size_t modelSize;

    if (sysctl(modelInfo, 2, NULL, &modelSize, NULL, 0) == 0) {
        void *modelData = malloc(modelSize);

        if (modelData) {
            if (sysctl(modelInfo, 2, modelData, &modelSize, NULL, 0) == 0) {
                modelString = [NSString stringWithUTF8String:modelData];
            }

            free(modelData);
        }
    }

    return modelString;
}



- (void)cancelReport {
    LOG_INFO(@"User cancelled crash report.");
    [self returnToMainApplication];
    [ self _cleanupConnectionAndNotifyDelegate];
}


- (void)sendReportCrash:(NSString *)crashContent description:(NSString *)notes
{
    NSString *userid = @"";
    NSString *contact = @"";

    SInt32 versionMajor, versionMinor, versionBugFix;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (Gestalt(gestaltSystemVersionMajor, &versionMajor) != noErr)
        versionMajor = 0;
    if (Gestalt(gestaltSystemVersionMinor, &versionMinor) != noErr)
        versionMinor = 0;
    if (Gestalt(gestaltSystemVersionBugFix, &versionBugFix) != noErr)
        versionBugFix = 0;
#pragma clang diagnostic pop
    
    NSString *xml = [NSString
            stringWithFormat:@"<crash><applicationname>%s</applicationname><bundleidentifier>%s</"
                              "bundleidentifier><systemversion>%@</"
                              "systemversion><senderversion>%@</senderversion><version>%@</"
                              "version><platform>%@</platform><userid>%@</userid><contact>%@</"
                              "contact><description><![CDATA[%@]]></"
                              "description><log><![CDATA[%@]]></log></crash>",
                             [self.reportBundleName UTF8String],
                             [self.reportBundleIdentifier UTF8String],
                             [NSString stringWithFormat:@"%i.%i.%i", versionMajor, versionMinor,
                                                        versionBugFix],
                             self.reportBundleVersion, self.reportBundleVersion, self.modelVersion,
                             userid, contact, notes, crashContent];


    LOG_DEBUG(@"Sending Crash Report: %@",xml);
    [self returnToMainApplication];

    [self _postXML:[NSString stringWithFormat:@"<crashes>%@</crashes>", xml]
               toURL:[NSURL URLWithString:self.submissionURL]];
}

- (void)_postXML:(NSString *)xml toURL:(NSURL *)url
{
    NSMutableURLRequest *request = nil;
    NSString *boundary = @"----FOO";

    if (self.appIdentifier) {
        request = [NSMutableURLRequest
                requestWithURL:
                        [NSURL URLWithString:
                                        [NSString
                                                stringWithFormat:
                                                        @"%@api/2/apps/%@/"
                                                         "crashes?sdk=%@&sdk_version=%@",
                                                        self.submissionURL,
                                                        [self.appIdentifier
                                                                stringByAddingPercentEscapesUsingEncoding:
                                                                        NSUTF8StringEncoding],
                                                        SDK_NAME, SDK_VERSION]]];
    }
    else {
        request = [NSMutableURLRequest requestWithURL:url];
    }

    [request setValue:@"Quincy/Mac" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setTimeoutInterval:15];
    [request setHTTPMethod:@"POST"];
    NSString *contentType = [NSString
            stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-type"];

    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary]
                                 dataUsingEncoding:NSUTF8StringEncoding]];
    if (self.appIdentifier) {
        [postBody
                appendData:
                        [@"Content-Disposition: form-data; name=\"xml\"; filename=\"crash.xml\"\r\n"
                                dataUsingEncoding:NSUTF8StringEncoding]];
        [postBody appendData:[[NSString stringWithFormat:@"Content-Type: text/xml\r\n\r\n"]
                                     dataUsingEncoding:NSUTF8StringEncoding]];
    }
    else {
        [postBody appendData:[@"Content-Disposition: form-data; name=\"xmlstring\"\r\n\r\n"
                                     dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postBody appendData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary]
                                 dataUsingEncoding:NSUTF8StringEncoding]];
    [request setHTTPBody:postBody];

    _serverResult = CrashReportStatusUnknown;
    _statusCode = 200;

    _receivedData = [NSMutableData new];
    _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self ];
                    
}

/*
 *
 *
 *================================================================================================*/
#pragma mark - NSURLConnectionDelegate
/*==================================================================================================
 */
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)urlResponse
{
    // This method is called when the server has determined that it
    // has enough information to create the NSURLResponse object.
    
    // It can be called multiple times, for example in the case of a
    // redirect, so each time we reset the data.
    
    // receivedData is an instance variable declared elsewhere.
    NSHTTPURLResponse* response = (NSHTTPURLResponse*)urlResponse;
    _statusCode = [response statusCode];
    LOG_INFO(@"Received status code %lu from server.", _statusCode);
    
    [_receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // Append the new data to receivedData.
    // receivedData is an instance variable declared elsewhere.
    [_receivedData appendData:data];
    LOG_DEBUG(@"Received %lu bytes.",data.length);
}

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error
{
    
    LOG_ERROR(@"Connection failed! Error - %@ %@",
          [error localizedDescription],
          [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);
    [self _cleanupConnectionAndNotifyDelegate];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    LOG_INFO(@"Succeeded! Received %lu bytes of data",[_receivedData length]);
    if (_receivedData != nil && _receivedData.length > 0) {
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData:_receivedData];
            // Set self as the delegate of the parser so that it will receive the parser delegate
            // methods callbacks.
            [parser setDelegate:self];
            // Depending on the XML document you're parsing, you may want to enable these features
            // of NSXMLParser.
            [parser setShouldProcessNamespaces:NO];
            [parser setShouldReportNamespacePrefixes:NO];
            [parser setShouldResolveExternalEntities:NO];
            
            [parser parse];
        LOG_INFO(@"Server result = %d",_serverResult);
    }
    [self _cleanupConnectionAndNotifyDelegate];
}

-(void)_cleanupConnectionAndNotifyDelegate
{
    _urlConnection = nil;
    _receivedData = nil;
    if ([self.delegate respondsToSelector:@selector(crashReportingCompleted)]) {
        [self.delegate crashReportingCompleted];
    }
}
/*
 *
 *
 *================================================================================================*/
#pragma mark - NSXMLParser
/*==================================================================================================
 */


- (void)parser:(NSXMLParser *)parser
        didStartElement:(NSString *)elementName
           namespaceURI:(NSString *)namespaceURI
          qualifiedName:(NSString *)qName
             attributes:(NSDictionary *)attributeDict
{
    if (qName) {
        elementName = qName;
    }

    if ([elementName isEqualToString:@"result"]) {
        _contentOfProperty = [NSMutableString string];
    }
}

- (void)parser:(NSXMLParser *)parser
        didEndElement:(NSString *)elementName
         namespaceURI:(NSString *)namespaceURI
        qualifiedName:(NSString *)qName
{
    if (qName) {
        elementName = qName;
    }

    if ([elementName isEqualToString:@"result"]) {
        if ([_contentOfProperty intValue] > _serverResult) {
            _serverResult = [_contentOfProperty intValue];
        }
    }
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (_contentOfProperty) {
        // If the current element is one whose content we care about, append 'string'
        // to the property that holds the content of the current element.
        if (string != nil) {
            [_contentOfProperty appendString:string];
        }
    }
}


/*
 *
 *
 *================================================================================================*/
#pragma mark - Properties
/*==================================================================================================
 */


- (NSString *)applicationName
{ return [self _infoPlistValueForBundle:_applicationBundle withKey:@"CFBundleExecutable"]; }

- (NSString *)applicationVersionString
{ return [self _infoPlistValueForBundle:_applicationBundle withKey:@"CFBundleShortVersionString"]; }

- (NSString *)applicationVersion
{ return [self _infoPlistValueForBundle:_applicationBundle withKey:@"CFBundleVersion"]; }

- (NSString *)applicationIdentifier
{ return [self _infoPlistValueForBundle:_applicationBundle withKey:@"CFBundleIdentifier"]; }

- (NSString *)reportBundleName
{ return [self _infoPlistValueForBundle:_reportBundle withKey:@"CFBundleExecutable"]; }

- (NSString *)reportBundleVersionString
{ return [self _infoPlistValueForBundle:_reportBundle withKey:@"CFBundleShortVersionString"]; }

- (NSString *)reportBundleVersion
{ return [self _infoPlistValueForBundle:_reportBundle withKey:@"CFBundleVersion"]; }

- (NSString *)reportBundleIdentifier
{ return [self _infoPlistValueForBundle:_reportBundle withKey:@"CFBundleIdentifier"]; }

- (NSImage*)reportBundleIcon
{
    if (self.icon) {
        return self.icon;
    }
    NSString* iconName = _reportBundle.infoDictionary[@"CFBundleIconFile"];
    NSString* iconPath = [ _reportBundle pathForImageResource:iconName ];
    return [[ NSImage alloc] initByReferencingFile:iconPath ];
}

- (void)_logAtLevel:(BWLogLevel)level message:(NSString *)message
{
    if ([self.delegate respondsToSelector:@selector(logAtLevel:message:)]) {
        [self.delegate logAtLevel:level message:message];
    }
}

/*
 *
 *
 *================================================================================================*/
#pragma mark - Utilities
/*==================================================================================================
 */


- (NSString *)_infoPlistValueForBundle:(NSBundle *)bundle withKey:(NSString *)infoPlistKey
{
    NSString *infoPlistValue = [bundle.localizedInfoDictionary valueForKey:infoPlistKey];
    return infoPlistValue ?: [bundle.infoDictionary valueForKey:infoPlistKey];
}

@end
