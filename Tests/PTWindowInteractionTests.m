#import <Cocoa/Cocoa.h>
#import <objc/message.h>

@interface PTEffortSlider : NSControl
@property(nonatomic) NSInteger selectedIndex;
- (void)handleEffortClick:(NSClickGestureRecognizer *)recognizer;
- (void)handleEffortPan:(NSPanGestureRecognizer *)recognizer;
@end

@interface PTTestGestureRecognizer : NSGestureRecognizer
@property(nonatomic) NSGestureRecognizerState reportedState;
@property(nonatomic) NSPoint reportedLocation;
@end

@implementation PTTestGestureRecognizer
- (NSGestureRecognizerState)state { return self.reportedState; }
- (NSPoint)locationInView:(NSView *)view { (void)view; return self.reportedLocation; }
@end

@interface PTEffortActionProbe : NSObject
@property(nonatomic) NSUInteger count;
@end


@implementation PTEffortActionProbe
- (void)changed:(id)sender {
    (void)sender;
    self.count += 1;
}
@end

static void PTAssert(BOOL condition, NSString *message) {
    if (condition) return;
    NSLog(@"FAIL: %@", message);
    exit(1);
}

static void PTCallNoArgument(id object, SEL selector) {
    ((void (*)(id, SEL))objc_msgSend)(object, selector);
}

static void PTCallOneObject(id object, SEL selector, id argument) {
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
}

static id PTCallOneObjectReturningObject(id object, SEL selector, id argument) {
    return ((id (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
}

static void PTCallObjectAndUnsigned(id object, SEL selector, id argument, NSUInteger value) {
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(object, selector, argument, value);
}

static void PTPumpRunLoop(NSTimeInterval duration) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:duration];
    while ([deadline timeIntervalSinceNow] > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

static NSString *PTRunTestGit(NSString *directory, NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithObjects:@"-C", directory, nil];
    [all addObjectsFromArray:arguments];
    NSPipe *pipe = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.arguments = all;
    task.standardOutput = pipe;
    task.standardError = pipe;
    PTAssert([task launchAndReturnError:nil], @"test Git command must launch");
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    PTAssert(task.terminationStatus == 0,
        [NSString stringWithFormat:@"test Git command failed: %@",
            [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static BOOL PTViewIsOrDescendsFromView(NSView *view, NSView *ancestor) {
    for (NSView *candidate = view; candidate; candidate = candidate.superview) {
        if (candidate == ancestor) return YES;
    }
    return NO;
}

static NSButton *PTFirstButtonInStack(NSStackView *stack) {
    for (NSView *view in stack.arrangedSubviews) {
        if ([view isKindOfClass:NSButton.class]) return (NSButton *)view;
    }
    return nil;
}

static void PTCollectDescendants(NSView *root, NSMutableArray<NSView *> *views) {
    for (NSView *view in root.subviews) {
        [views addObject:view];
        PTCollectDescendants(view, views);
    }
}

static NSArray<NSView *> *PTAllDescendants(NSView *root) {
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    PTCollectDescendants(root, views);
    return views;
}

static void PTAssertButtonHitTest(NSWindow *window, NSButton *button, NSString *stage) {
    [window.contentView layoutSubtreeIfNeeded];
    [button scrollRectToVisible:button.bounds];
    [window.contentView layoutSubtreeIfNeeded];
    PTAssert(button.frame.size.width > 0 && button.frame.size.height > 0,
        [NSString stringWithFormat:@"%@ must keep a non-empty button frame", stage]);
    NSPoint center = NSMakePoint(NSMidX(button.bounds), NSMidY(button.bounds));
    NSPoint contentPoint = [button convertPoint:center toView:window.contentView];
    NSView *hit = [window.contentView hitTest:contentPoint];
    PTAssert(PTViewIsOrDescendsFromView(hit, button),
        [NSString stringWithFormat:@"%@ hit %@ instead of the target button",
            stage, NSStringFromClass(hit.class)]);
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        PTEffortSlider *effortSlider = [[PTEffortSlider alloc] initWithFrame:NSMakeRect(0, 0, 260, 62)];
        PTEffortActionProbe *effortProbe = [[PTEffortActionProbe alloc] init];
        effortSlider.target = effortProbe;
        effortSlider.action = @selector(changed:);
        BOOL hasClickRecognizer = NO;
        BOOL hasPanRecognizer = NO;
        for (NSGestureRecognizer *recognizer in effortSlider.gestureRecognizers) {
            hasClickRecognizer |= [recognizer isKindOfClass:NSClickGestureRecognizer.class];
            hasPanRecognizer |= [recognizer isKindOfClass:NSPanGestureRecognizer.class];
        }
        PTAssert(hasClickRecognizer && hasPanRecognizer,
            @"effort slider must install real click and drag recognizers");

        PTTestGestureRecognizer *click = [[PTTestGestureRecognizer alloc] init];
        click.reportedState = NSGestureRecognizerStateEnded;
        click.reportedLocation = NSMakePoint(238, 31);
        effortSlider.selectedIndex = 1;
        [effortSlider handleEffortClick:(id)click];
        PTAssert(effortProbe.count == 0,
            @"effort clicks must wait until gesture dispatch has fully returned");
        PTPumpRunLoop(0.03);
        PTAssert(effortProbe.count == 1 && effortSlider.selectedIndex == 4,
            @"one click must select its stop and emit exactly one deferred effort command");

        PTTestGestureRecognizer *pan = [[PTTestGestureRecognizer alloc] init];
        effortSlider.selectedIndex = 1;
        pan.reportedState = NSGestureRecognizerStateBegan;
        pan.reportedLocation = NSMakePoint(70, 31);
        [effortSlider handleEffortPan:(id)pan];
        pan.reportedState = NSGestureRecognizerStateChanged;
        pan.reportedLocation = NSMakePoint(238, 31);
        [effortSlider handleEffortPan:(id)pan];
        pan.reportedState = NSGestureRecognizerStateEnded;
        [effortSlider handleEffortPan:(id)pan];
        PTAssert(effortProbe.count == 1,
            @"effort drags must not submit while pointer tracking is active");
        PTPumpRunLoop(0.03);
        PTAssert(effortProbe.count == 2 && effortSlider.selectedIndex == 4,
            @"one drag must emit exactly one deferred effort command");
        [NSUserDefaults.standardUserDefaults setObject:@"zh-Hans" forKey:@"PTInterfaceLanguage"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"PTGitObservedDirectories"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"PTGitSuppressedDirectories"];
        id delegate = [[NSClassFromString(@"PTAppDelegate") alloc] init];
        PTAssert(delegate != nil, @"PTAppDelegate must be loadable");
        PTCallNoArgument(delegate, NSSelectorFromString(@"buildWindow"));
        PTCallNoArgument(delegate, NSSelectorFromString(@"buildQuestionPanelIfNeeded"));

        NSWindow *window = [delegate valueForKey:@"window"];
        NSPanel *questionPanel = [delegate valueForKey:@"questionPanel"];
        PTAssert(questionPanel != nil && questionPanel.movableByWindowBackground,
            @"MCP question panel must use its custom draggable surface");
        PTAssert([questionPanel standardWindowButton:NSWindowCloseButton].hidden &&
            [questionPanel standardWindowButton:NSWindowMiniaturizeButton].hidden &&
            [questionPanel standardWindowButton:NSWindowZoomButton].hidden,
            @"MCP question panel must hide all native traffic-light buttons");
        NSButton *customSubmit = nil;
        NSButton *customClose = nil;
        for (NSView *view in PTAllDescendants(questionPanel.contentView)) {
            if ([view isKindOfClass:NSButton.class] &&
                [((NSButton *)view).title hasPrefix:@"提交回答"]) {
                customSubmit = (NSButton *)view;
            }
            if ([view isKindOfClass:NSButton.class] &&
                [((NSButton *)view).title isEqual:@"×"]) {
                customClose = (NSButton *)view;
            }
        }
        PTAssert(customSubmit != nil && [customSubmit isKindOfClass:NSClassFromString(@"PTAnimatedButton")] &&
            !customSubmit.bordered && customSubmit.focusRingType == NSFocusRingTypeNone,
            @"MCP submit control must be a borderless custom animated button");
        PTAssert(customClose != nil && [customClose isKindOfClass:NSClassFromString(@"PTAnimatedButton")],
            @"MCP panel must expose its custom close control");

        NSDictionary *questionFixture = @{
            @"question": @"选择哪一种？", @"header": @"方式", @"multiSelect": @NO,
            @"options": @[
                @{ @"label": @"甲", @"description": @"第一种方案" },
                @{ @"label": @"乙", @"description": @"第二种方案" }
            ]
        };
        NSView *questionCard = PTCallOneObjectReturningObject(delegate,
            NSSelectorFromString(@"buildQuestionBlockForQuestion:"), questionFixture);
        NSUInteger customOptionCount = 0;
        NSTextField *customAnswerField = nil;
        for (NSView *view in PTAllDescendants(questionCard)) {
            if ([view isKindOfClass:NSClassFromString(@"PTQuestionOptionButton")]) {
                customOptionCount++;
                NSButton *button = (NSButton *)view;
                PTAssert(!button.bordered && button.focusRingType == NSFocusRingTypeNone,
                    @"MCP options must not expose native AppKit button chrome");
            }
            if ([view isKindOfClass:NSTextField.class] &&
                [((NSTextField *)view).placeholderString containsString:@"没有符合的选项"]) {
                customAnswerField = (NSTextField *)view;
            }
        }
        PTAssert(customOptionCount == 2,
            @"every MCP answer option must use the custom vertical option control");
        PTAssert(customAnswerField != nil && !customAnswerField.bordered &&
            !customAnswerField.bezeled && customAnswerField.focusRingType == NSFocusRingTypeNone,
            @"MCP custom-answer input must have no native bezel or focus ring");

        NSDictionary *questionRequest = @{
            @"id": @"interaction-test",
            @"questions": @[ questionFixture ]
        };
        PTCallOneObject(delegate, NSSelectorFromString(@"presentQuestionRequest:"), questionRequest);
        [questionPanel.contentView layoutSubtreeIfNeeded];
        NSArray<NSView *> *panelViews = PTAllDescendants(questionPanel.contentView);
        NSMutableArray<NSButton *> *questionButtons = [NSMutableArray array];
        for (NSView *view in panelViews) {
            if ([view isKindOfClass:NSClassFromString(@"PTQuestionOptionButton")]) {
                [questionButtons addObject:(NSButton *)view];
            }
        }
        PTAssert(questionButtons.count == 2,
            @"the presented MCP panel must contain both custom answer buttons");
        for (NSButton *button in questionButtons) {
            [button scrollRectToVisible:button.bounds];
            [questionPanel.contentView layoutSubtreeIfNeeded];
            NSPoint center = NSMakePoint(NSMidX(button.bounds), NSMidY(button.bounds));
            NSPoint panelPoint = [button convertPoint:center toView:questionPanel.contentView];
            NSView *hit = [questionPanel.contentView hitTest:panelPoint];
            PTAssert(PTViewIsOrDescendsFromView(hit, button),
                [NSString stringWithFormat:@"MCP answer button hit %@ instead of itself",
                    NSStringFromClass(hit.class)]);
            PTAssert([button acceptsFirstMouse:nil],
                @"MCP answer buttons must react on the click that activates the floating panel");
        }
        [questionButtons[0] performClick:nil];
        PTAssert(questionButtons[0].state == NSControlStateValueOn,
            @"clicking a custom MCP option must select it");
        [questionButtons[1] performClick:nil];
        PTAssert(questionButtons[0].state == NSControlStateValueOff &&
            questionButtons[1].state == NSControlStateValueOn,
            @"clicking another single-choice option must move the selection");
        PTAssertButtonHitTest(questionPanel, customSubmit, @"MCP submit control");
        PTAssertButtonHitTest(questionPanel, customClose, @"MCP close control");
        [questionPanel orderOut:nil];
        NSStackView *changedFiles = [delegate valueForKey:@"changedFilesStack"];
        NSSplitView *splitView = [delegate valueForKey:@"splitView"];
        NSView *inspector = [delegate valueForKey:@"inspectorView"];
        NSPopUpButton *gitDirectoryPicker = [delegate valueForKey:@"gitDirectoryPicker"];
        NSButton *removeGitDirectoryButton = [delegate valueForKey:@"removeGitDirectoryButton"];
        NSTextField *gitDirectoryInput = [delegate valueForKey:@"gitDirectoryInput"];
        NSTextField *gitDirectoryHint = [delegate valueForKey:@"gitDirectoryHintLabel"];
        NSScrollView *gitDiffScroll = [delegate valueForKey:@"gitDiffScroll"];
        NSTextView *gitDiffTextView = [delegate valueForKey:@"gitDiffTextView"];
        NSProgressIndicator *gitDiffProgress = [delegate valueForKey:@"gitDiffProgress"];
        NSButton *compactButton = [delegate valueForKey:@"compactButton"];
        NSTextField *contextLabel = [delegate valueForKey:@"inspectorContextLabel"];
        NSTextField *contextPercent = [delegate valueForKey:@"inspectorContextPercentLabel"];
        NSView *contextMeter = [delegate valueForKey:@"inspectorContextMeter"];
        NSStackView *contextDetailStack = [delegate valueForKey:@"inspectorContextDetailStack"];
        NSButton *contextDisclosure = [delegate valueForKey:@"contextDisclosureButton"];
        PTAssert(window != nil && changedFiles != nil && splitView != nil && inspector != nil &&
            gitDirectoryPicker != nil && removeGitDirectoryButton != nil &&
            gitDirectoryInput != nil && gitDirectoryHint != nil && gitDiffScroll != nil &&
            gitDiffTextView != nil && gitDiffProgress != nil && compactButton != nil &&
            contextLabel != nil && contextPercent != nil && contextMeter != nil &&
            contextDetailStack != nil && contextDisclosure != nil,
            @"window, inspector, Git controls, and changed-files stack must exist");
        PTAssert([compactButton.title isEqual:@"Compact"] &&
                 compactButton.action == NSSelectorFromString(@"compactConversation:") &&
                 !compactButton.enabled,
            @"Compact must be a dedicated command button disabled before Terminal sync");

        NSTextView *pasteComposer = [delegate valueForKey:@"composerTextView"];
        PTAssert(pasteComposer != nil, @"main composer must exist for paste focus regression coverage");
        pasteComposer.string = @"composer must stay unchanged";
        gitDirectoryInput.stringValue = @"";
        [window makeKeyAndOrderFront:nil];
        PTAssert([window makeFirstResponder:gitDirectoryInput],
            @"Git directory input must accept keyboard focus");
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:@"/tmp" forType:NSPasteboardTypeString];
        NSEvent *pasteEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown
            location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0
            windowNumber:window.windowNumber context:nil characters:@"v"
            charactersIgnoringModifiers:@"v" isARepeat:NO keyCode:9];
        PTAssert(![pasteComposer performKeyEquivalent:pasteEvent],
            @"an unfocused composer must not intercept Command-V from the Git path field");
        PTAssert([pasteComposer.string isEqual:@"composer must stay unchanged"],
            @"Git path paste must never leak into the message composer");
        [(NSText *)window.firstResponder paste:nil];
        PTAssert([gitDirectoryInput.stringValue isEqual:@"/tmp"],
            @"the focused Git directory input must receive the pasted path exactly once");
        pasteComposer.string = @"";

        [window.contentView layoutSubtreeIfNeeded];
        CGFloat splitWidth = NSWidth(splitView.bounds);
        [splitView setPosition:splitWidth - 320.0 ofDividerAtIndex:1];
        CGFloat immediateWideInspectorWidth = NSWidth(inspector.frame);
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat wideInspectorWidth = NSWidth(inspector.frame);
        [splitView setPosition:splitWidth - 230.0 ofDividerAtIndex:1];
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat narrowInspectorWidth = NSWidth(inspector.frame);
        PTAssert(wideInspectorWidth > narrowInspectorWidth + 60.0,
            [NSString stringWithFormat:@"inspector divider must resize its pane (immediate %.1f wide %.1f narrow %.1f)",
                immediateWideInspectorWidth, wideInspectorWidth, narrowInspectorWidth]);
        NSRect proposedHitRect = NSMakeRect(800.0, 0.0, 3.0, NSHeight(splitView.bounds));
        NSRect expandedHitRect = [(id<NSSplitViewDelegate>)splitView.delegate
            splitView:splitView
            effectiveRect:proposedHitRect
            forDrawnRect:proposedHitRect
            ofDividerAtIndex:1];
        PTAssert(NSWidth(expandedHitRect) >= NSWidth(proposedHitRect) + 10.0,
            @"thin inspector divider must expose a reliably draggable hit target");

        id session = [[NSClassFromString(@"PTSessionInfo") alloc] init];
        [session setValue:@56600 forKey:@"contextUsed"];
        [session setValue:@967000 forKey:@"contextWindow"];
        [session setValue:@[
            @{@"category": @"system_prompt", @"tokens": @9300, @"percentage": @1.0},
            @{@"category": @"messages", @"tokens": @22500, @"percentage": @2.3},
            @{@"category": @"free_space", @"tokens": @877400, @"percentage": @90.7},
            @{@"category": @"autocompact_buffer", @"tokens": @33000, @"percentage": @3.4}
        ] forKey:@"contextBreakdown"];
        [session setValue:@"session-local-review" forKey:@"sessionID"];
        [session setValue:@[@"/tmp"] forKey:@"accessedDirectories"];
        [session setValue:@"/tmp" forKey:@"cwd"];
        [session setValue:@[@{
            @"displayName": @"interaction-test.txt",
            @"filePath": @"/tmp/interaction-test.txt",
            @"added": @1,
            @"removed": @0
        }] forKey:@"changedFiles"];
        [session setValue:@[] forKey:@"tasks"];
        [session setValue:@[
            @{@"kind": @"user", @"text": @"change it"},
            @{
                @"kind": @"diff",
                @"toolName": @"Edit",
                @"filePath": @"/tmp/TranscriptOnly.m",
                @"oldText": @"before local",
                @"newText": @"after local"
            }
        ] forKey:@"assistantMessages"];
        [delegate setValue:session forKey:@"selectedSession"];
        [delegate setValue:@[session] forKey:@"sessions"];
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert([contextLabel.stringValue isEqual:@"57K / 967K tokens"] &&
            [contextPercent.stringValue isEqual:@"5.9%"],
            @"context card must keep the exact usage headline visible");
        PTAssert([[contextMeter valueForKey:@"progress"] doubleValue] > 0.05 &&
            contextDetailStack.hidden && contextDisclosure.enabled,
            @"context status meter must stay visible while real category details start collapsed");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleContextDetail:"), nil);
        PTAssert(!contextDetailStack.hidden && contextDetailStack.arrangedSubviews.count == 4,
            @"context disclosure must expand the parsed /context categories");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleContextDetail:"), nil);
        PTAssert(contextDetailStack.hidden && !contextMeter.hidden,
            @"collapsing context details must never hide the persistent status meter");

        [session setValue:@[] forKey:@"contextBreakdown"];
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(contextDisclosure.enabled,
            @"Details must remain clickable when total usage exists before /context categories arrive");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleContextDetail:"), nil);
        PTAssert(!contextDetailStack.hidden && contextDetailStack.arrangedSubviews.count == 1,
            @"clicking Details without a breakdown must reveal a synchronization hint");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleContextDetail:"), nil);

        id secondSession = [[NSClassFromString(@"PTSessionInfo") alloc] init];
        [secondSession setValue:@42000 forKey:@"contextUsed"];
        [secondSession setValue:@1000000 forKey:@"contextWindow"];
        [secondSession setValue:@[] forKey:@"contextBreakdown"];
        [secondSession setValue:@"session-second-page" forKey:@"sessionID"];
        [secondSession setValue:@"/tmp" forKey:@"cwd"];
        [secondSession setValue:@[] forKey:@"accessedDirectories"];
        [secondSession setValue:@[] forKey:@"changedFiles"];
        [secondSession setValue:@[] forKey:@"tasks"];
        [secondSession setValue:@[] forKey:@"assistantMessages"];
        [delegate setValue:secondSession forKey:@"selectedSession"];
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), secondSession);
        PTAssert(contextDisclosure.enabled,
            @"Details must remain clickable after switching to another conversation page");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleContextDetail:"), nil);
        PTAssert(!contextDetailStack.hidden,
            @"Details must expand on every conversation page, not only the first selected session");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleContextDetail:"), nil);
        [delegate setValue:session forKey:@"selectedSession"];
        [delegate setValue:@[session, secondSession] forKey:@"sessions"];

        NSArray *waitingBaseline = [[session valueForKey:@"assistantMessages"] copy];
        PTCallOneObject(delegate,
            NSSelectorFromString(@"beginAwaitingClaudeReplyForSessionID:"),
            @"session-local-review");
        PTAssert([[delegate valueForKey:@"awaitingClaudeReply"] boolValue],
            @"a successfully submitted message must begin the visible Claude waiting state");
        NSMutableArray *messagesWithActivity = [waitingBaseline mutableCopy];
        [messagesWithActivity addObject:@{
            @"role": @"assistant",
            @"text": @"started",
            @"messageKey": @"waiting-activity"
        }];
        [session setValue:messagesWithActivity forKey:@"assistantMessages"];
        PTCallOneObject(delegate,
            NSSelectorFromString(@"reconcileAwaitingClaudeReplyWithSession:"), session);
        PTAssert(![[delegate valueForKey:@"awaitingClaudeReply"] boolValue],
            @"the first real assistant transcript event must dismiss the waiting state");
        [session setValue:waitingBaseline forKey:@"assistantMessages"];

        PTAssert([gitDirectoryPicker.selectedItem.representedObject isEqual:@"/tmp"],
            @"the inspector must remember and select directories observed in the Claude transcript");
        PTAssert(removeGitDirectoryButton.enabled,
            @"a remembered Git directory must expose its delete control");
        PTAssert([gitDirectoryHint.stringValue containsString:@"不会改变 Claude Code"] &&
            [gitDirectoryHint.stringValue containsString:@"/add-dir"],
            @"Git directory controls must explain the Claude Code boundary and /add-dir requirement");

        PTCallOneObject(delegate, NSSelectorFromString(@"removeSelectedGitDirectory:"), nil);
        PTAssert(!gitDirectoryPicker.enabled && !removeGitDirectoryButton.enabled,
            @"deleting the only remembered Git directory must empty and disable the picker row");
        PTAssert([[NSUserDefaults.standardUserDefaults arrayForKey:@"PTGitSuppressedDirectories"]
            containsObject:@"/tmp"],
            @"deleting a directory must persist its exclusion across conversation reopen");
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(!gitDirectoryPicker.enabled,
            @"polling the currently open transcript must not immediately restore a deleted directory");

        gitDirectoryInput.stringValue = @"/tmp";
        PTCallOneObject(delegate, NSSelectorFromString(@"addManualGitDirectory:"), nil);
        PTAssert([gitDirectoryPicker.selectedItem.representedObject isEqual:@"/tmp"],
            @"manual entry must restore a deleted Git directory immediately");
        PTAssert(![[NSUserDefaults.standardUserDefaults arrayForKey:@"PTGitSuppressedDirectories"]
            containsObject:@"/tmp"],
            @"manual re-add must explicitly clear the persistent exclusion");

        PTCallOneObject(delegate, NSSelectorFromString(@"removeSelectedGitDirectory:"), nil);
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(!gitDirectoryPicker.enabled,
            @"reopening a related conversation must not resurrect a persistently deleted directory");
        gitDirectoryInput.stringValue = @"/tmp";
        PTCallOneObject(delegate, NSSelectorFromString(@"addManualGitDirectory:"), nil);

        PTCallNoArgument(delegate, NSSelectorFromString(@"buildGitActionPopoverIfNeeded"));
        NSTextField *commitMessage = [delegate valueForKey:@"gitCommitMessageField"];
        NSButton *commitButton = [delegate valueForKey:@"gitCommitButton"];
        NSButton *commitAndPushButton = [delegate valueForKey:@"gitCommitAndPushButton"];
        NSButton *pushButton = [delegate valueForKey:@"gitPushButton"];
        PTAssert(commitMessage != nil && commitButton != nil && commitAndPushButton != nil && pushButton != nil,
            @"Git actions must expose manual commit, commit-and-push, and push controls");
        commitMessage.stringValue = @"";
        PTCallNoArgument(delegate, NSSelectorFromString(@"updateGitActionControls"));
        PTAssert(!commitButton.enabled && !commitAndPushButton.enabled && pushButton.enabled,
            @"commit actions must remain unavailable until the user types a message");
        commitMessage.stringValue = @"Manual test message";
        PTCallNoArgument(delegate, NSSelectorFromString(@"updateGitActionControls"));
        PTAssert(commitButton.enabled && commitAndPushButton.enabled,
            @"a manually entered commit message must enable commit actions");

        NSString *gitFixture = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-git-action-%@", NSUUID.UUID.UUIDString]];
        PTAssert([NSFileManager.defaultManager createDirectoryAtPath:gitFixture
            withIntermediateDirectories:YES attributes:nil error:nil],
            @"temporary Git fixture must be created");
        PTRunTestGit(gitFixture, @[@"init", @"-q"]);
        PTRunTestGit(gitFixture, @[@"config", @"user.name", @"PrettyTerm Tests"]);
        PTRunTestGit(gitFixture, @[@"config", @"user.email", @"tests@prettyterm.invalid"]);
        NSString *fixtureFile = [gitFixture stringByAppendingPathComponent:@"Review.txt"];
        PTAssert([@"before\n" writeToFile:fixtureFile atomically:YES
                                  encoding:NSUTF8StringEncoding error:nil],
            @"initial fixture file must be written");
        PTRunTestGit(gitFixture, @[@"add", @"Review.txt"]);
        PTRunTestGit(gitFixture, @[@"commit", @"-q", @"-m", @"Initial"]);
        PTAssert([@"after\n" writeToFile:fixtureFile atomically:YES
                                 encoding:NSUTF8StringEncoding error:nil],
            @"changed fixture file must be written");
        [delegate setValue:gitFixture forKey:@"gitObservedDirectory"];
        commitMessage.stringValue = @"Manual integration commit";
        PTCallNoArgument(delegate, NSSelectorFromString(@"updateGitActionControls"));
        PTCallOneObject(delegate, NSSelectorFromString(@"commitGitChanges:"), nil);
        NSDate *commitDeadline = [NSDate dateWithTimeIntervalSinceNow:8.0];
        while ([[delegate valueForKey:@"gitActionInFlight"] boolValue] &&
               commitDeadline.timeIntervalSinceNow > 0) {
            PTPumpRunLoop(0.02);
        }
        PTAssert(![[delegate valueForKey:@"gitActionInFlight"] boolValue],
            @"manual commit must finish without blocking the app");
        NSString *latestSubject = [PTRunTestGit(gitFixture, @[@"log", @"-1", @"--pretty=%s"])
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        PTAssert([latestSubject isEqual:@"Manual integration commit"],
            @"Git must receive exactly the user-entered commit message");
        [NSFileManager.defaultManager removeItemAtPath:gitFixture error:nil];
        [delegate setValue:@"/tmp" forKey:@"gitObservedDirectory"];

        PTCallObjectAndUnsigned(delegate,
            NSSelectorFromString(@"openTranscriptEditReviewForSessionID:turnIndex:"),
            @"session-local-review", 0);
        [window.contentView layoutSubtreeIfNeeded];
        PTPumpRunLoop(0.12);
        PTAssert(!gitDiffScroll.hidden,
            @"the per-turn review must open the inspector document");
        PTAssert([gitDiffTextView.string containsString:@"本轮本地修改"] &&
                 [gitDiffTextView.string containsString:@"before local"] &&
                 [gitDiffTextView.string containsString:@"after local"] &&
                 [gitDiffTextView.string containsString:@"未执行 git diff"],
            @"the per-turn review must show transcript Edit content without probing Git");
        PTAssert(![gitDiffTextView.string containsString:@"Git 审阅不可用"] &&
                 [[delegate valueForKey:@"gitReviewShowsTranscriptEdits"] boolValue],
            @"a non-repository Git observation directory must not affect local turn review");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleGitDiff:"), nil);
        [window.contentView layoutSubtreeIfNeeded];
        PTPumpRunLoop(0.18);
        PTAssert(gitDiffScroll.hidden,
            @"the local turn review must collapse through the shared review control");

        CGFloat compactInspectorWidth = NSWidth(inspector.frame);
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleGitDiff:"), nil);
        [window.contentView layoutSubtreeIfNeeded];
        PTPumpRunLoop(0.24);
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat expandedInspectorWidth = NSWidth(inspector.frame);
        PTAssert(!gitDiffScroll.hidden && expandedInspectorWidth > compactInspectorWidth + 100.0,
            [NSString stringWithFormat:@"clicking Git diff must reveal it and widen the inspector (hidden=%d compact=%.1f expanded=%.1f)",
                gitDiffScroll.hidden, compactInspectorWidth, expandedInspectorWidth]);
        PTPumpRunLoop(0.24);
        PTAssert(gitDiffScroll.alphaValue > 0.95,
            @"the Git review must finish its expansion fade at full opacity");
        PTAssert(NSWidth(gitDiffTextView.frame) > 0.0,
            @"the expanded Git diff text document must have a visible width");
        PTAssert(gitDiffTextView.richText && gitDiffScroll.borderType == NSNoBorder,
            @"Git review must use a styled native document instead of a terminal text box");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleGitDiff:"), nil);
        [window.contentView layoutSubtreeIfNeeded];
        PTPumpRunLoop(0.18);
        PTAssert(gitDiffScroll.hidden,
            @"clicking the expanded Git diff control again must collapse the diff view");

        NSButton *button = PTFirstButtonInStack(changedFiles);
        PTAssert(button != nil, @"changed-file action must render as a button");
        PTAssert([button acceptsFirstMouse:nil], @"changed-file button must accept first mouse");
        PTAssert(button.target == delegate && button.action == NSSelectorFromString(@"revealChangedFile:"),
            @"changed-file button must retain its explicit target and action");

        // JSONL 会在 Claude 回复期间持续修订，但改动文件列表往往没有变化。
        // 轮询刷新不能销毁一个可能正处于 mouseDown/mouseUp 之间的按钮。
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(PTFirstButtonInStack(changedFiles) == button,
            @"unchanged inspector data must preserve changed-file button identity");
        [session setValue:@[@{
            @"displayName": @"interaction-test.txt",
            @"filePath": @"/tmp/interaction-test.txt",
            @"added": @2,
            @"removed": @1
        }] forKey:@"changedFiles"];
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(PTFirstButtonInStack(changedFiles) == button,
            @"changed counts for the same path must preserve changed-file button identity");
        PTAssert([button.title containsString:@"+2"] && [button.title containsString:@"−1"],
            @"a reused changed-file button must still refresh its visible counts");

        PTAssertButtonHitTest(window, button, @"initial layout");

        NSArray<NSValue *> *frames = @[
            [NSValue valueWithRect:NSMakeRect(80, 90, 1180, 760)],
            [NSValue valueWithRect:NSMakeRect(360, 240, 1040, 680)],
            [NSValue valueWithRect:NSMakeRect(30, 40, 900, 600)],
            [NSValue valueWithRect:NSMakeRect(520, 120, 1320, 820)]
        ];
        NSUInteger index = 0;
        for (NSValue *value in frames) {
            [window setFrame:value.rectValue display:NO];
            PTAssertButtonHitTest(window, button,
                [NSString stringWithFormat:@"move/resize pass %lu", (unsigned long)++index]);
        }

        NSTextView *composer = [delegate valueForKey:@"composerTextView"];
        NSPopUpButton *languagePicker = [delegate valueForKey:@"languagePicker"];
        composer.string = @"unsent draft survives language switch";
        [languagePicker selectItemAtIndex:1];
        PTCallOneObject(delegate, NSSelectorFromString(@"changeInterfaceLanguage:"), languagePicker);
        NSWindow *englishWindow = [delegate valueForKey:@"window"];
        NSTextView *englishComposer = [delegate valueForKey:@"composerTextView"];
        NSButton *englishSend = [delegate valueForKey:@"sendButton"];
        PTAssert(englishWindow != window &&
                 [englishComposer.string isEqual:@"unsent draft survives language switch"],
            @"switching interface language must rebuild presentation without dropping the draft");
        PTAssert([englishSend.title isEqual:@"↑"],
            @"English mode must localize native controls");
        NSButton *englishCompact = [delegate valueForKey:@"compactButton"];
        PTAssert([englishCompact.title isEqual:@"Compact"] &&
                 [englishCompact.toolTip containsString:@"/compact"],
            @"Compact must survive the localized presentation rebuild");
        NSPopUpButton *englishPicker = [delegate valueForKey:@"languagePicker"];
        [englishPicker selectItemAtIndex:0];
        PTCallOneObject(delegate, NSSelectorFromString(@"changeInterfaceLanguage:"), englishPicker);
        PTAssert([[[delegate valueForKey:@"sendButton"] title] isEqual:@"↑"],
            @"Chinese mode must remain selectable after switching to English");
        NSLog(@"PTWindowInteractionTests passed");
    }
    return 0;
}
