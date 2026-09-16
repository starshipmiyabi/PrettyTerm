#import <AppKit/AppKit.h>
#define main PTPrettyTermApplicationMain
#import "../Sources/PrettyTerm.m"
#undef main

@interface PTRenameBridgeProbe : PTClaudeBridge
@property(nonatomic, strong) PTSessionInfo *target;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL rejectSend;
@property(nonatomic, strong) NSMutableArray<NSString *> *commands;
@end
@implementation PTRenameBridgeProbe
- (instancetype)init { if ((self = [super init])) _commands = [NSMutableArray array]; return self; }
- (BOOL)running { return self.ready; }
- (NSString *)sessionID { return self.target.sessionID; }
- (void)connectToSession:(PTSessionInfo *)session { self.target = session; }
- (BOOL)sendMessage:(NSString *)message { [self.commands addObject:message]; return !self.rejectSend; }
@end

@interface PTRenameDelegateProbe : PTAppDelegate
@property(nonatomic, strong) PTRenameBridgeProbe *connection;
@property(nonatomic) NSUInteger connectionCount;
@end
@implementation PTRenameDelegateProbe
- (PTClaudeBridge *)newRenameBridge {
    self.connectionCount++;
    self.connection = [PTRenameBridgeProbe new];
    return self.connection;
}
@end

static void CheckRename(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        PTRenameDelegateProbe *app = [PTRenameDelegateProbe new];
        [app setValue:[NSMutableArray array] forKey:@"workspaceTabs"];
        [app setValue:[PTAgentState new] forKey:@"agentState"];
        for (NSString *key in @[@"pendingImages", @"pendingFiles", @"floatingPendingImages", @"floatingPendingFiles"])
            [app setValue:[NSMutableArray array] forKey:key];
        [app setValue:[NSMutableSet set] forKey:@"temporaryImagePaths"];
        [app buildWindow];
        NSTextField *status = [app valueForKey:@"statusLabel"];
        PTSessionInfo *target = [PTSessionInfo new];
        target.sessionID = [@"rename-command-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
        target.cwd = @"/expected/project";
        target.title = @"Before";
        target.assistantMessages = @[];
        [app setValue:@[target] forKey:@"sessions"];
        PTRenameBridgeProbe *connected = [PTRenameBridgeProbe new];
        connected.target = target;
        connected.ready = YES;
        PTWorkspaceTab *tab = [app createWorkspaceTab];
        tab.sessionID = target.sessionID;
        tab.bridge = connected;
        PTSessionInfo *other = [PTSessionInfo new];
        other.sessionID = @"other-active-session";
        other.title = @"Do not rename this";
        other.cwd = @"/another/project";
        other.assistantMessages = @[];
        PTRenameBridgeProbe *otherBridge = [PTRenameBridgeProbe new];
        otherBridge.target = other;
        otherBridge.ready = YES;
        PTWorkspaceTab *otherTab = [app createWorkspaceTab];
        otherTab.sessionID = other.sessionID;
        otherTab.bridge = otherBridge;
        [app setValue:otherTab forKey:@"activeWorkspaceTab"];
        [app setValue:other forKey:@"selectedSession"];
        [app setValue:otherBridge forKey:@"bridge"];
        [app setValue:@[target, other] forKey:@"sessions"];

        NSString *name = @"老师  的 \"new\" 标题";
        [app renameSession:target toTitle:name];
        CheckRename([connected.commands isEqual:@[@"/rename 老师  的 \"new\" 标题"]],
            @"rename must send the slash command and the exact user's title to the matching connected Claude session");
        CheckRename(app.connectionCount == 0, @"an existing connection must not launch another Terminal");
        CheckRename(otherBridge.commands.count == 0 && [app valueForKey:@"selectedSession"] == other,
            @"right-click rename must leave the active different conversation untouched");
        CheckRename([target.title isEqual:name], @"Claude sync must preserve local rename");

        connected.ready = NO;
        NSUInteger tabsBefore = [[app valueForKey:@"workspaceTabs"] count];
        [app renameSession:target toTitle:@"离线名称"];
        CheckRename(app.connectionCount == 1 && app.connection.target == target,
            @"offline rename must connect or resume the requested session with its cwd");
        CheckRename(app.connection.commands.count == 0, @"rename must wait until that connection completes");
        [app renameSession:target toTitle:@"最新名称"];
        CheckRename(app.connectionCount == 1, @"another title during connection must reuse the pending connection");
        PTRenameBridgeProbe *pending = app.connection;
        pending.ready = YES;
        pending.statusChanged(@"connected");
        CheckRename([pending.commands isEqual:@[@"/rename 最新名称"]], @"the final requested title must be submitted once after resume");
        CheckRename([[app valueForKey:@"workspaceTabs"] count] == tabsBefore,
            @"renaming must not create or switch workspace tabs");
        CheckRename(otherBridge.commands.count == 0 && [app valueForKey:@"selectedSession"] == other,
            @"resuming a rename target must not rename or switch to the active conversation");

        [app renameSession:target toTitle:@"连接失败也保留本地名"];
        app.connection.statusChanged(@"test connection failure");
        CheckRename([target.title isEqual:@"连接失败也保留本地名"] && [status.stringValue containsString:@"test connection failure"],
            @"connection failure must retain the local title and report the actual sync failure");
        CheckRename(app.connection.commands.count == 0, @"failed connection must not submit a rename elsewhere");

        connected.ready = YES;
        connected.rejectSend = YES;
        [app renameSession:target toTitle:@"发送失败"];
        CheckRename([target.title isEqual:@"发送失败"] && [status.stringValue containsString:@"未接受"],
            @"a rejected command must not be reported as a successful Claude rename");
        NSMutableDictionary *titles = [[NSUserDefaults.standardUserDefaults dictionaryForKey:@"PTSessionTitleOverrides"] mutableCopy];
        [titles removeObjectForKey:target.sessionID];
        [NSUserDefaults.standardUserDefaults setObject:titles forKey:@"PTSessionTitleOverrides"];
        NSLog(@"PTRenameTests passed");
    }
    return 0;
}
