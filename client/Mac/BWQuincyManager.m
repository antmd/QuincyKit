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
#import "BWDelegatedLoggingMacros.h"
#import <sys/sysctl.h>

#define SDK_NAME @"Quincy"
#define SDK_VERSION @"2.1.6"
NSString* BWCrashLogSeparator = @"**********\n\n";


@interface BWQuincyManager ()
@property (nonatomic,copy,readwrite) NSString *reportBundleName;
@property (nonatomic,copy,readwrite) NSString *reportBundleVersionString;
@property (nonatomic,copy,readwrite) NSString *reportBundleVersion;
@property (nonatomic,copy,readwrite) NSString *reportBundleIdentifier;
@property (nonatomic,copy,readwrite) NSImage  *reportBundleIcon;
@property (nonatomic,strong,readwrite) NSBundle* applicationBundle;
@property (nonatomic,strong,readwrite) NSBundle* reportBundle;
@end


@implementation BWQuincyManager {
    CrashReportStatus _serverResult;
    NSInteger _statusCode;
    NSMutableString *_contentOfProperty;
    NSString *_crashFile;
    BWQuincyUI *_quincyUI;
    NSMutableData *_receivedData;
    NSURLConnection *_urlConnection;
}

@synthesize delegate = _delegate;
@synthesize submissionURL = _submissionURL;
@synthesize companyName = _companyName;
@synthesize appIdentifier = _appIdentifier;
@synthesize autoSubmitCrashReport = _autoSubmitCrashReport;


+(NSString*)makeReportFromCrashFile:(NSString*)crashFile
{
    NSError* error;
    NSString *crashLogs = [NSString stringWithContentsOfFile:crashFile
                                                    encoding:NSUTF8StringEncoding
                                                       error:&error];
    NSString* lastCrash;
    if (!error) {
        lastCrash = [[crashLogs componentsSeparatedByString:BWCrashLogSeparator] lastObject];
    }

    return lastCrash;
}


- (id)initWithDelegate:(id<BWQuincyManagerDelegate>)delegate
        applicationBundle:(NSBundle *)bundle
             reportBundle:(NSBundle *)pluginBundle
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
        
        if (_reportBundle == nil || [_applicationBundle.bundleURL isEqual:_reportBundle.bundleURL]) {
            self.reportBundleName = self.applicationName;
            self.reportBundleVersion = self.applicationVersion;
            self.reportBundleIdentifier = self.applicationIdentifier;
            self.reportBundleVersionString = self.applicationVersionString;
            self.reportBundleIcon = [self _iconForBundle:_applicationBundle
                                                   named:[ self _infoPlistValueForBundle:_applicationBundle withKey:@"CFBundleIconFile"]];
        }
        else {
            NSURL* url = _reportBundle.bundleURL;
            // Use the CoreFoundation functtion instead of the NSBundle method, as NSBundle caches, and will not pick up on
            // changes during the same run of this program
            NSDictionary* infoDictionary = (__bridge_transfer  NSDictionary*) CFBundleCopyInfoDictionaryForURL( (__bridge CFURLRef) url );
            self.reportBundleName = infoDictionary[@"CFBundleExecutable"];
            self.reportBundleVersionString = infoDictionary[@"CFBundleShortVersionString"];
            self.reportBundleVersion = infoDictionary[@"CFBundleVersion"];
            self.reportBundleIdentifier = infoDictionary[@"CFBundleIdentifier"];
            self.reportBundleIcon = [self _iconForBundle:_reportBundle
                                                   named:infoDictionary[@"CFBundleIconFile"]];
        }

        self.companyName = @"";
    }
    return self;
}

- (id)initWithDelegate:(id<BWQuincyManagerDelegate>)delegate applicationBundle:(NSBundle *)bundle
{ return [self initWithDelegate:nil applicationBundle:bundle reportBundle:bundle]; }
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

    NSSortDescriptor *dateSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"modDate"
                                                                       ascending:YES];
    NSArray *sortedFiles = [filesWithModificationDate
            sortedArrayUsingDescriptors:[NSArray arrayWithObject:dateSortDescriptor]];

    NSPredicate *filterPredicate = [NSPredicate
            predicateWithFormat:@"name BEGINSWITH %@", self.applicationName];
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
            libraryDirectories = NSSearchPathForDirectoriesInDomains(
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
    id<BWQuincyManagerDelegate> delegate = self.delegate;
    if (delegate != nil && [delegate respondsToSelector:@selector(showMainApplicationWindow)])
        [delegate showMainApplicationWindow];
}


- (void)startManager
{
    LOG_DEBUG(@"Starting:\n\tApplication { name = %@, version = %@, identifier = %@ },\n\tReport "
               "Bundle { name = %@, version = %@, identifier = %@ }",
              self.applicationName, self.applicationVersion, self.applicationIdentifier,
              self.reportBundleName, self.reportBundleVersion, self.reportBundleIdentifier);

    id<BWQuincyManagerDelegate> delegate = self.delegate;
    BOOL hasValidPendingCrashReport = [self hasPendingCrashReport];
    if (hasValidPendingCrashReport) {
        if ([delegate respondsToSelector:@selector(diagnosticReportFileIsValid:manager:)]) {
            hasValidPendingCrashReport = [delegate diagnosticReportFileIsValid:_crashFile manager:self];
        }
    }


    if (hasValidPendingCrashReport) {
        NSString* crashLogText = [ BWQuincyManager makeReportFromCrashFile:_crashFile ];
        
        if (crashLogText.length > 0) {
            if (!self.autoSubmitCrashReport) {
                // Present 'Send Crash Report' query window
                _quincyUI = [[BWQuincyUI alloc] initWithManager:self
                                                   crashLogText:crashLogText
                                                    companyName:_companyName
                                                applicationName:self.reportBundleName];
                
                [ self performSelector:@selector(_showCrashReportDialog)
                            withObject:nil
                            afterDelay:self.delaySecsBeforeShowingCrashReportDialog ];
                return; // QuincyUI will call 'returnToMainApplication'
            }
            else {
            // Auto-submit crash report

                NSString *description = @"";

                if ([delegate respondsToSelector:@selector(crashReportDescription)]) {
                    description = [delegate crashReportDescription];
                }

                [self sendReportCrash:crashLogText description:description];
                return; // sendReportCrash:description: will call 'returnToMainApplication'
            }
        }
    }
    
    [self returnToMainApplication];
    [self _cleanupConnectionAndNotifyDelegate];
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



- (void)cancelReport
{
    LOG_INFO(@"User cancelled crash report.");
    [self returnToMainApplication];
    [self _cleanupConnectionAndNotifyDelegate];
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


    LOG_DEBUG(@"Sending Crash Report: %@", xml);
    [self returnToMainApplication];

    [self _postXML:[NSString stringWithFormat:@"<crashes>%@</crashes>", xml]
               toURL:[NSURL URLWithString:self.submissionURL]];
}


-(void)_showCrashReportDialog
{
    id<BWQuincyManagerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(uiWillBeShown)]) {
        [delegate uiWillBeShown];
    }
    [_quincyUI askCrashReportDetails];
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
    _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
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
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)urlResponse;
    _statusCode = [response statusCode];
    LOG_DEBUG(@"Received status code %lu from server.", _statusCode);

    [_receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [_receivedData appendData:data];
    LOG_DEBUG(@"Received %lu bytes.", data.length);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    LOG_ERROR(@"Connection failed! Error - %@ %@", [error localizedDescription],
              [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);
    [self _cleanupConnectionAndNotifyDelegate];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    LOG_DEBUG(@"Succeeded! Received %lu bytes of data", [_receivedData length]);
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
        LOG_DEBUG(@"Server result = %d", _serverResult);
        if (_serverResult == 0) {
            LOG_INFO(@"Crash report was submitted successfully.");
        }
        else {
            LOG_ERROR(@"Crash reporting failed with result %d", _serverResult);
        }
    }
    [self _cleanupConnectionAndNotifyDelegate];
}

- (void)_cleanupConnectionAndNotifyDelegate
{
    _urlConnection = nil;
    _receivedData = nil;
    id<BWQuincyManagerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(crashReportingCompleted)]) {
        [delegate crashReportingCompleted];
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


/*
 *
 *
 *================================================================================================*/
#pragma mark - Utilities
/*==================================================================================================
 */

- (NSImage *)_iconForBundle:(NSBundle*)bundle named:(NSString*)iconName
{
    NSString *iconPath = [bundle pathForImageResource:iconName];
    return [[NSImage alloc] initByReferencingFile:iconPath];
}


- (NSString *)_infoPlistValueForBundle:(NSBundle *)bundle withKey:(NSString *)infoPlistKey
{
    NSString *infoPlistValue = [bundle.localizedInfoDictionary valueForKey:infoPlistKey];
    return infoPlistValue ?: [bundle.infoDictionary valueForKey:infoPlistKey];
}


@end
