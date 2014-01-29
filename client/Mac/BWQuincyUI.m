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


const CGFloat kCommentsHeight = 105;
const CGFloat kDetailsHeight = 285;

@implementation BWQuincyUI

- (id)initWithManager:(BWQuincyManager *)quincyManager
          crashLogText:(NSString *)crashLogText
            companyName:(NSString *)companyName
        applicationName:(NSString *)applicationName
{

    self = [super initWithWindowNibName:@"BWQuincyMain"];

    if (self != nil) {
        _xml = nil;
        _quincyManager = quincyManager;
        self.crashLogText = crashLogText;
        self.companyName = companyName;
        self.applicationName = applicationName;
        self.icon = quincyManager.reportBundleIcon;
        self.showComments = YES;
        self.showDetails = NO;
    }
    return self;
}


- (void)awakeFromNib
{
    self.window.canHide = NO;
    crashLogTextView.editable = NO;
    crashLogTextView.selectable = NO;
    crashLogTextView.automaticSpellingCorrectionEnabled = NO;
    crashLogTextView.typingAttributes =
            @{NSFontAttributeName : [NSFont userFixedPitchFontOfSize:11.0]};
    if (!self.showComments) {
        self.commentTextFieldHeightConstraint.constant = 0.0;
    }
    if (!self.showDetails) {
        self.detailScrollViewHeightConstraint.constant = 2.0;
        self.detailsScrollView.hidden = YES;
    }
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
        self.commentTextFieldHeightConstraint.animator.constant = 0.0;
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
        { self.detailScrollViewHeightConstraint.animator.constant = 2.0; }
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
    [_quincyManager sendReportCrash:crashLogTextView.string description:notes];
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
    [[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Problem Report for %@",
                                                                         @"Window title"),
                                                       _applicationName]];

    crashLogTextView.string = self.crashLogText ?: @"";
    
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
