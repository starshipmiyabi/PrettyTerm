#import <AppKit/AppKit.h>
#define main PTPrettyTermApplicationMain
#import "../Sources/PrettyTerm.m"
#undef main

static void Check(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface PTClaudeBridge (NewSessionTest)
- (void)startNewSession:(PTSessionInfo *)session prompt:(NSString *)prompt;
- (void)startNewSessionInDirectory:(NSString *)directory;
@end

// Only the external Terminal/process boundary is replaced. The production
// connection selection, command construction and asynchronous binding run intact.
@interface PTLaunchProbe : PTClaudeBridge
@property(nonatomic, copy) NSArray *existingTTYs;
@property(nonatomic, copy) NSString *existingSessionID;
@property(nonatomic, copy) NSString *launchCommand;
@property(nonatomic, strong) NSMutableArray<NSString *> *shellCommands;
@property(nonatomic, copy) NSString *launchError;
@property(nonatomic, copy) NSString *scanError;
@property(nonatomic) NSUInteger launches;
@property(nonatomic) NSUInteger polls;
@property(nonatomic) BOOL exited;
@end
@implementation PTLaunchProbe
- (NSArray *)allTerminalTTYsWithError:(NSString **)error {
    if (error) *error = self.scanError;
    return self.existingTTYs ?: @[];
}
- (pid_t)claudePIDForTTY:(NSString *)tty {
    if ([tty isEqual:@"/dev/ttys-new"]) return ++self.polls >= 3 && !self.exited ? 222 : 0;
    return [tty isEqual:@"/dev/ttys-existing"] ? 111 : 0;
}
- (NSString *)cwdForPID:(pid_t)pid { return @"/expected/project"; }
- (NSDictionary *)sessionMetadataForPID:(pid_t)pid {
    return @{ @"pid": @(pid), @"sessionId": pid == 222 ? @"target-session" : self.existingSessionID ?: @"" };
}
- (NSString *)launchTerminalCommand:(NSString *)command error:(NSString **)error {
    self.launches++;
    self.launchCommand = command;
    self.shellCommands = [NSMutableArray arrayWithObject:command];
    if (error) *error = self.launchError;
    return self.launchError ? nil : @"/dev/ttys-new";
}
- (BOOL)sendShellCommand:(NSString *)command toTTY:(NSString *)tty error:(NSString **)error {
    Check([tty isEqual:@"/dev/ttys-new"], @"Claude must be submitted to the same shell that received cd");
    [self.shellCommands addObject:command];
    return YES;
}
- (NSDictionary *)terminalStateForTTY:(NSString *)tty error:(NSString **)error {
    return @{ @"busy": @(!self.exited), @"contents": @"claude: startup failed" };
}
@end

static NSString *Connect(PTLaunchProbe *bridge, PTSessionInfo *session, BOOL twice) {
    __block NSString *status = nil;
    bridge.statusChanged = ^(NSString *value) { status = value; };
    [bridge connectToSession:session];
    if (twice) [bridge connectToSession:session];
    PTRunLoopUntil(3, ^BOOL { return status != nil; });
    return status;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        if (argc == 3 && strcmp(argv[1], "--live") == 0) {
            // Explicit opt-in: a fresh synthetic transcript, never a user's
            // conversation, exercises the real Terminal, shell wrapper and CLI.
            NSString *cwd = [NSString stringWithUTF8String:argv[2]];
            NSString *sessionID = NSUUID.UUID.UUIDString.lowercaseString;
            NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:
                [@".claude/projects/" stringByAppendingString:[cwd stringByReplacingOccurrencesOfString:@"/" withString:@"-"]]];
            Check([NSFileManager.defaultManager fileExistsAtPath:directory], @"live fixture uses an existing project directory");
            NSString *path = [directory stringByAppendingPathComponent:[sessionID stringByAppendingString:@".jsonl"]];
            NSString *userID = NSUUID.UUID.UUIDString;
            NSArray *messages = @[
                @{ @"type": @"user", @"uuid": userID, @"parentUuid": NSNull.null,
                   @"sessionId": sessionID, @"cwd": cwd, @"timestamp": @"2026-09-14T00:00:00.000Z",
                   @"message": @{ @"role": @"user", @"content": @"PrettyTerm launch regression fixture" } },
                @{ @"type": @"assistant", @"uuid": NSUUID.UUID.UUIDString, @"parentUuid": userID,
                   @"sessionId": sessionID, @"cwd": cwd, @"timestamp": @"2026-09-14T00:00:01.000Z",
                   @"message": @{ @"role": @"assistant", @"id": @"msg_fixture", @"type": @"message",
                       @"model": @"claude-opus-4-6", @"stop_reason": @"end_turn",
                       @"content": @[@{ @"type": @"text", @"text": @"Fixture ready." }] } }
            ];
            NSMutableData *data = [NSMutableData data];
            for (NSDictionary *message in messages) {
                [data appendData:[NSJSONSerialization dataWithJSONObject:message options:0 error:nil]];
                [data appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
            }
            Check([data writeToFile:path atomically:YES], @"live fixture must be created");
            PTSessionInfo *session = [PTSessionInfo new];
            session.sessionID = sessionID;
            session.cwd = cwd;
            PTClaudeBridge *bridge = [PTClaudeBridge new];
            __block NSString *status = nil;
            bridge.statusChanged = ^(NSString *value) { status = value; NSLog(@"LIVE: %@", value); };
            [bridge connectToSession:session];
            PTRunLoopUntil(30, ^BOOL { return status != nil; });
            if (!bridge.running) NSLog(@"LIVE fixture retained at %@", path);
            Check(bridge.running, [NSString stringWithFormat:@"live resume must bind: %@", status]);
            pid_t pid = [[bridge valueForKey:@"terminalPID"] intValue];
            Check([[bridge sessionMetadataForPID:pid][@"sessionId"] isEqual:sessionID], @"live metadata must identify the fixture");
            NSString *tty = [bridge valueForKey:@"terminalTTY"];
            NSString *screen = [bridge terminalStateForTTY:tty error:nil][@"contents"];
            NSLog(@"LIVE bound %@ pid %d; transcript visible=%@", tty, pid, [screen containsString:@"Fixture ready"] ? @"YES" : @"NO");
            // This PID was created above for this synthetic fixture only. Keep
            // the Terminal window and its shell available after the test exits.
            kill(pid, SIGTERM);
            [bridge stop];
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            NSLog(@"PTClaudeLaunchTests live passed");
            return 0;
        }
        PTSessionInfo *session = [PTSessionInfo new];
        session.sessionID = @"target-session";
        session.cwd = @"/expected/project";
        PTLaunchProbe *blank = [PTLaunchProbe new];
        __block NSString *blankStatus = nil;
        blank.statusChanged = ^(NSString *status) { blankStatus = status; };
        if ([blank respondsToSelector:@selector(startNewSessionInDirectory:)])
            [blank startNewSessionInDirectory:session.cwd];
        PTRunLoopUntil(1, ^BOOL { return blankStatus != nil; });
        Check(blank.running && [blank.sessionID isEqual:@"target-session"],
            @"blank launch must adopt the session ID created by Claude");
        Check([blank.shellCommands isEqual:@[@"cd -- '/expected/project'", @"Claude --yolo"]],
            @"blank launch must issue only two separate ordered shell commands, without resume, session ID or prompt");
        PTLaunchProbe *newConversation = [PTLaunchProbe new];
        Check([newConversation respondsToSelector:@selector(startNewSession:prompt:)], @"new conversations need a launch path distinct from resume");
        __block NSString *newStatus = nil;
        newConversation.statusChanged = ^(NSString *status) { newStatus = status; };
        [newConversation startNewSession:session prompt:@"first line\nsecond 'quoted' line"];
        PTRunLoopUntil(3, ^BOOL { return newStatus != nil; });
        Check(newConversation.running, @"a new conversation must bind to its new session ID");
        Check([newConversation.shellCommands isEqual:@[@"cd -- '/expected/project'",
            @"Claude --yolo --session-id 'target-session' -- 'first line\nsecond '\\''quoted'\\'' line'"]],
            @"new conversation must send cd separately and retain the whole first prompt as one argument");
        for (NSArray *ttys in @[@[], @[@"/dev/ttys-idle"], @[@"/dev/ttys-existing"]]) {
            PTLaunchProbe *bridge = [PTLaunchProbe new];
            bridge.existingTTYs = ttys;
            bridge.existingSessionID = @"other-session";
            NSString *status = Connect(bridge, session, YES);
            Check(bridge.running && [bridge.sessionID isEqual:session.sessionID],
                [NSString stringWithFormat:@"missing session must launch and bind automatically (%@): %@", ttys, status]);
            Check(bridge.launches == 1, @"repeated sync must use the same launch");
            Check([[bridge valueForKey:@"terminalTTY"] isEqual:@"/dev/ttys-new"], @"must bind the newly launched tab");
            Check([bridge.shellCommands isEqual:@[@"cd -- '/expected/project'", @"Claude --yolo --resume 'target-session'"]],
                @"submit cd to the shell first, then submit Claude separately in that shell");
        }
        for (NSString *liveID in @[@"target-session", @""]) {
            PTLaunchProbe *bridge = [PTLaunchProbe new];
            bridge.existingTTYs = @[@"/dev/ttys-existing"];
            bridge.existingSessionID = liveID;
            Connect(bridge, session, NO);
            Check(bridge.running && bridge.launches == 0, @"existing exact and legacy connections must stay unchanged");
        }
        PTLaunchProbe *denied = [PTLaunchProbe new];
        denied.scanError = @"Terminal automation error";
        Check([Connect(denied, session, NO) isEqual:denied.scanError] && denied.launches == 0,
            @"an actual discovery error must be reported, not mistaken for an absent session");
        PTLaunchProbe *failed = [PTLaunchProbe new];
        failed.launchError = @"Terminal launch error";
        Check([Connect(failed, session, NO) isEqual:failed.launchError] && !failed.running,
            @"launch errors must reach the UI");
        PTLaunchProbe *exited = [PTLaunchProbe new];
        exited.exited = YES;
        Check([Connect(exited, session, NO) containsString:@"startup failed"] && !exited.running,
            @"a returned shell must report startup output and end connecting");
        NSLog(@"PTClaudeLaunchTests passed");
    }
    return 0;
}
