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
- (void)consumeFrame:(NSDictionary *)frame;
@end

@interface PTClaudeBridgeExactSessionProbe : PTClaudeBridge
@end

@implementation PTClaudeBridgeExactSessionProbe
- (NSString *)releaseInteractiveSession:(NSString *)sessionID {
    (void)sessionID;
    return nil;
}
- (void)startProcessInDirectory:(NSString *)cwd resume:(BOOL)resume {
    (void)cwd;
    (void)resume;
    NSString *initID = @"probe-init-1";
    [self setValue:initID forKey:@"initializeID"];
    [self consumeFrame:@{
        @"type": @"control_response",
        @"response": @{
            @"subtype": @"success",
            @"request_id": initID,
            @"response": @{ @"commands": @[] }
        }
    }];
}
- (void)writeFrame:(NSDictionary *)frame completion:(void (^)(BOOL))completion {
    (void)frame;
    if (completion) completion(YES);
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

static BOOL PTViewIsOrDescendsFromView(NSView *view, NSView *ancestor) {
    for (NSView *candidate = view; candidate; candidate = candidate.superview) {
        if (candidate == ancestor) return YES;
    }
    return NO;
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
            ([bridgeStatus containsString:@"Claude 后台会话已连接"] ||
             [bridgeStatus containsString:@"Claude background session connected"]),
            @"an exact Claude sessionId must bind cleanly through the headless bridge");

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
        NSWindow *window = [delegate valueForKey:@"window"];
        PTAssert(window != nil && window.minSize.width == 680, @"the native shell must preserve the minimum width");
        PTCallNoArgument(delegate, NSSelectorFromString(@"buildQuestionPanelIfNeeded"));

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
        [[delegate valueForKey:@"pendingImages"] removeAllObjects];
        [[delegate valueForKey:@"pendingFiles"] removeAllObjects];
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
        [[delegate valueForKey:@"pendingImages"] removeAllObjects];
        [[delegate valueForKey:@"pendingFiles"] removeAllObjects];
        PTCallNoArgument(delegate, NSSelectorFromString(@"clearFloatingPendingImagesAfterSuccessfulSend"));
        [NSFileManager.defaultManager removeItemAtPath:folderPath error:nil];

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
        NSLog(@"PTWindowInteractionTests passed");
    }
    return 0;
}
