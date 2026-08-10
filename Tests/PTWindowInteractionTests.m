#import <Cocoa/Cocoa.h>
#import <objc/message.h>

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

static void PTPumpRunLoop(NSTimeInterval duration) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:duration];
    while ([deadline timeIntervalSinceNow] > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

static id PTCreateWithObject(Class classObject, SEL selector, id argument) {
    id allocated = ((id (*)(id, SEL))objc_msgSend)(classObject, @selector(alloc));
    return ((id (*)(id, SEL, id))objc_msgSend)(allocated, selector, argument);
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
        [NSString stringWithFormat:@"%@ hit %@ instead of the changed-file button",
            stage, NSStringFromClass(hit.class)]);
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        id delegate = [[NSClassFromString(@"PTAppDelegate") alloc] init];
        PTAssert(delegate != nil, @"PTAppDelegate must be loadable");
        PTCallNoArgument(delegate, NSSelectorFromString(@"buildWindow"));

        NSWindow *window = [delegate valueForKey:@"window"];
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
        PTAssert(window != nil && changedFiles != nil && splitView != nil && inspector != nil &&
            gitDirectoryPicker != nil && removeGitDirectoryButton != nil &&
            gitDirectoryInput != nil && gitDirectoryHint != nil && gitDiffScroll != nil &&
            gitDiffTextView != nil && gitDiffProgress != nil,
            @"window, inspector, Git controls, and changed-files stack must exist");

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
        [session setValue:@0 forKey:@"contextUsed"];
        [session setValue:@200000 forKey:@"contextWindow"];
        [session setValue:@[@"/tmp"] forKey:@"accessedDirectories"];
        [session setValue:@"/tmp" forKey:@"cwd"];
        [session setValue:@[@{
            @"displayName": @"interaction-test.txt",
            @"filePath": @"/tmp/interaction-test.txt",
            @"added": @1,
            @"removed": @0
        }] forKey:@"changedFiles"];
        [session setValue:@[] forKey:@"tasks"];
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);

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
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert(!gitDirectoryPicker.enabled,
            @"polling the currently open transcript must not immediately restore a deleted directory");

        gitDirectoryInput.stringValue = @"/tmp";
        PTCallOneObject(delegate, NSSelectorFromString(@"addManualGitDirectory:"), nil);
        PTAssert([gitDirectoryPicker.selectedItem.representedObject isEqual:@"/tmp"],
            @"manual entry must restore a deleted Git directory immediately");

        PTCallOneObject(delegate, NSSelectorFromString(@"removeSelectedGitDirectory:"), nil);
        PTCallNoArgument(delegate, NSSelectorFromString(@"allowRediscoveryOfGitDirectoriesForNewSession"));
        PTCallOneObject(delegate, NSSelectorFromString(@"updateInspectorForSession:"), session);
        PTAssert([gitDirectoryPicker.selectedItem.representedObject isEqual:@"/tmp"],
            @"reopening a related conversation must rediscover its deleted Git directory");

        CGFloat compactInspectorWidth = NSWidth(inspector.frame);
        PTCallOneObject(delegate, NSSelectorFromString(@"toggleGitDiff:"), nil);
        [window.contentView layoutSubtreeIfNeeded];
        CGFloat expandedInspectorWidth = NSWidth(inspector.frame);
        PTAssert(!gitDiffScroll.hidden && expandedInspectorWidth > compactInspectorWidth + 100.0,
            @"clicking Git diff must reveal it and widen the inspector");
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

        Class leaseClass = NSClassFromString(@"PTPasteboardLease");
        id lease = PTCreateWithObject(leaseClass, NSSelectorFromString(@"initWithText:"), @"多行\n消息");
        NSPasteboard *testPasteboard = [NSPasteboard pasteboardWithUniqueName];
        NSPasteboardItem *testItem = [[NSPasteboardItem alloc] init];
        [testItem setDataProvider:lease forTypes:@[NSPasteboardTypeString]];
        PTAssert([testPasteboard writeObjects:@[testItem]], @"pasteboard lease must be writable");
        PTAssert(![[lease valueForKey:@"served"] boolValue],
            @"pasteboard lease must remain pending before a consumer requests text");
        PTAssert([[testPasteboard stringForType:NSPasteboardTypeString] isEqual:@"多行\n消息"],
            @"pasteboard lease must provide the complete multiline text");
        PTAssert([[lease valueForKey:@"served"] boolValue],
            @"pasteboard lease must acknowledge that a consumer requested the text");

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
        NSLog(@"PTWindowInteractionTests passed");
    }
    return 0;
}
