#import <AppKit/AppKit.h>
#define main PTPrettyTermApplicationMain
#import "../Sources/PrettyTerm.m"
#undef main

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
        [app setValue:[PTAgentState new] forKey:@"agentState"];
        for (NSString *key in @[@"pendingImages", @"pendingFiles", @"floatingPendingImages", @"floatingPendingFiles", @"workspaceTabs"])
            [app setValue:[NSMutableArray array] forKey:key];
        [app setValue:[NSMutableSet set] forKey:@"temporaryImagePaths"];
        PTWorkspaceTab *original = [app createWorkspaceTab];
        [app setValue:original forKey:@"activeWorkspaceTab"];
        [app setValue:original.bridge forKey:@"bridge"];
        PTSessionInfo *session = [PTSessionInfo new];
        session.sessionID = @"original";
        session.cwd = NSTemporaryDirectory();
        [app setValue:session forKey:@"selectedSession"];
        [app setValue:@[session] forKey:@"sessions"];
        original.draft = @"keep original draft";
        PTFrontendBridge *surface = [[PTFrontendBridge alloc] initWithSurface:@"main" delegate:app];
        NSString *prompt = @"start a separate conversation\nkeep all text";
        [app frontendBridge:surface didInvokeAction:@"startNewConversation"
                     payload:@{@"cwd": session.cwd, @"prompt": prompt}
                       reply:^(NSDictionary *data, NSString *error) {
            (void)data;
            CheckHome(!error, @"new conversation request must be accepted");
        }];
        CheckHome([app.launch.requestedPrompt isEqual:prompt], @"home must submit the complete initial message");
        CheckHome([app.launch.requestedSession.cwd isEqual:session.cwd.stringByStandardizingPath], @"home must use the selected project directory");
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
        [app frontendBridge:surface didInvokeAction:@"startNewConversation"
                     payload:@{@"cwd": session.cwd, @"prompt": @""}
                       reply:^(NSDictionary *data, NSString *error) {
            (void)data;
            CheckHome(!error, @"blank conversation request must be accepted");
        }];
        CheckHome([app.launch.requestedSession.sessionID isEqual:@"blank-session-created-by-claude"],
            @"home must create a blank session with no selected conversation and without submitting the home draft");
        app.launch.ready = YES;
        app.launch.statusChanged(@"connected");
        PTSessionInfo *blankSession = [app valueForKey:@"selectedSession"];
        CheckHome([blankSession.sessionID isEqual:@"blank-session-created-by-claude"],
            @"a connected blank conversation must open before its first transcript message exists");
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
