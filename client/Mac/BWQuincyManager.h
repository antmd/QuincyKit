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

#import <Cocoa/Cocoa.h>
#import "BWDelegateLogger-Protocol.h"


typedef enum CrashAlertType {
  CrashAlertTypeSend = 0,
  CrashAlertTypeFeedback = 1,
} CrashAlertType;

typedef enum CrashReportStatus {
  // This app version is set to discontinued, no new crash reports accepted by the server
  CrashReportStatusFailureVersionDiscontinued = -30,
    
  // XML: Sender ersion string contains not allowed characters, only alphanumberical including space and . are allowed
  CrashReportStatusFailureXMLSenderVersionNotAllowed = -21,
    
  // XML: Version string contains not allowed characters, only alphanumberical including space and . are allowed
  CrashReportStatusFailureXMLVersionNotAllowed = -20,
    
  // SQL for adding a symoblicate todo entry in the database failed
  CrashReportStatusFailureSQLAddSymbolicateTodo = -18,
    
  // SQL for adding crash log in the database failed
  CrashReportStatusFailureSQLAddCrashlog = -17,
    
  // SQL for adding a new version in the database failed
  CrashReportStatusFailureSQLAddVersion = -16,
  
  // SQL for checking if the version is already added in the database failed
  CrashReportStatusFailureSQLCheckVersionExists = -15,
  
  // SQL for creating a new pattern for this bug and set amount of occurrances to 1 in the database failed
  CrashReportStatusFailureSQLAddPattern = -14,
  
  // SQL for checking the status of the bugfix version in the database failed
  CrashReportStatusFailureSQLCheckBugfixStatus = -13,
  
  // SQL for updating the occurances of this pattern in the database failed
  CrashReportStatusFailureSQLUpdatePatternOccurances = -12,
  
  // SQL for getting all the known bug patterns for the current app version in the database failed
  CrashReportStatusFailureSQLFindKnownPatterns = -11,
  
  // SQL for finding the bundle identifier in the database failed
  CrashReportStatusFailureSQLSearchAppName = -10,
  
  // the post request didn't contain valid data
  CrashReportStatusFailureInvalidPostData = -3,
  
  // incoming data may not be added, because e.g. bundle identifier wasn't found
  CrashReportStatusFailureInvalidIncomingData = -2,
  
  // database cannot be accessed, check hostname, username, password and database name settings in config.php
  CrashReportStatusFailureDatabaseNotAvailable = -1,
  
  CrashReportStatusUnknown = 0,
  
  CrashReportStatusAssigned = 1,
  
  CrashReportStatusSubmitted = 2,
  
  CrashReportStatusAvailable = 3,
} CrashReportStatus;

// A separator used in composite crash logs to separate individual crash logs
extern NSString* BWCrashLogSeparator ;
/*
 *
 *
 *================================================================================================*/
#pragma mark - BWQuincyManagerDelegate Protocol
/*==================================================================================================
 */


@class BWQuincyUI;
@class BWQuincyManager;

@protocol BWQuincyManagerDelegate <BWDelegateLogger>

@required

// Invoked once the modal sheets are gone
- (void) showMainApplicationWindow;

@optional

// Return the description the crashreport should contain, empty by default. The string will automatically be wrapped into <[DATA[ ]]>, so make sure you don't do that in your string.
-(NSString *) crashReportDescription;

// Return the userid the crashreport should contain, empty by default
-(NSString *) crashReportUserID;

// Return the contact value (e.g. email) the crashreport should contain, empty by default
-(NSString *) crashReportContact;

// Filtering of crash reports
-(BOOL) diagnosticReportFileIsValid:(NSString*)diagnosticReportFile manager:(BWQuincyManager*)manager;

// Notify delegate that UI will show (e.g. to unhide this app)
-(void)uiWillBeShown;

// Notify delegate when crash reporting has completed
-(void)crashReportingCompleted;
@end


/*
 *
 *
 *================================================================================================*/
#pragma mark - BWQuincyManager
/*==================================================================================================
 */

@interface BWQuincyManager : NSObject <NSXMLParserDelegate,NSURLConnectionDelegate>

- (NSString*) modelVersion;

/// The bundle of the application or plugin to be reported on
/*! In the case of a plugin, this will be the bundle of the plugin, not the main app
 */
@property (nonatomic, strong, readonly) NSBundle* applicationBundle;
@property (nonatomic, strong, readonly) NSBundle* reportBundle;

// submission URL defines where to send the crash reports to (required)
@property (nonatomic, copy) NSString *submissionURL;

// defines the company name to be shown in the crash reporting dialog
@property (nonatomic, copy) NSString *companyName;

// delegate is required
@property (nonatomic, weak) id <BWQuincyManagerDelegate> delegate;

// if YES, the crash report will be submitted without asking the user
// if NO, the user will be asked if the crash report can be submitted (default)
@property (nonatomic, getter=isAutoSubmitCrashReport) BOOL autoSubmitCrashReport;

// Delay in seconds before showing any pending crash report dialog
@property (nonatomic) NSTimeInterval delaySecsBeforeShowingCrashReportDialog;

///////////////////////////////////////////////////////////////////////////////////////////////////
// settings

// If you want to use HockeyApp instead of your own server, this is required
@property (nonatomic, copy) NSString *appIdentifier;


- (id) initWithDelegate:(id<BWQuincyManagerDelegate>)delegate applicationBundle:(NSBundle*)bundle reportBundle:(NSBundle*)pluginBundle;
- (id) initWithDelegate:(id<BWQuincyManagerDelegate>)delegate applicationBundle:(NSBundle*)bundle;
- (void) startManager;
- (void) cancelReport;
- (void) sendReportCrash:(NSString*)crashContent
             description:(NSString*)description;
+(NSString*)makeReportFromCrashFile:(NSString*)crashFile;

/// Readonly properties extracted from Info.plist of 'bundle'
@property (nonatomic,readonly) NSString *applicationName;
@property (nonatomic,readonly) NSString *applicationVersionString;
@property (nonatomic,readonly) NSString *applicationVersion;
@property (nonatomic,readonly) NSString *applicationIdentifier;

/// Readonly properties extracted from Info.plist of the application/bundle to be reported
/*! The 'reportBundle' is the same as the 'application' by default, but if 'reportBundle'
 *  is set, then the reportBundle information is used to obtain the details for crash reports.
 *  This allows us to look for crash reports from a main application, but report on a plugin
 *  integrated into the application
 */
@property (nonatomic,copy,readonly) NSString *reportBundleName;
@property (nonatomic,copy,readonly) NSString *reportBundleVersionString;
@property (nonatomic,copy,readonly) NSString *reportBundleVersion;
@property (nonatomic,copy,readonly) NSString *reportBundleIdentifier;
@property (nonatomic,copy,readonly) NSImage  *reportBundleIcon;
@end
