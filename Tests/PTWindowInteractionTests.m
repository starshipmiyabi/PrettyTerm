#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import <string.h>

FOUNDATION_EXPORT NSData *PTPNGDataForImageFileURL(NSURL *url);
FOUNDATION_EXPORT NSString *PTMessageByAppendingClaudeAttachMarkers(
    NSString *message, NSArray<NSString *> *filePaths);

@interface PTSessionInfo : NSObject
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *cwd;
@end

@interface PTClaudeBridge : NSObject
@property(nonatomic, copy) void (^statusChanged)(NSString *status);
@property(nonatomic, readonly) NSString *sessionID;
@property(nonatomic, readonly) BOOL running;
- (void)connectToSession:(PTSessionInfo *)session;
@end

@interface PTClaudeBridgeExactSessionProbe : PTClaudeBridge
@end

@implementation PTClaudeBridgeExactSessionProbe
- (NSArray<NSString *> *)allTerminalTTYsWithError:(NSString **)errorMessage {
    if (errorMessage) *errorMessage = nil;
    return @[@"/dev/ttys999"];
}
- (pid_t)claudePIDForTTY:(NSString *)tty {
    return [tty isEqual:@"/dev/ttys999"] ? 999 : 0;
}
- (NSString *)cwdForPID:(pid_t)pid {
    return pid == 999 ? @"" : @"";
}
- (NSDictionary *)sessionMetadataForPID:(pid_t)pid {
    return pid == 999 ? @{ @"pid": @999, @"sessionId": @"exact-session" } : nil;
}
@end

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

// Test wide desktop layouts independently of the test host's physical display.

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

static id PTCallNoArgumentReturningObject(id object, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static void PTCallOneObject(id object, SEL selector, id argument) {
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
}

static void PTCallTwoObjects(id object, SEL selector, id firstArgument, id secondArgument) {
    ((void (*)(id, SEL, id, id))objc_msgSend)(object, selector, firstArgument, secondArgument);
}

static id PTCallOneObjectReturningObject(id object, SEL selector, id argument) {
    return ((id (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
}

static void PTCallObjectAndUnsigned(id object, SEL selector, id argument, NSUInteger value) {
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(object, selector, argument, value);
}

static BOOL PTCallObjectAndBoolReturningBool(id object, SEL selector, id argument, BOOL value) {
    return ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(object, selector, argument, value);
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
    NSMutableString *hitChain = [NSMutableString string];
    for (NSView *view = hit; view; view = view.superview) {
        [hitChain appendFormat:@" %@%@", NSStringFromClass(view.class), NSStringFromRect(view.frame)];
    }
    PTAssert(PTViewIsOrDescendsFromView(hit, button),
        [NSString stringWithFormat:@"%@ hit %@ instead of the target button (button=%@ contentPoint=%@ hitFrame=%@ value=%@ parent=%@ chain=%@)",
            stage, NSStringFromClass(hit.class), NSStringFromRect(button.frame),
            NSStringFromPoint(contentPoint), NSStringFromRect(hit.frame),
            [hit isKindOfClass:NSTextField.class] ? ((NSTextField *)hit).stringValue : @"",
            NSStringFromClass(hit.superview.class), hitChain]);
}

int main(void) {
    @autoreleasepool {
        NSTextView *submittedComposer = [[NSClassFromString(@"PTComposerTextView") alloc]
            initWithFrame:NSMakeRect(0, 0, 320, 60)];
        submittedComposer.string = @"已成功发送的消息";
        submittedComposer.editable = YES;
        PTCallOneObject(submittedComposer,
            NSSelectorFromString(@"clearAfterSuccessfulSubmissionMatchingText:"),
            @"已成功发送的消息");
        PTAssert(submittedComposer.string.length == 0 && submittedComposer.editable,
            @"a successful send must clear its exact submitted snapshot");

        (void)NSApplication.sharedApplication;
        PTClaudeBridgeExactSessionProbe *bridgeProbe =
            [[PTClaudeBridgeExactSessionProbe alloc] init];
        PTSessionInfo *bridgeSession = [[PTSessionInfo alloc] init];
        bridgeSession.sessionID = @"exact-session";
        bridgeSession.cwd = @"/expected/project";
        __block NSString *bridgeStatus = nil;
        bridgeProbe.statusChanged = ^(NSString *status) {
            bridgeStatus = status;
        };
        [bridgeProbe connectToSession:bridgeSession];
        NSDate *bridgeDeadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (!bridgeProbe.running && bridgeDeadline.timeIntervalSinceNow > 0) {
            PTPumpRunLoop(0.01);
        }
        PTAssert(bridgeProbe.running &&
            [bridgeProbe.sessionID isEqual:@"exact-session"] &&
            [bridgeStatus containsString:@"已同步 Terminal"],
            @"an exact Claude sessionId must bind even when cwd discovery is unavailable");

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
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"PTCollapsedSessionProjectPaths"];
        id delegate = [[NSClassFromString(@"PTAppDelegate") alloc] init];
        PTAssert(delegate != nil, @"PTAppDelegate must be loadable");
        [delegate setValue:[[NSClassFromString(@"PTAgentState") alloc] init]
                   forKey:@"agentState"];
        [delegate setValue:[NSMutableArray array] forKey:@"pendingImages"];
        [delegate setValue:[NSMutableArray array] forKey:@"pendingFiles"];
        [delegate setValue:[NSMutableArray array] forKey:@"floatingPendingImages"];
        [delegate setValue:[NSMutableArray array] forKey:@"floatingPendingFiles"];
        [delegate setValue:[NSMutableSet set] forKey:@"temporaryImagePaths"];
        [delegate setValue:[NSMutableArray array] forKey:@"workspaceTabs"];
        PTCallNoArgument(delegate, NSSelectorFromString(@"buildWindow"));
        PTCallNoArgument(delegate, NSSelectorFromString(@"buildQuestionPanelIfNeeded"));

        id firstWorkspaceTab = PTCallNoArgumentReturningObject(delegate,
            NSSelectorFromString(@"createWorkspaceTab"));
        id secondWorkspaceTab = PTCallNoArgumentReturningObject(delegate,
            NSSelectorFromString(@"createWorkspaceTab"));
        [delegate setValue:firstWorkspaceTab forKey:@"activeWorkspaceTab"];
        [delegate setValue:[firstWorkspaceTab valueForKey:@"bridge"] forKey:@"bridge"];
        PTCallNoArgument(delegate, NSSelectorFromString(@"updateWorkspaceTabBar"));
        NSStackView *workspaceTabStack = [delegate valueForKey:@"workspaceTabStack"];
        PTAssert(workspaceTabStack.arrangedSubviews.count == 3,
            @"two workspace tabs plus the new-tab control must be visible");
        NSMutableArray<NSButton *> *workspaceCloseButtons = [NSMutableArray array];
        for (NSView *item in workspaceTabStack.arrangedSubviews) {
            for (NSView *view in item.subviews) {
                if ([view isKindOfClass:NSButton.class] &&
                    ((NSButton *)view).action == NSSelectorFromString(@"closeWorkspaceTab:")) {
                    [workspaceCloseButtons addObject:(NSButton *)view];
                }
            }
        }
        PTAssert(workspaceCloseButtons.count == 2,
            @"every workspace tab must expose its own close control");
        NSWindow *workspaceWindow = [delegate valueForKey:@"window"];
        [workspaceWindow makeKeyAndOrderFront:nil];
        for (NSButton *button in workspaceCloseButtons) {
            PTAssertButtonHitTest(workspaceWindow, button, @"workspace tab close control");
            PTAssert([button acceptsFirstMouse:nil],
                @"workspace tab close must work on the click that activates the app");
        }
        [workspaceCloseButtons[1] performClick:nil];
        PTAssert([[delegate valueForKey:@"workspaceTabs"] count] == 1,
            @"closing an inactive workspace tab must remove only that tab");
        PTCallNoArgument(delegate, NSSelectorFromString(@"updateWorkspaceTabBar"));
        NSButton *remainingCloseButton = nil;
        for (NSView *item in workspaceTabStack.arrangedSubviews) {
            for (NSView *view in item.subviews) {
                if ([view isKindOfClass:NSButton.class] &&
                    ((NSButton *)view).action == NSSelectorFromString(@"closeWorkspaceTab:")) {
                    remainingCloseButton = (NSButton *)view;
                }
            }
        }
        [remainingCloseButton performClick:nil];
        PTAssert([[delegate valueForKey:@"workspaceTabs"] count] == 0 &&
            [delegate valueForKey:@"activeWorkspaceTab"] == nil &&
            workspaceTabStack.arrangedSubviews.count == 1,
            @"closing the last workspace tab must leave only the new-tab control");

        NSBitmapImageRep *sourceRep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:2 bitsPerSample:8
            samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        unsigned char fixturePixels[] = {
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255
        };
        memcpy(sourceRep.bitmapData, fixturePixels, sizeof(fixturePixels));
        NSData *sourcePNG = [sourceRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *imagePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"PrettyTerm-drag-test-%@.png", NSUUID.UUID.UUIDString]];
        PTAssert([sourcePNG writeToFile:imagePath atomically:YES],
            @"the drag regression fixture must be writable");
        NSURL *imageURL = [NSURL fileURLWithPath:imagePath];
        NSData *transportPNG = PTPNGDataForImageFileURL(imageURL);
        PTAssert([transportPNG isEqual:sourcePNG],
            @"a dragged PNG must reach the clipboard transport byte-for-byte without TIFF re-encoding");
        PTAssert(PTCallObjectAndBoolReturningBool(delegate,
            NSSelectorFromString(@"addComposerAttachmentURLs:floating:"), @[imageURL], NO),
            @"the main composer must accept the dragged image fixture");
        NSArray *pendingImages = [delegate valueForKey:@"pendingImages"];
        PTAssert(pendingImages.count == 1 &&
            [pendingImages.firstObject[@"pngData"] isEqual:sourcePNG],
            @"the pending drag attachment must retain the verified non-black PNG payload");
        PTCallNoArgument(delegate, NSSelectorFromString(@"clearPendingImagesAfterSuccessfulSend"));
        [NSFileManager.defaultManager removeItemAtPath:imagePath error:nil];

        NSString *folderPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"PrettyTerm folder attachment %@", NSUUID.UUID.UUIDString]];
        PTAssert([NSFileManager.defaultManager createDirectoryAtPath:folderPath
            withIntermediateDirectories:NO attributes:nil error:nil],
            @"the folder attachment fixture must be created");
        NSURL *folderURL = [NSURL fileURLWithPath:folderPath isDirectory:YES];
        PTAssert(PTCallObjectAndBoolReturningBool(delegate,
            NSSelectorFromString(@"addComposerAttachmentURLs:floating:"), @[folderURL], NO),
            @"the main composer must accept a dragged folder as one path attachment");
        NSArray *pendingFiles = [delegate valueForKey:@"pendingFiles"];
        PTAssert([pendingFiles isEqual:@[folderPath]],
            @"a dragged folder must retain its exact standardized path without enumerating contents");
        PTAssert(PTCallObjectAndBoolReturningBool(delegate,
            NSSelectorFromString(@"addComposerAttachmentURLs:floating:"), @[folderURL], YES),
            @"the floating composer must accept the same dragged folder path");
        NSArray *floatingPendingFiles = [delegate valueForKey:@"floatingPendingFiles"];
        PTAssert([floatingPendingFiles isEqual:@[folderPath]],
            @"the floating composer must retain a folder in its existing file-path queue");
        PTAssert([PTMessageByAppendingClaudeAttachMarkers(@"检查这个目录", pendingFiles)
            isEqual:[NSString stringWithFormat:@"检查这个目录\n\n<attach>%@</attach>", folderPath]],
            @"a folder attachment must use the existing inline attach marker, not a slash command");
        PTAssert(!PTCallObjectAndBoolReturningBool(delegate,
            NSSelectorFromString(@"addComposerAttachmentURLs:floating:"), @[folderURL], NO),
            @"dropping the same folder again must report that no new attachment was added");
        PTAssert([[delegate valueForKey:@"pendingFiles"] count] == 1,
            @"repeated folder drops must not duplicate its path attachment");
        PTCallNoArgument(delegate, NSSelectorFromString(@"clearPendingImagesAfterSuccessfulSend"));
        PTCallNoArgument(delegate, NSSelectorFromString(@"clearFloatingPendingImagesAfterSuccessfulSend"));
        [NSFileManager.defaultManager removeItemAtPath:folderPath error:nil];

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
        PTAssert([delegate respondsToSelector:
            NSSelectorFromString(@"setToolWorkspaceExpanded:animated:")] &&
            [delegate respondsToSelector:
            NSSelectorFromString(@"setInspectorExpanded:animated:")],
            @"the main window must expose animated workspace and inspector layout transitions");
        NSSplitView *workspaceSplitView = [delegate valueForKey:@"workspaceSplitView"];
        NSView *conversationPane = [delegate valueForKey:@"conversationPane"];
        NSView *toolWorkspace = [delegate valueForKey:@"toolWorkspaceView"];
        NSPopUpButton *gitDirectoryPicker = [delegate valueForKey:@"gitDirectoryPicker"];
        NSButton *removeGitDirectoryButton = [delegate valueForKey:@"removeGitDirectoryButton"];
        NSTextField *gitDirectoryInput = [delegate valueForKey:@"gitDirectoryInput"];
        NSTextField *gitDirectoryHint = [delegate valueForKey:@"gitDirectoryHintLabel"];
        NSScrollView *gitDiffScroll = [delegate valueForKey:@"gitDiffScroll"];
        NSTextView *gitDiffTextView = [delegate valueForKey:@"gitDiffTextView"];
        NSProgressIndicator *gitDiffProgress = [delegate valueForKey:@"gitDiffProgress"];
        NSButton *compactButton = [delegate valueForKey:@"compactButton"];
        NSButton *sendButton = [delegate valueForKey:@"sendButton"];
        NSButton *imageButton = [delegate valueForKey:@"imageButton"];
        NSTextField *composerTargetLabel = [delegate valueForKey:@"composerTargetLabel"];
        NSTextField *bottomStatusLabel = [delegate valueForKey:@"bottomStatusLabel"];
        NSTextField *inspectorConnectionLabel = [delegate valueForKey:@"inspectorConnectionLabel"];
        NSTextField *contextLabel = [delegate valueForKey:@"inspectorContextLabel"];
        NSTextField *contextPercent = [delegate valueForKey:@"inspectorContextPercentLabel"];
        NSView *contextMeter = [delegate valueForKey:@"inspectorContextMeter"];
        NSStackView *contextDetailStack = [delegate valueForKey:@"inspectorContextDetailStack"];
        NSButton *contextDisclosure = [delegate valueForKey:@"contextDisclosureButton"];
        PTAssert(window != nil && changedFiles != nil && splitView != nil && inspector != nil &&
            workspaceSplitView != nil && conversationPane != nil && toolWorkspace != nil &&
            gitDirectoryPicker != nil && removeGitDirectoryButton != nil &&
            gitDirectoryInput != nil && gitDirectoryHint != nil && gitDiffScroll != nil &&
            gitDiffTextView != nil && gitDiffProgress != nil && compactButton != nil &&
            sendButton != nil && imageButton != nil && composerTargetLabel != nil &&
            bottomStatusLabel != nil && inspectorConnectionLabel != nil &&
            contextLabel != nil && contextPercent != nil && contextMeter != nil &&
            contextDetailStack != nil && contextDisclosure != nil,
            @"window, split workspaces, inspector, Git controls, and changed-files stack must exist");
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat fullConversationWidth = NSWidth(conversationPane.frame);
        PTPumpRunLoop(0.02);
        [window.contentView layoutSubtreeIfNeeded];
        for (NSView *view in PTAllDescendants(window.contentView)) {
            if (![view isKindOfClass:NSButton.class]) continue;
            PTAssert([view isKindOfClass:NSClassFromString(@"PTAnimatedButton")] ||
                     [view isKindOfClass:NSClassFromString(@"PTWarmPopUpButton")],
                [NSString stringWithFormat:@"main-window control %@ must use custom warm chrome",
                    NSStringFromClass(view.class)]);
        }
        PTAssert([gitDirectoryPicker isKindOfClass:NSClassFromString(@"PTWarmPopUpButton")] &&
                 [[delegate valueForKey:@"languagePicker"] isKindOfClass:NSClassFromString(@"PTWarmPopUpButton")],
            @"language and Git directory pickers must use the custom warm popup control");
        [window.contentView layoutSubtreeIfNeeded];
        NSArray<NSDictionary *> *standardControls = @[
            @{@"name": @"language", @"view": [delegate valueForKey:@"languagePicker"]},
            @{@"name": @"refresh", @"view": [delegate valueForKey:@"refreshButton"]},
            @{@"name": @"inspector", @"view": [delegate valueForKey:@"inspectorToggleButton"]},
            @{@"name": @"remote", @"view": [delegate valueForKey:@"remoteButton"]},
            @{@"name": @"compact", @"view": [delegate valueForKey:@"compactButton"]},
            @{@"name": @"connect", @"view": [delegate valueForKey:@"connectButton"]},
            @{@"name": @"floating", @"view": [delegate valueForKey:@"floatingButton"]},
            @{@"name": @"context", @"view": [delegate valueForKey:@"contextDisclosureButton"]},
            @{@"name": @"cost", @"view": [delegate valueForKey:@"costDisclosureButton"]},
            @{@"name": @"git picker", @"view": gitDirectoryPicker},
            @{@"name": @"git remove", @"view": removeGitDirectoryButton}
        ];
        for (NSDictionary *entry in standardControls) {
            NSView *control = entry[@"view"];
            PTAssert(ABS(NSHeight(control.frame) - 28.0) < 0.6,
                [NSString stringWithFormat:@"%@ (%@) must use the shared 28-point control height, got %.1f",
                    entry[@"name"], NSStringFromClass(control.class), NSHeight(control.frame)]);
        }
        id unconnectedSession = [[NSClassFromString(@"PTSessionInfo") alloc] init];
        [unconnectedSession setValue:@"unconnected-session" forKey:@"sessionID"];
        [unconnectedSession setValue:@"Unconnected conversation" forKey:@"title"];
        [unconnectedSession setValue:@"/tmp" forKey:@"cwd"];
        [unconnectedSession setValue:@[] forKey:@"assistantMessages"];
        [delegate setValue:unconnectedSession forKey:@"selectedSession"];
        [delegate setValue:@[unconnectedSession] forKey:@"sessions"];
        PTCallNoArgument(delegate, NSSelectorFromString(@"refreshAgentStateAndControls"));
        PTAssert([compactButton.title isEqual:@"Compact"] &&
                 compactButton.action == NSSelectorFromString(@"compactConversation:") &&
                 compactButton.enabled,
            @"Compact must remain available without a Terminal connection");

        NSTextView *pasteComposer = [delegate valueForKey:@"composerTextView"];
        PTAssert(pasteComposer != nil, @"main composer must exist for paste focus regression coverage");
        PTAssert(pasteComposer.editable && sendButton.enabled && imageButton.enabled,
            @"composer, send, and attachment controls must remain available without a Terminal connection");
        NSString *connectionCopy = [NSString stringWithFormat:@"%@ %@ %@",
            composerTargetLabel.stringValue, bottomStatusLabel.stringValue,
            inspectorConnectionLabel.stringValue];
        PTAssert([connectionCopy rangeOfString:@"只读"].location == NSNotFound &&
                 [connectionCopy rangeOfString:@"未同步"].location == NSNotFound &&
                 [connectionCopy rangeOfString:@"请先同步"].location == NSNotFound,
            @"conversation controls must not present synchronization-gated copy");
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
        CGFloat mainWorkspaceWidthWithInspector = NSWidth(splitView.subviews.lastObject.frame);
        PTAssert(splitView.subviews.count == 2 && inspector.window == window &&
                 inspector.superview != splitView &&
                 inspector.translatesAutoresizingMaskIntoConstraints,
            @"the inspector must be an absolute root overlay excluded from Auto Layout");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleInspector:"), nil);
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat mainWorkspaceWidthWithoutInspector = NSWidth(splitView.subviews.lastObject.frame);
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleInspector:"), nil);
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        PTAssert(fabs(mainWorkspaceWidthWithInspector - mainWorkspaceWidthWithoutInspector) < 1.0,
            @"opening or closing the floating inspector must not resize the main workspace");

        id session = [[NSClassFromString(@"PTSessionInfo") alloc] init];
        NSString *changedFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"PrettyTerm-changed-file-%@.txt", NSUUID.UUID.UUIDString]];
        PTAssert([@"visible\n" writeToFile:changedFilePath atomically:YES
                                   encoding:NSUTF8StringEncoding error:nil],
            @"changed-file fixture must exist while the inspector renders it");
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
            @"filePath": changedFilePath,
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
        NSMenu *sessionContextMenu = [[NSMenu alloc] init];
        PTCallTwoObjects(delegate,
            NSSelectorFromString(@"populateSessionContextMenu:forSession:"),
            sessionContextMenu,
            session);
        NSMutableSet *menuActions = [NSMutableSet set];
        NSMenuItem *openProjectItem = nil;
        for (NSMenuItem *item in sessionContextMenu.itemArray) {
            if (item.action) [menuActions addObject:NSStringFromSelector(item.action)];
            if (item.action == NSSelectorFromString(@"openSessionProjectFolder:")) openProjectItem = item;
        }
        PTAssert([menuActions containsObject:@"revealSessionTranscript:"] &&
                 [menuActions containsObject:@"copySessionTranscriptPath:"] &&
                 [menuActions containsObject:@"renameSessionFromMenu:"],
            @"adding rename must retain transcript reveal and path copy actions");
        PTAssert([openProjectItem.title isEqual:@"打开项目文件夹"] &&
            openProjectItem.action == NSSelectorFromString(@"openSessionProjectFolder:") &&
            [openProjectItem.representedObject isEqual:@"/tmp"] &&
            openProjectItem.enabled,
            @"session context menu must open the session cwd without changing the selected conversation");
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

        id thirdSession = [[NSClassFromString(@"PTSessionInfo") alloc] init];
        [thirdSession setValue:@"session-other-project" forKey:@"sessionID"];
        [thirdSession setValue:@"Other project" forKey:@"title"];
        [thirdSession setValue:@"/private" forKey:@"cwd"];
        [thirdSession setValue:@[] forKey:@"assistantMessages"];
        [delegate setValue:@[session, secondSession, thirdSession] forKey:@"sessions"];
        PTCallNoArgument(delegate, NSSelectorFromString(@"rebuildSessionSidebarRows"));
        NSArray<NSDictionary *> *sidebarRows = [delegate valueForKey:@"sessionSidebarRows"];
        PTAssert(sidebarRows.count == 5 &&
            [sidebarRows[0][@"kind"] isEqual:@"project"] &&
            [sidebarRows[1][@"session"] isEqual:session] &&
            [sidebarRows[2][@"session"] isEqual:secondSession] &&
            [sidebarRows[3][@"kind"] isEqual:@"project"] &&
            [sidebarRows[4][@"session"] isEqual:thirdSession],
            @"sidebar rows must group conversations by project while preserving recency order");
        NSTableView *sessionTable = [delegate valueForKey:@"sessionTable"];
        NSView *projectCell = [(id<NSTableViewDelegate>)delegate
            tableView:sessionTable
            viewForTableColumn:sessionTable.tableColumns.firstObject
            row:0];
        NSButton *projectButton = [projectCell valueForKey:@"clickTarget"];
        PTAssert([projectButton isKindOfClass:NSClassFromString(@"PTAnimatedButton")] &&
            !projectButton.bordered && projectButton.title.length == 0 &&
            [projectButton.identifier isEqual:@"/tmp"],
            @"project groups must use a custom warm full-row disclosure control without a visible native button title");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleSessionProject:"), projectButton);
        sidebarRows = [delegate valueForKey:@"sessionSidebarRows"];
        NSArray<NSString *> *collapsedProjects = [NSUserDefaults.standardUserDefaults
            stringArrayForKey:@"PTCollapsedSessionProjectPaths"];
        PTAssert(sidebarRows.count == 3 && [collapsedProjects containsObject:@"/tmp"],
            @"collapsing one project must hide only its conversations and persist that state");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleSessionProject:"), projectButton);
        sidebarRows = [delegate valueForKey:@"sessionSidebarRows"];
        PTAssert(sidebarRows.count == 5,
            @"expanding a project must restore its conversations in the grouped sidebar");
        [delegate setValue:@[session, secondSession] forKey:@"sessions"];
        PTCallNoArgument(delegate, NSSelectorFromString(@"rebuildSessionSidebarRows"));

        NSArray *waitingBaseline = [[session valueForKey:@"assistantMessages"] copy];
        PTCallOneObject(delegate,
            NSSelectorFromString(@"beginAwaitingClaudeReplyForSessionID:"),
            @"session-local-review");
        NSDictionary *awaitingBySession = [delegate valueForKey:@"awaitingClaudeBaselineBySessionID"];
        PTAssert(awaitingBySession[@"session-local-review"] != nil,
            @"a successfully submitted message must begin the visible Claude waiting state");
        PTAssert([sendButton.title isEqual:@"■"] &&
                 sendButton.action == NSSelectorFromString(@"stopSelectedClaudeOutput:") &&
                 [sendButton.toolTip containsString:@"Esc"],
            @"the send button must become an Escape-backed Stop button while Claude is responding");
        NSMutableArray *messagesWithActivity = [waitingBaseline mutableCopy];
        [messagesWithActivity addObject:@{
            @"role": @"assistant",
            @"text": @"started",
            @"messageKey": @"waiting-activity"
        }];
        [session setValue:messagesWithActivity forKey:@"assistantMessages"];
        PTCallOneObject(delegate,
            NSSelectorFromString(@"reconcileAwaitingClaudeReplyWithSession:"), session);
        PTAssert(awaitingBySession[@"session-local-review"] == nil,
            @"the first real assistant transcript event must dismiss the waiting state");
        PTAssert([sendButton.title isEqual:@"↑"] &&
                 sendButton.action == NSSelectorFromString(@"sendMessage:"),
            @"the Stop button must return to Send when Claude output is complete");
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
        PTAssert([commitButton isKindOfClass:NSClassFromString(@"PTAnimatedButton")] &&
                 [commitAndPushButton isKindOfClass:NSClassFromString(@"PTAnimatedButton")] &&
                 [pushButton isKindOfClass:NSClassFromString(@"PTAnimatedButton")] &&
                 [[delegate valueForKey:@"gitIncludeUnstagedButton"]
                     isKindOfClass:NSClassFromString(@"PTWarmToggleButton")],
            @"Git action popover must contain only custom warm buttons");
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
        PTAssert(!toolWorkspace.hidden,
            @"the review workspace must exist before its opening animation begins");
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat reviewConversationWidth = NSWidth(conversationPane.frame);
        PTAssert(!gitDiffScroll.hidden && NSWidth(toolWorkspace.frame) >= 320.0 &&
                 reviewConversationWidth < fullConversationWidth - 200.0,
            [NSString stringWithFormat:
                @"the per-turn review must open a large page that pushes the conversation left (full=%.1f review=%.1f tool=%.1f hidden=%d inspector=%.1f workspace=%.1f preference=%.1f window=%@ mainSplit=%@ mainRight=%@)",
                fullConversationWidth, reviewConversationWidth, NSWidth(toolWorkspace.frame),
                gitDiffScroll.hidden, NSWidth(inspector.frame),
                NSWidth(workspaceSplitView.frame),
                [[delegate valueForKey:@"toolWorkspaceWidthConstraint"] constant],
                NSStringFromRect(window.frame), NSStringFromRect(splitView.frame),
                NSStringFromRect(splitView.subviews.lastObject.frame)]);
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
        PTAssert(!toolWorkspace.hidden,
            @"closing review must keep the page mounted while its animation is running");
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        PTAssert(toolWorkspace.hidden && NSWidth(conversationPane.frame) > reviewConversationWidth + 200.0,
            @"the local review must collapse smoothly and restore conversation width");

        PTCallOneObject(delegate, NSSelectorFromString(@"toggleGitDiff:"), nil);
        [window.contentView layoutSubtreeIfNeeded];
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        PTAssert(!gitDiffScroll.hidden && NSWidth(toolWorkspace.frame) >= 320.0,
            @"clicking Git review must reuse the large review workspace");
        PTAssert(gitDiffScroll.alphaValue > 0.95,
            @"the Git review must finish its expansion fade at full opacity");
        PTAssert(NSWidth(gitDiffTextView.frame) > 0.0,
            @"the expanded Git diff text document must have a visible width");
        PTAssert(gitDiffTextView.richText && gitDiffScroll.borderType == NSNoBorder,
            @"Git review must use a styled native document instead of a terminal text box");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleGitDiff:"), nil);
        [window.contentView layoutSubtreeIfNeeded];
        PTPumpRunLoop(0.28);
        PTAssert(toolWorkspace.hidden,
            @"clicking the expanded Git review control again must close the review page");

        CGFloat expandedInspectorWidth = NSWidth(inspector.frame);
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleInspector:"), nil);
        [window.contentView layoutSubtreeIfNeeded];
        PTAssert(!inspector.hidden && NSWidth(inspector.frame) > 0.0,
            @"the inspector must remain mounted while its closing animation runs");
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        PTAssert(inspector.hidden,
            @"the inspector must hide only after its closing animation completes");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleInspector:"), nil);
        PTAssert(!inspector.hidden,
            @"opening the inspector must mount it before animating its width");
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        PTAssert(NSWidth(inspector.frame) >= expandedInspectorWidth - 1.0,
            @"the animated inspector must restore its prior width instead of snapping smaller");

        NSRect originalReadingFrame = window.frame;
        [window setFrame:NSMakeRect(20, 20, 1040, 680) display:NO];
        [window.contentView layoutSubtreeIfNeeded];
        NSView *summaryCard = [delegate valueForKey:@"inspectorCard"];
        NSView *readingComposer = [delegate valueForKey:@"composerSurface"];
        NSButton *summaryToggle = [delegate valueForKey:@"inspectorToggleButton"];
        NSButton *pagesToggle = [delegate valueForKey:@"sidePanelToggleButton"];
        NSRect expandedReadingFrame = [readingComposer convertRect:readingComposer.bounds toView:window.contentView];
        PTAssert(summaryCard.superview == inspector && summaryCard.layer.cornerRadius == 20 &&
                 NSWidth(summaryCard.frame) < NSWidth(inspector.frame) - 20 &&
                 NSHeight(summaryCard.frame) <= 640.5,
            @"inspector must be one inset rounded summary card, not a full-height sidebar surface");
        PTAssert(summaryToggle.superview == pagesToggle.superview &&
                 summaryToggle.action != pagesToggle.action && summaryToggle.image != nil && pagesToggle.image != nil &&
                 summaryToggle.imagePosition == NSImageOnly && pagesToggle.imagePosition == NSImageOnly &&
                 summaryToggle.alignment == NSTextAlignmentCenter && pagesToggle.alignment == NSTextAlignmentCenter,
            @"summary and side pages must use independent toolbar buttons with exactly centered icons");
        NSRect userWindowFrame = window.frame;
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleInspector:"), nil);
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        NSRect centeredReadingFrame = [readingComposer convertRect:readingComposer.bounds toView:window.contentView];
        NSSize fittingWithoutInspector = window.contentView.fittingSize;
        PTAssert(NSEqualRects(window.frame, userWindowFrame),
            @"collapsing the inspector must preserve the user's exact window frame");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleInspector:"), nil);
        PTPumpRunLoop(0.28);
        PTAssert(NSEqualRects(window.frame, userWindowFrame) &&
                 inspector.window == window &&
                 inspector.translatesAutoresizingMaskIntoConstraints,
            @"opening the floating inspector must preserve the user's exact window frame");
        NSSize compactUserSize = NSMakeSize(420.0, 360.0);
        PTAssert(window.minSize.width <= compactUserSize.width &&
                 window.minSize.height <= compactUserSize.height,
            @"the inspector must not install a window minimum size that blocks the user's resize gesture");
        NSRect resizedWindowFrame = userWindowFrame;
        resizedWindowFrame.size = compactUserSize;
        [window setFrame:resizedWindowFrame display:NO];
        PTPumpRunLoop(0.05);
        [window.contentView layoutSubtreeIfNeeded];
        NSSize topBarFitting = window.contentView.subviews.count > 0
            ? window.contentView.subviews[0].fittingSize : NSZeroSize;
        NSSize splitFitting = window.contentView.subviews.count > 1
            ? window.contentView.subviews[1].fittingSize : NSZeroSize;
        NSSize inspectorFitting = inspector.fittingSize;
        NSSize sidebarFitting = splitView.subviews.count > 0
            ? splitView.subviews[0].fittingSize : NSZeroSize;
        NSSize conversationFitting = splitView.subviews.count > 1
            ? splitView.subviews[1].fittingSize : NSZeroSize;
        NSMutableString *conversationChildren = [NSMutableString string];
        for (NSView *child in conversationPane.subviews) {
            [conversationChildren appendFormat:@" %@=%@",
                NSStringFromClass(child.class), NSStringFromSize(child.fittingSize)];
        }
        PTAssert(NSEqualRects(window.frame, resizedWindowFrame) &&
                 inspector.window == window &&
                 fabs(NSWidth(splitView.frame) - compactUserSize.width) < 1.0 &&
                 fabs(NSWidth(window.contentView.subviews[0].frame) - compactUserSize.width) < 1.0,
            [NSString stringWithFormat:
                @"the application window must remain freely resizable while the inspector is open (requested=%@ actual=%@ min=%@ contentMin=%@ fitting=%@ closedFitting=%@ top=%@ split=%@ inspector=%@ sidebar=%@ conversation=%@ children=%@)",
                NSStringFromRect(resizedWindowFrame), NSStringFromRect(window.frame),
                NSStringFromSize(window.minSize), NSStringFromSize(window.contentMinSize),
                NSStringFromSize(window.contentView.fittingSize),
                NSStringFromSize(fittingWithoutInspector), NSStringFromSize(topBarFitting),
                NSStringFromSize(splitFitting), NSStringFromSize(inspectorFitting),
                NSStringFromSize(sidebarFitting), NSStringFromSize(conversationFitting),
                conversationChildren]);
        [window setFrame:userWindowFrame display:NO];
        (void)expandedReadingFrame;
        (void)centeredReadingFrame;
        [window setFrame:originalReadingFrame display:NO];
        [window.contentView layoutSubtreeIfNeeded];

        PTAssert([delegate respondsToSelector:NSSelectorFromString(@"openFileWorkspace:")] &&
                 [delegate respondsToSelector:NSSelectorFromString(@"openPreviewFileURL:")] &&
                 [delegate respondsToSelector:NSSelectorFromString(@"toggleFileTree:")],
            @"the main window must expose the file workspace, file opening, and file-tree controls");
        NSURL *previewRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:
                @"PrettyTerm workspace preview %@", NSUUID.UUID.UUIDString]] isDirectory:YES];
        PTAssert([NSFileManager.defaultManager createDirectoryAtURL:previewRoot
            withIntermediateDirectories:YES attributes:nil error:nil],
            @"file-workspace fixture directory must be created");
        NSURL *markdownURL = [previewRoot URLByAppendingPathComponent:@"Guide.md"];
        NSURL *sourceURL = [previewRoot URLByAppendingPathComponent:@"Review.m"];
        PTAssert([@"# Rendered heading\n\n- item\n" writeToURL:markdownURL atomically:YES
            encoding:NSUTF8StringEncoding error:nil] &&
            [@"NSInteger value = 42;\n" writeToURL:sourceURL atomically:YES
            encoding:NSUTF8StringEncoding error:nil],
            @"Markdown and source fixtures must be written");
        [session setValue:previewRoot.path forKey:@"cwd"];
        [delegate setValue:session forKey:@"selectedSession"];
        NSRect windowFrameBeforeFiles = window.frame;
        CGFloat workspaceWidthBeforeFiles = NSWidth(workspaceSplitView.frame);
        CGFloat inspectorWidthBeforeFiles = NSWidth(inspector.frame);
        PTCallOneObject(delegate, NSSelectorFromString(@"openFileWorkspace:"), nil);
        PTAssert(!inspector.hidden,
            @"opening Files must keep the inspector mounted during the shared closing animation");
        PTPumpRunLoop(0.50);
        [window.contentView layoutSubtreeIfNeeded];
        NSView *fileTreeView = [delegate valueForKey:@"fileTreeView"];
        NSOutlineView *fileOutlineView = [delegate valueForKey:@"fileOutlineView"];
        NSView *toolPageContainer = [delegate valueForKey:@"toolPageContainerView"];
        NSURL *fileTreeRootURL = [delegate valueForKey:@"fileTreeRootURL"];
        PTAssert(!toolWorkspace.hidden && !fileTreeView.hidden && fileOutlineView != nil &&
                 toolPageContainer != nil && [fileTreeRootURL.path isEqual:previewRoot.path],
            @"opening Files must create a large page with a visible tree rooted at the session cwd");
        PTAssert(inspector.hidden && NSEqualRects(window.frame, windowFrameBeforeFiles) &&
                 fabs(NSWidth(workspaceSplitView.frame) - workspaceWidthBeforeFiles) < 1.0,
            [NSString stringWithFormat:
                @"opening Files must hide the floating inspector without changing the application layout (before=%.1f inspector=%.1f after=%.1f hidden=%d frame=%d conversation=%.1f tool=%.1f tree=%.1f fitting=%@ contentMin=%@ min=%@ oldWindow=%@ newWindow=%@)",
                workspaceWidthBeforeFiles, inspectorWidthBeforeFiles,
                NSWidth(workspaceSplitView.frame), inspector.hidden,
                NSEqualRects(window.frame, windowFrameBeforeFiles), NSWidth(conversationPane.frame),
                NSWidth(toolWorkspace.frame), NSWidth(fileTreeView.frame),
                NSStringFromSize(window.contentView.fittingSize),
                NSStringFromSize(window.contentMinSize), NSStringFromSize(window.minSize),
                NSStringFromRect(windowFrameBeforeFiles), NSStringFromRect(window.frame)]);
        CGFloat previewWidthWithTree = NSWidth(toolPageContainer.frame);
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleFileTree:"), nil);
        PTAssert(!fileTreeView.hidden,
            @"the file tree must remain mounted during its closing animation");
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat previewWidthWithoutTree = NSWidth(toolPageContainer.frame);
        PTAssert(fileTreeView.hidden && previewWidthWithoutTree > previewWidthWithTree + 160.0,
            @"closing the file tree must smoothly return its width to the file page");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleFileTree:"), nil);
        PTPumpRunLoop(0.28);

        PTCallOneObject(delegate, NSSelectorFromString(@"openPreviewFileURL:"), markdownURL);
        NSDictionary *markdownPayload = [delegate valueForKey:@"activeFilePreviewPayload"];
        PTAssert([markdownPayload[@"kind"] isEqual:@"markdown"] &&
                 [markdownPayload[@"path"] isEqual:markdownURL.path] &&
                 [[delegate valueForKey:@"activeToolPageKind"] isEqual:@"file"],
            @"selecting Markdown must open the rendered file page with its exact path");
        PTCallOneObject(delegate, NSSelectorFromString(@"openPreviewFileURL:"), sourceURL);
        NSDictionary *sourcePayload = [delegate valueForKey:@"activeFilePreviewPayload"];
        PTAssert([sourcePayload[@"kind"] isEqual:@"source"] &&
                 [sourcePayload[@"path"] isEqual:sourceURL.path],
            @"selecting source must reuse the large file page with source rendering");
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleInspector:"), nil);
        PTPumpRunLoop(0.28);
        [window.contentView layoutSubtreeIfNeeded];
        PTAssert(!inspector.hidden,
            @"the inspector must remain explicitly reopenable after Files auto-hides it");

        NSButton *button = PTFirstButtonInStack(changedFiles);
        PTAssert(button != nil, @"changed-file action must render as a button");
        PTAssert([button acceptsFirstMouse:nil], @"changed-file button must accept first mouse");
        PTAssert(button.target == delegate && button.action == NSSelectorFromString(@"revealChangedFile:"),
            @"changed-file button must retain its explicit target and action");
        PTAssert(button.alignment == NSTextAlignmentCenter,
            @"changed-file text must be centered inside the full-width warm button");

        // JSONL 会在 Claude 回复期间持续修订，但改动文件列表往往没有变化。
        // 轮询刷新不能销毁一个可能正处于 mouseDown/mouseUp 之间的按钮。
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(PTFirstButtonInStack(changedFiles) == button,
            @"unchanged inspector data must preserve changed-file button identity");
        [session setValue:@[@{
            @"displayName": @"interaction-test.txt",
            @"filePath": changedFilePath,
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

        [NSFileManager.defaultManager removeItemAtPath:changedFilePath error:nil];
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(PTFirstButtonInStack(changedFiles) == nil,
            @"a moved or deleted file must disappear from current changes on the next refresh");

        NSTextView *composer = [delegate valueForKey:@"composerTextView"];
        NSPopUpButton *languagePicker = [delegate valueForKey:@"languagePicker"];
        NSArray *preservedReviewEvents = @[@{
            @"filePath": sourceURL.path,
            @"oldText": @"NSInteger value = 1;\n",
            @"newText": @"NSInteger value = 42;\n",
            @"kind": @"Edit"
        }];
        PTCallOneObject(delegate, NSSelectorFromString(@"showTranscriptEditReviewWithEvents:"),
            preservedReviewEvents);
        PTCallOneObject(delegate, NSSelectorFromString(@"openPreviewFileURL:"), sourceURL);
        PTPumpRunLoop(0.50);
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat preservedToolWidth = NSWidth([[delegate valueForKey:@"toolWorkspaceView"] frame]);
        CGFloat preservedTreeWidth = NSWidth([[delegate valueForKey:@"fileTreeView"] frame]);
        PTAssert([[delegate valueForKey:@"reviewToolPageOpen"] boolValue] &&
                 [[delegate valueForKey:@"fileToolPageOpen"] boolValue] &&
                 [[delegate valueForKey:@"activeToolPageKind"] isEqual:@"file"],
            @"review and file pages must coexist before rebuilding the interface language");
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
        NSDictionary *englishPreview = [delegate valueForKey:@"activeFilePreviewPayload"];
        NSURL *englishRoot = [delegate valueForKey:@"fileTreeRootURL"];
        NSView *englishTool = [delegate valueForKey:@"toolWorkspaceView"];
        NSView *englishTree = [delegate valueForKey:@"fileTreeView"];
        PTAssert([[delegate valueForKey:@"reviewToolPageOpen"] boolValue] &&
                 [[delegate valueForKey:@"fileToolPageOpen"] boolValue] &&
                 [[delegate valueForKey:@"activeToolPageKind"] isEqual:@"file"] &&
                 [englishPreview[@"path"] isEqual:sourceURL.path] &&
                 [englishRoot.path isEqual:previewRoot.path],
            @"language rebuilding must preserve both tool tabs, selected file, and file root");
        PTAssert(!englishTool.hidden && !englishTree.hidden &&
                 fabs(NSWidth(englishTool.frame) - preservedToolWidth) < 3.0 &&
                 fabs(NSWidth(englishTree.frame) - preservedTreeWidth) < 3.0,
            [NSString stringWithFormat:@"language rebuilding must preserve open panel states and split widths (tool %.1f -> %.1f, tree %.1f -> %.1f, hidden %d/%d)", preservedToolWidth, NSWidth(englishTool.frame), preservedTreeWidth, NSWidth(englishTree.frame), englishTool.hidden, englishTree.hidden]);
        NSButton *englishCompact = [delegate valueForKey:@"compactButton"];
        PTAssert([englishCompact.title isEqual:@"Compact"] &&
                 [englishCompact.toolTip containsString:@"/compact"],
            @"Compact must survive the localized presentation rebuild");
        NSPopUpButton *englishPicker = [delegate valueForKey:@"languagePicker"];
        [englishPicker selectItemAtIndex:0];
        PTCallOneObject(delegate, NSSelectorFromString(@"changeInterfaceLanguage:"), englishPicker);
        PTAssert([[[delegate valueForKey:@"sendButton"] title] isEqual:@"↑"],
            @"Chinese mode must remain selectable after switching to English");
        [NSFileManager.defaultManager removeItemAtURL:previewRoot error:nil];
        NSLog(@"PTWindowInteractionTests passed");
    }
    return 0;
}
