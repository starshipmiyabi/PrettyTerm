#import <AppKit/AppKit.h>
#define main PTPrettyTermApplicationMain
#import "../Sources/PrettyTerm.m"
#undef main

static void Check(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}

static BOOL PTRunLoopUntil(NSTimeInterval timeout, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return condition();
}

@interface PTClaudeBridge (LaunchTestAccess)
- (BOOL)writeFrame:(NSDictionary *)frame completion:(void (^)(BOOL))completion;
- (NSString *)releaseInteractiveSession:(NSString *)sessionID;
- (void)startProcessInDirectory:(NSString *)cwd resume:(BOOL)resume model:(NSString *)model;
- (void)consumeFrame:(NSDictionary *)frame;
- (void)finishProcessIfEnded;
- (void)reportError:(NSString *)message;
- (void)completePendingSends:(BOOL)accepted;
@end

// Only the external process / pipe boundary is replaced. Production session
// selection, deduplication, initialize handshake, and error routing run intact.
@interface PTLaunchProbe : PTClaudeBridge
@property(nonatomic, copy) NSString *releaseError;
@property(nonatomic, copy) NSString *launchError;
@property(nonatomic, copy) NSString *initializeError;
@property(nonatomic, copy) NSString *stderrFailure;
@property(nonatomic) BOOL deferInitialize;
@property(nonatomic, copy) NSString *lastDirectory;
@property(nonatomic) BOOL lastResume;
@property(nonatomic, copy) NSString *lastModel;
@property(nonatomic) NSUInteger releases;
@property(nonatomic) NSUInteger launches;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *writtenFrames;
@end

@implementation PTLaunchProbe
- (instancetype)init {
    if ((self = [super init])) {
        _writtenFrames = [NSMutableArray array];
    }
    return self;
}

- (NSString *)releaseInteractiveSession:(NSString *)sessionID {
    (void)sessionID;
    self.releases++;
    return self.releaseError;
}

- (BOOL)writeFrame:(NSDictionary *)frame completion:(void (^)(BOOL))completion {
    [self.writtenFrames addObject:frame];
    if (completion) completion(YES);
    return YES;
}

- (void)startProcessInDirectory:(NSString *)cwd resume:(BOOL)resume model:(NSString *)model {
    self.launches++;
    self.lastDirectory = cwd;
    self.lastResume = resume;
    self.lastModel = model;
    if (self.launchError.length) {
        [self reportError:self.launchError];
        [self setValue:nil forKey:@"connectingSessionID"];
        [self completePendingSends:NO];
        return;
    }
    if (self.stderrFailure.length) {
        [self setValue:self.stderrFailure forKey:@"stderrText"];
        [self setValue:@YES forKey:@"stdoutEnded"];
        [self setValue:@YES forKey:@"processEnded"];
        [self setValue:@1 forKey:@"exitStatus"];
        [self finishProcessIfEnded];
        return;
    }
    NSString *initID = [NSString stringWithFormat:@"probe-init-%lu", (unsigned long)self.launches];
    [self setValue:initID forKey:@"initializeID"];
    NSDictionary *responseFrame = self.initializeError.length
        ? @{
            @"type": @"control_response",
            @"response": @{
                @"subtype": @"error",
                @"request_id": initID,
                @"error": self.initializeError
            }
        }
        : @{
            @"type": @"control_response",
            @"response": @{
                @"subtype": @"success",
                @"request_id": initID,
                @"response": @{ @"commands": @[] }
            }
        };
    if (self.deferInitialize) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf consumeFrame:responseFrame];
        });
    } else {
        [self consumeFrame:responseFrame];
    }
}
@end

static NSArray<NSDictionary *> *UserFrames(PTLaunchProbe *bridge) {
    NSMutableArray *users = [NSMutableArray array];
    for (NSDictionary *frame in bridge.writtenFrames) {
        if ([frame[@"type"] isEqual:@"user"]) [users addObject:frame];
    }
    return users;
}

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
            // conversation, exercises the real headless Claude CLI.
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
            PTRunLoopUntil(30, ^BOOL { return bridge.running || (status != nil && ![status containsString:@"已连接"]); });
            if (!bridge.running) NSLog(@"LIVE fixture retained at %@", path);
            Check(bridge.running && [bridge.sessionID isEqual:sessionID],
                [NSString stringWithFormat:@"live resume must bind: %@", status]);
            [bridge stop];
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            NSLog(@"PTClaudeLaunchTests live passed");
            return 0;
        }

        PTSessionInfo *session = [PTSessionInfo new];
        session.sessionID = @"target-session";
        session.cwd = @"/expected/project";
        session.model = @"claude-opus-5-5";

        PTLaunchProbe *blank = [PTLaunchProbe new];
        __block NSString *blankStatus = nil;
        blank.statusChanged = ^(NSString *status) { blankStatus = status; };
        Check([blank respondsToSelector:@selector(startNewSessionInDirectory:)], @"blank launch selector must exist");
        [blank startNewSessionInDirectory:session.cwd];
        PTRunLoopUntil(1, ^BOOL { return blankStatus != nil; });
        Check(blank.running && blank.sessionID.length > 0,
            @"blank launch must assign a session ID and enter running state");
        Check(blank.launches == 1 && !blank.lastResume && [blank.lastDirectory isEqual:@"/expected/project"],
            @"blank launch must start a new headless session without --resume");
        Check(blank.releases == 0 && UserFrames(blank).count == 0,
            @"blank launch must not release an existing session or send a prompt");

        PTLaunchProbe *newConversation = [PTLaunchProbe new];
        Check([newConversation respondsToSelector:@selector(startNewSession:prompt:)],
            @"new conversations need a launch path distinct from resume");
        __block NSString *newStatus = nil;
        newConversation.statusChanged = ^(NSString *status) { newStatus = status; };
        [newConversation startNewSession:session prompt:@"first line\nsecond 'quoted' line"];
        PTRunLoopUntil(3, ^BOOL { return newStatus != nil; });
        Check(newConversation.running && [newConversation.sessionID isEqual:@"target-session"],
            @"a new conversation must bind to its new session ID");
        Check(!newConversation.lastResume && newConversation.releases == 0,
            @"new conversation must launch with --session-id rather than --resume");
        NSArray<NSDictionary *> *submitted = UserFrames(newConversation);
        Check(submitted.count == 1 &&
              [submitted.firstObject[@"session_id"] isEqual:@"target-session"] &&
              [submitted.firstObject[@"message"][@"content"] isEqual:@"first line\nsecond 'quoted' line"],
            @"new conversation must emit one stream-json user frame retaining the exact multiline quoted prompt");

        PTLaunchProbe *bridge = [PTLaunchProbe new];
        bridge.deferInitialize = YES;
        NSString *status = Connect(bridge, session, YES);
        Check(bridge.running && [bridge.sessionID isEqual:session.sessionID],
            [NSString stringWithFormat:@"resume must bind cleanly: %@", status]);
        Check(bridge.launches == 1 && bridge.lastResume && bridge.releases == 1,
            @"repeated connect while connecting must deduplicate into one resume launch");
        Check([bridge.lastModel isEqual:@"claude-opus-5-5"],
            @"resuming an Opus transcript must launch with its own recorded model");
        [bridge connectToSession:session];
        PTRunLoopUntil(0.1, ^BOOL { return NO; });
        Check(bridge.launches == 1, @"connecting again while already running on the same session must be a no-op");

        NSString *overrideSessionID = [@"resume-override-" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSMutableDictionary *savedOverrides = [[NSUserDefaults.standardUserDefaults
            dictionaryForKey:@"PTSessionModelOverrides"] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSDictionary *previousOverrides = [NSUserDefaults.standardUserDefaults
            dictionaryForKey:@"PTSessionModelOverrides"];
        savedOverrides[overrideSessionID] = @"claude-fable-5-2";
        [NSUserDefaults.standardUserDefaults setObject:savedOverrides forKey:@"PTSessionModelOverrides"];
        PTSessionInfo *overriddenSession = [PTSessionInfo new];
        overriddenSession.sessionID = overrideSessionID;
        overriddenSession.cwd = @"/expected/project";
        overriddenSession.model = @"claude-opus-5-5";
        PTLaunchProbe *overridden = [PTLaunchProbe new];
        Connect(overridden, overriddenSession, NO);
        Check(overridden.running,
            @"a session with a saved model choice must reconnect");
        Check([overridden.lastModel isEqual:@"claude-fable-5-2"],
            @"an explicit per-session model choice must take precedence over the transcript model");
        if (previousOverrides) {
            [NSUserDefaults.standardUserDefaults setObject:previousOverrides forKey:@"PTSessionModelOverrides"];
        } else {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"PTSessionModelOverrides"];
        }

        PTLaunchProbe *denied = [PTLaunchProbe new];
        denied.releaseError = @"Session takeover failed";
        Check([Connect(denied, session, NO) isEqual:denied.releaseError] && denied.launches == 0 && !denied.running,
            @"a session takeover failure must be reported without launching");

        PTLaunchProbe *failed = [PTLaunchProbe new];
        failed.launchError = @"Headless launch error";
        Check([Connect(failed, session, NO) isEqual:failed.launchError] && !failed.running,
            @"launch errors must reach the UI");

        PTLaunchProbe *initError = [PTLaunchProbe new];
        initError.initializeError = @"Initialize rejected";
        Check([Connect(initError, session, NO) isEqual:initError.initializeError] && !initError.running,
            @"initialize control errors must abort running state and report the failure");

        PTLaunchProbe *exited = [PTLaunchProbe new];
        exited.stderrFailure = @"claude: startup failed";
        Check([Connect(exited, session, NO) containsString:@"startup failed"] && !exited.running,
            @"an exited process must report stderr output and end connecting");

        NSLog(@"PTClaudeLaunchTests passed");
    }
    return 0;
}
