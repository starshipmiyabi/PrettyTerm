#import <AppKit/AppKit.h>
#define main PTPrettyTermApplicationMain
#import "../Sources/PrettyTerm.m"
#undef main

@interface PTAppDelegate (HomeTests)
- (void)showHome:(id)sender;
- (void)hideHome:(id)sender;
- (void)startHomeConversation:(id)sender;
- (void)finishHomeSessionIfAvailable;
- (void)startBlankHomeConversation:(id)sender;
- (void)renameSession:(PTSessionInfo *)session toTitle:(NSString *)title;
@end
@interface PTHomeBridgeProbe : PTClaudeBridge
@property(nonatomic, strong) PTSessionInfo *requestedSession;
@property(nonatomic, copy) NSString *requestedPrompt;
@property(nonatomic) BOOL ready;
@end
@implementation PTHomeBridgeProbe
- (void)connectToSession:(PTSessionInfo *)session { self.requestedSession = session; }
- (void)startNewSession:(PTSessionInfo *)session prompt:(NSString *)prompt {
    self.requestedSession = session;
    self.requestedPrompt = prompt;
}
- (BOOL)running { return self.ready; }
- (void)startNewSessionInDirectory:(NSString *)directory {
    self.requestedSession = [PTSessionInfo new];
    self.requestedSession.sessionID = @"blank-session-created-by-claude";
    self.requestedSession.cwd = directory;
}
- (NSString *)sessionID { return self.requestedSession.sessionID; }
@end
@interface PTHomeDelegateProbe : PTAppDelegate
@property(nonatomic, strong) PTHomeBridgeProbe *launch;
@end
@implementation PTHomeDelegateProbe
- (PTClaudeBridge *)newHomeBridge { self.launch = [PTHomeBridgeProbe new]; return self.launch; }
- (PTClaudeBridge *)newRenameBridge { return [PTHomeBridgeProbe new]; }
@end
static void CheckHome(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        PTHomeDelegateProbe *app = [PTHomeDelegateProbe new];
        CheckHome([app respondsToSelector:@selector(showHome:)], @"homepage must have an independent entry");
        [app setValue:[PTAgentState new] forKey:@"agentState"];
        for (NSString *key in @[@"pendingImages", @"pendingFiles", @"floatingPendingImages", @"floatingPendingFiles", @"workspaceTabs"])
            [app setValue:[NSMutableArray array] forKey:key];
        [app setValue:[NSMutableSet set] forKey:@"temporaryImagePaths"];
        [app buildWindow];
        PTWorkspaceTab *original = [app createWorkspaceTab];
        [app setValue:original forKey:@"activeWorkspaceTab"];
        [app setValue:original.bridge forKey:@"bridge"];
        PTSessionInfo *session = [PTSessionInfo new];
        session.sessionID = @"original";
        session.cwd = @"/expected/project";
        [app setValue:session forKey:@"selectedSession"];
        [app setValue:@[session] forKey:@"sessions"];
        NSTextView *oldComposer = [app valueForKey:@"composerTextView"];
        oldComposer.string = @"keep original draft";
        [app showHome:nil];
        NSView *home = [app valueForKey:@"homeView"];
        CheckHome(!home.hidden, @"home entry must show the welcome page");
        NSWindow *window = [app valueForKey:@"window"];
        [window orderFront:nil];
        [window.contentView layoutSubtreeIfNeeded];
        NSSplitView *split = [app valueForKey:@"splitView"];
        for (NSNumber *width in @[@230, @340, @270]) {
            [(PTWorkspaceSplitView *)split setTrackedPosition:width.doubleValue ofDividerAtIndex:0];
            CGFloat immediateSidebarWidth = NSWidth(split.subviews[0].frame);
            for (NSUInteger pass = 0; pass < 4; pass++) {
                [window.contentView layoutSubtreeIfNeeded];
                [app updateHomeProjects];
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            }
            CheckHome(fabs(NSWidth(split.subviews[0].frame) - width.doubleValue) < 1,
                [NSString stringWithFormat:@"sidebar must retain dragged width %@ across home relayout, immediate %.1f got %.1f preference %.1f active %d", width, immediateSidebarWidth, NSWidth(split.subviews[0].frame),
                    [[[app valueForKey:@"sidebarWidthConstraint"] valueForKey:@"constant"] doubleValue],
                    [[[app valueForKey:@"sidebarWidthConstraint"] valueForKey:@"active"] boolValue]]);
        }
        CGFloat savedSidebarWidth = NSWidth(split.subviews[0].frame);
        [app toggleInspector:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.28]];
        [window.contentView layoutSubtreeIfNeeded];
        CheckHome(fabs(NSWidth(split.subviews[0].frame) - savedSidebarWidth) < 1,
            @"toggling the floating inspector must not rewrite the sidebar width");
        NSPoint dragStart = [split convertPoint:NSMakePoint(NSWidth(split.subviews[0].frame) + 0.5, 250) toView:nil];
        NSPoint dragEnd = NSMakePoint(dragStart.x + 42, dragStart.y);
        NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:dragStart modifierFlags:0
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
        for (NSNumber *type in @[@(NSEventTypeLeftMouseDragged), @(NSEventTypeLeftMouseUp)]) {
            NSEvent *event = [NSEvent mouseEventWithType:type.unsignedIntegerValue location:dragEnd modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:1];
            [NSApp postEvent:event atStart:NO];
        }
        [split mouseDown:down];
        [window.contentView layoutSubtreeIfNeeded];
        CheckHome(fabs(NSWidth(split.subviews[0].frame) - (savedSidebarWidth + 42)) < 2,
            @"a real divider mouse drag must retain its new sidebar width after layout");
        NSString *preview = NSProcessInfo.processInfo.environment[@"PT_HOME_PREVIEW"];
        if (preview.length) {
            [window orderFront:nil];
            [window.contentView layoutSubtreeIfNeeded];
            NSBitmapImageRep *bitmap = [home bitmapImageRepForCachingDisplayInRect:home.bounds];
            [home cacheDisplayInRect:home.bounds toBitmapImageRep:bitmap];
            [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:preview atomically:YES];
        }
        CheckHome([app valueForKey:@"selectedSession"] == session && [app valueForKey:@"bridge"] == original.bridge,
            @"opening home must preserve the current conversation and Terminal bridge");
        CheckHome([oldComposer.string isEqual:@"keep original draft"], @"opening home must retain the old draft");
        NSTextView *prompt = [app valueForKey:@"homePromptTextView"];
        prompt.string = @"start a separate conversation\nkeep all text";
        [app hideHome:nil];
        [app showHome:nil];
        CheckHome([prompt.string containsString:@"keep all text"], @"home draft survives leaving and returning");
        [app startHomeConversation:nil];
        CheckHome([app.launch.requestedPrompt isEqual:prompt.string], @"home must submit the complete initial message");
        CheckHome([app.launch.requestedSession.cwd isEqual:session.cwd], @"home must use the selected project directory");
        CheckHome(![app.launch.requestedSession.sessionID isEqual:session.sessionID], @"home must create a new session ID");
        CheckHome([app valueForKey:@"bridge"] == original.bridge, @"starting a new session must not replace the old bridge");
        PTSessionInfo *created = app.launch.requestedSession;
        created.title = @"New conversation";
        created.assistantMessages = @[];
        [app setValue:@[session, created] forKey:@"sessions"];
        app.launch.ready = YES;
        [app finishHomeSessionIfAvailable];
        CheckHome([[app valueForKey:@"workspaceTabs"] count] == 2, @"new conversation opens in a separate workspace tab");
        CheckHome([app valueForKey:@"selectedSession"] == created, @"new transcript must enter the existing conversation page");
        CheckHome([original.draft isEqual:@"keep original draft"], @"old workspace draft survives new conversation handoff");
        CheckHome(prompt.string.length == 0 && home.hidden, @"successful handoff clears only the submitted home prompt");
        [app setValue:nil forKey:@"selectedSession"];
        [app showHome:nil];
        prompt.string = @"unsent home draft";
        if ([app respondsToSelector:@selector(startBlankHomeConversation:)])
            [app startBlankHomeConversation:nil];
        CheckHome([app.launch.requestedSession.sessionID isEqual:@"blank-session-created-by-claude"],
            @"home must create a blank session with no selected conversation and without submitting the home draft");
        app.launch.ready = YES;
        app.launch.statusChanged(@"connected");
        PTSessionInfo *blankSession = [app valueForKey:@"selectedSession"];
        CheckHome([blankSession.sessionID isEqual:@"blank-session-created-by-claude"] && home.hidden,
            @"a connected blank conversation must open before its first transcript message exists");
        CheckHome([prompt.string isEqual:@"unsent home draft"], @"blank creation must retain unsent home text");
        [app applySessions:@[session, created]];
        CheckHome([[app valueForKey:@"selectedSession"] sessionID] &&
            [[[app valueForKey:@"selectedSession"] sessionID] isEqual:blankSession.sessionID],
            @"background disk refresh must preserve a new conversation before the first message");
        PTSessionInfo *recorded = [PTSessionInfo new];
        recorded.sessionID = blankSession.sessionID;
        recorded.cwd = blankSession.cwd;
        recorded.title = @"First prompt";
        recorded.filePath = @"/simulated/first-transcript.jsonl";
        recorded.assistantMessages = @[@{@"role": @"user", @"text": @"First prompt"}];
        recorded.modifiedAt = NSDate.date;
        [app applySessions:@[session, created, recorded]];
        CheckHome([app valueForKey:@"selectedSession"] == recorded &&
                  [[app valueForKey:@"newSessionsAwaitingTranscript"] count] == 0,
            @"the first real transcript must replace the blank session without losing its active tab");

        NSString *renameID = [@"rename-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
        PTSessionInfo *renameTarget = [PTSessionInfo new];
        renameTarget.sessionID = renameID;
        renameTarget.title = @"Original title";
        renameTarget.cwd = @"/expected/project";
        [app setValue:@[renameTarget] forKey:@"sessions"];
        NSMenu *renameMenu = [NSMenu new];
        [app populateSessionContextMenu:renameMenu forSession:renameTarget];
        NSPredicate *renameAction = [NSPredicate predicateWithBlock:^BOOL(NSMenuItem *item, NSDictionary *bindings) {
            return item.action == NSSelectorFromString(@"renameSessionFromMenu:");
        }];
        CheckHome([renameMenu.itemArray filteredArrayUsingPredicate:renameAction].count == 1,
            @"conversation context menu must expose rename for the clicked session");
        [app renameSession:renameTarget toTitle:@"老师的中文新名称"];
        PTSessionInfo *diskSession = [PTSessionInfo new];
        diskSession.sessionID = renameID;
        diskSession.title = @"Original title";
        diskSession.cwd = renameTarget.cwd;
        PTHomeDelegateProbe *reopened = [PTHomeDelegateProbe new];
        [reopened applySessions:@[diskSession]];
        CheckHome([diskSession.title isEqual:@"老师的中文新名称"], @"rename must survive disk refresh and a fresh app delegate");
        NSMutableDictionary *titles = [[NSUserDefaults.standardUserDefaults dictionaryForKey:@"PTSessionTitleOverrides"] mutableCopy];
        [titles removeObjectForKey:renameID];
        [NSUserDefaults.standardUserDefaults setObject:titles forKey:@"PTSessionTitleOverrides"];
        NSLog(@"PTHomeTests passed");
    }
    return 0;
}
