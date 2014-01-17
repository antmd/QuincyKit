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

#import "BWQuincyUI.h"
#import "BWQuincyManager.h"
#import <sys/sysctl.h>

#define CRASHREPORTSENDER_MAX_CONSOLE_SIZE 50000

const CGFloat kCommentsHeight = 105;
const CGFloat kDetailsHeight = 285;

@implementation BWQuincyUI

- (id)initWithManager:(BWQuincyManager *)quincyManager
              crashFile:(NSString *)crashFile
            companyName:(NSString *)companyName
        applicationName:(NSString *)applicationName
{

    self = [super initWithWindowNibName:@"BWQuincyMain"];

    if (self != nil) {
        _xml = nil;
        _quincyManager = quincyManager;
        _crashFile = crashFile;
        _companyName = companyName;
        _applicationName = applicationName;
        self.icon = quincyManager.reportBundleIcon;
        self.showComments = YES;
        self.showDetails = YES;
    }
    return self;
}


- (void)awakeFromNib
{
    crashLogTextView.editable = NO;
    crashLogTextView.selectable = NO;
    crashLogTextView.automaticSpellingCorrectionEnabled = NO;
    crashLogTextView.typingAttributes =
            @{NSFontAttributeName : [NSFont userFixedPitchFontOfSize:11.0]};
}


- (void)endCrashReporter { [self close]; }


- (IBAction)showComments:(id)sender
{

    if ([sender intValue]) {
        self.showComments = NO;
        self.commentTextFieldHeightConstraint.animator.constant = kCommentsHeight;
        self.showComments = YES;
    }
    else {
        self.showComments = NO;
        self.commentTextFieldHeightConstraint.animator.constant = 0;
    }
}


- (IBAction)showDetails:(id)sender
{
    if ([sender intValue]) {
        self.showDetails = NO;
        self.detailsScrollView.hidden = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context)
        { self.detailScrollViewHeightConstraint.animator.constant = kDetailsHeight; }
    completionHandler:nil ];
        self.showDetails = YES;
    }
    else {
        self.showDetails = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context)
        { self.detailScrollViewHeightConstraint.animator.constant = 2; }
    completionHandler:^{
            self.detailsScrollView.hidden = YES;
        } ];
    }
}


- (IBAction)hideDetails:(id)sender { [self setShowDetails:NO]; }


- (IBAction)cancelReport:(id)sender
{
    [self endCrashReporter];
    [NSApp stopModal];

    [_quincyManager cancelReport];
}

- (void)_sendReportAfterDelay
{
    NSMutableString *notes = [NSMutableString
            stringWithFormat:@"Comments:\n%@\n", descriptionTextField.stringValue];
    if (self.sendConsoleLog && _consoleContent.length > 0) {
        [notes appendString:@"\nConsole:\n"];
        [notes appendString:_consoleContent];
    }

    [_quincyManager sendReportCrash:_crashLogContent description:notes];
    _crashLogContent = nil;
}

- (IBAction)submitReport:(id)sender
{
    [submitButton setEnabled:NO];

    [self.window makeFirstResponder:nil];

    [self performSelector:@selector(_sendReportAfterDelay) withObject:nil afterDelay:0.01];

    [self endCrashReporter];
    [NSApp stopModal];
}


- (void)askCrashReportDetails
{
    NSError *error;

    [[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Problem Report for %@",
                                                                         @"Window title"),
                                                       _applicationName]];

    // get the crash log
    NSString *crashLogs = [NSString stringWithContentsOfFile:_crashFile
                                                    encoding:NSUTF8StringEncoding
                                                       error:&error];
    NSString *lastCrash = [[crashLogs componentsSeparatedByString:@"**********\n\n"] lastObject];

    _crashLogContent = lastCrash;

    if (self.sendConsoleLog) {
        // get the console log
        NSEnumerator *theEnum = [[[NSString stringWithContentsOfFile:@"/private/var/log/system.log"
                                                            encoding:NSUTF8StringEncoding
                                                               error:&error]
                                         componentsSeparatedByString:@"\n"] objectEnumerator];
        NSString *currentObject;
        NSMutableArray *applicationStrings = [NSMutableArray array];

        NSString *searchString = [_applicationName stringByAppendingString:@"["];
        while ((currentObject = [theEnum nextObject])) {
            if ([currentObject rangeOfString:searchString].location != NSNotFound)
                [applicationStrings addObject:currentObject];
        }

        _consoleContent = [[NSMutableString alloc] initWithString:@""];

        NSInteger i;
        for (i = ((NSInteger)[applicationStrings count]) - 1;
             (i >= 0 && i > ((NSInteger)[applicationStrings count]) - 100); i--) {
            [_consoleContent appendString:[applicationStrings objectAtIndex:i]];
            [_consoleContent appendString:@"\n"];
        }

        // Now limit the content to CRASHREPORTSENDER_MAX_CONSOLE_SIZE (default: 50kByte)
        if ([_consoleContent length] > CRASHREPORTSENDER_MAX_CONSOLE_SIZE) {
            _consoleContent = (NSMutableString *)[_consoleContent
                    substringWithRange:NSMakeRange([_consoleContent length] -
                                                           CRASHREPORTSENDER_MAX_CONSOLE_SIZE - 1,
                                                   CRASHREPORTSENDER_MAX_CONSOLE_SIZE)];
        }
    }

    [crashLogTextView setString:[NSString stringWithFormat:@"%@\n\n%@", _crashLogContent,
                                                           _consoleContent ?: @""]];


    NSBeep();
    [NSApp runModalForWindow:self.window];
}


/*
 *
 *
 *================================================================================================*/
#pragma mark - NSWindow Delegate
/*==================================================================================================
 */
- (BOOL)windowShouldClose:(id)sender
{
    [NSApp stopModal];
    [_quincyManager cancelReport];
    return YES;
}

/*
 *
 *
 *================================================================================================*/
#pragma mark - NSTextField Delegate
/*==================================================================================================
 */


- (BOOL)control:(NSControl *)control
                   textView:(NSTextView *)textView
        doCommandBySelector:(SEL)commandSelector
{
    BOOL commandHandled = NO;

    if (commandSelector == @selector(insertNewline:)) {
        [textView insertNewlineIgnoringFieldEditor:self];
        commandHandled = YES;
    }

    return commandHandled;
}

@end
