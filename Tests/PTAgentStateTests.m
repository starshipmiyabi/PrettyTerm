#import <Foundation/Foundation.h>
#import "../Sources/PTAgentState.h"

extern NSInteger PTFloatingConversationActionForState(
    BOOL visible,
    NSString *pinnedSessionID,
    NSString *selectedSessionID
);
extern BOOL PTSessionRenderNeedsUpdate(
    NSString *renderedSessionID,
    NSDate *renderedModifiedAt,
    NSUInteger renderedMessageCount,
    NSString *sessionID,
    NSDate *modifiedAt,
    NSUInteger messageCount
);

static void PTAssert(BOOL condition, NSString *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        PTAgentState *state = [[PTAgentState alloc] init];
        state.selectedSessionID = @"session-a";
        state.boundSessionID = @"session-a";
        state.bridgeRunning = YES;
        PTAssert(state.commandsEnabled, @"matching selected and bound sessions should enable commands");

        state.selectedSessionID = @"session-b";
        PTAssert(!state.commandsEnabled, @"selecting another session must disable every command");

        state.selectedSessionID = @"session-a";
        state.sendInFlight = YES;
        PTAssert(!state.commandsEnabled, @"an in-flight send must block duplicate submissions");

        PTRefreshGate *gate = [[PTRefreshGate alloc] init];
        PTAssert([gate beginRefresh], @"the first refresh request should start immediately");
        PTAssert(![gate beginRefresh], @"a refresh requested while parsing should be coalesced");
        PTAssert([gate finishRefreshNeedsAnotherPass],
            @"finishing a busy refresh must report the coalesced follow-up");
        PTAssert([gate beginRefresh], @"the coalesced follow-up should be allowed to start");
        PTAssert(![gate finishRefreshNeedsAnotherPass],
            @"a refresh with no concurrent request should finish cleanly");

        PTAssert(PTIsSupportedImagePath(@"/tmp/photo.PNG"),
            @"common image extensions should be accepted case-insensitively");
        PTAssert(PTIsSupportedImagePath(@"/tmp/camera.heic"),
            @"camera HEIC photos should be accepted");
        PTAssert(!PTIsSupportedImagePath(@"/tmp/report.pdf"),
            @"non-image files must be rejected");
        PTAssert(!PTIsSupportedImagePath(@"/tmp/no-extension"),
            @"files without an image extension must be rejected");
        PTAssert([PTMessageForClaudeAttachments(@"  请比较  ", 2)
            isEqual:@"请比较"],
            @"native Claude image attachments must not be downgraded to path text");
        PTAssert([PTMessageForClaudeAttachments(@"", 1) isEqual:@" "],
            @"an image-only turn needs a harmless submit character after native paste");
        PTAssert([PTMessageForClaudeAttachments(@"", 0) isEqual:@""],
            @"an empty turn without attachments must remain unsendable");
        PTAssert([PTNormalizedTerminalPasteText(@"单行消息") isEqual:@"单行消息"],
            @"single-line paste text must remain byte-for-byte stable");
        PTAssert([PTNormalizedTerminalPasteText(@"第一行\r\n第二行\r第三行") isEqual:
            @"第一行\n第二行\n第三行"],
            @"native multiline paste must normalize CRLF and CR without losing line breaks");
        PTAssert([PTTerminalSubmissionPayload(@"单行消息") isEqual:@"单行消息"],
            @"single-line Terminal submissions must not gain control sequences");
        NSString *escape = [NSString stringWithFormat:@"%C", (unichar)0x1B];
        PTAssert([PTTerminalSubmissionPayload(@"第一行\r\n第二行") isEqual:
            [NSString stringWithFormat:@"%@[200~第一行\n第二行%@[201~", escape, escape]],
            @"multiline Terminal submissions must use one complete bracketed-paste frame");
        PTAssert(PTLatestTerminalPasteMarker(@"before\n[Pasted text #2 +4 lines]\nafter") == 2,
            @"Terminal paste acknowledgement must read Claude's visible marker number");
        PTAssert(PTLatestTerminalPasteMarker(
            @"[Pasted text #2 +4 lines]\n[Pasted text #7 +1 lines]") == 7,
            @"Terminal paste acknowledgement must use the newest visible marker");
        PTAssert(PTLatestTerminalPasteMarker(@"ordinary terminal contents") == -1,
            @"ordinary Terminal contents must not look like a paste acknowledgement");
        PTAssert(PTComposerActionForKey(36, NO, NO, NO) == PTComposerKeyActionSubmit,
            @"Return should submit the composer");
        PTAssert(PTComposerActionForKey(76, NO, NO, NO) == PTComposerKeyActionSubmit,
            @"keypad Enter should submit the composer");
        PTAssert(PTComposerActionForKey(36, YES, NO, NO) == PTComposerKeyActionInsertNewline,
            @"Command-Return should insert a newline");
        PTAssert(PTComposerActionForKey(36, NO, YES, NO) == PTComposerKeyActionInsertNewline,
            @"Shift-Return should insert a newline");
        PTAssert(PTComposerActionForKey(36, YES, YES, NO) == PTComposerKeyActionInsertNewline,
            @"Command-Shift-Return should still insert only a newline");
        PTAssert(PTComposerActionForKey(36, NO, NO, YES) == PTComposerKeyActionDefer,
            @"Return must remain available to confirm an IME candidate");
        PTAssert(PTComposerActionForKey(0, NO, NO, NO) == PTComposerKeyActionDefer,
            @"ordinary keys should use the text view's default behavior");
        PTAssert(PTFloatingConversationActionForState(NO, @"", @"session-a") == 1,
            @"Command-O should open a floating window for the selected session");
        PTAssert(PTFloatingConversationActionForState(YES, @"session-a", @"session-a") == 2,
            @"toggling the already pinned session should close its floating window");
        PTAssert(PTFloatingConversationActionForState(YES, @"session-a", @"session-b") == 1,
            @"toggling another session should replace the single floating window");
        PTAssert(PTFloatingConversationActionForState(NO, @"", @"") == 0,
            @"a floating window cannot open without a selected session");
        NSDate *revisionA = [NSDate dateWithTimeIntervalSince1970:1000.10];
        NSDate *revisionB = [NSDate dateWithTimeIntervalSince1970:1000.20];
        PTAssert(!PTSessionRenderNeedsUpdate(@"a", revisionA, 8, @"a", revisionA, 8),
            @"an identical rendered revision must be skipped");
        PTAssert(PTSessionRenderNeedsUpdate(@"a", revisionA, 8, @"a", revisionB, 8),
            @"same-count content appended later must still refresh");
        PTAssert(PTSessionRenderNeedsUpdate(@"a", revisionA, 8, @"a", revisionA, 9),
            @"a new message must refresh");
        PTAssert(PTSessionRenderNeedsUpdate(@"a", revisionA, 8, @"b", revisionA, 8),
            @"a different session must refresh");

        NSString *watchPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-watch-%@.jsonl", NSUUID.UUID.UUIDString]];
        [NSData.data writeToFile:watchPath atomically:YES];
        dispatch_semaphore_t changed = dispatch_semaphore_create(0);
        PTTranscriptWatcher *watcher = [[PTTranscriptWatcher alloc] init];
        PTAssert([watcher watchFileAtPath:watchPath onChange:^{
            dispatch_semaphore_signal(changed);
        }], @"a selected transcript should be watchable");
        NSFileHandle *writer = [NSFileHandle fileHandleForWritingAtPath:watchPath];
        [writer seekToEndOfFile];
        [writer writeData:[@"{\"type\":\"assistant\"}\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [writer closeFile];
        PTAssert(dispatch_semaphore_wait(changed,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))) == 0,
            @"appending an assistant record must trigger an immediate transcript refresh");
        [watcher stopWatching];
        [NSFileManager.defaultManager removeItemAtPath:watchPath error:nil];

        NSArray<NSDictionary *> *events = @[
            @{@"kind": @"diff", @"filePath": @"/tmp/PrettyTerm.m",
              @"oldText": @"a\nb\nc", @"newText": @"a\nB\nc\nd"},
            @{@"kind": @"diff", @"filePath": @"/tmp/PrettyTerm.m",
              @"oldText": @"x", @"newText": @"x\ny"},
            @{@"kind": @"diff", @"filePath": @"relative.txt",
              @"oldText": @"", @"newText": @"ignored"},
            @{@"kind": @"tool", @"filePath": @"/tmp/not-a-diff",
              @"oldText": @"", @"newText": @"ignored"}
        ];
        NSArray<NSDictionary *> *files = PTAggregateChangedFiles(events);
        PTAssert(files.count == 1, @"only absolute paths from diff events should be aggregated");
        NSDictionary *file = files.firstObject;
        PTAssert([file[@"filePath"] isEqual:@"/tmp/PrettyTerm.m"], @"file path should be preserved");
        PTAssert([file[@"added"] integerValue] == 3, @"added line count should use line diff");
        PTAssert([file[@"removed"] integerValue] == 1, @"removed line count should use line diff");
        PTAssert([file[@"changeCount"] integerValue] == 2, @"edits to the same file should merge");

        NSDictionary *thinking = PTEventFromAssistantBlock(
            @{@"type": @"thinking", @"thinking": @"先检查状态"}, @"k1", @"t", @"Claude");
        PTAssert([thinking[@"kind"] isEqual:@"thinking"], @"thinking blocks should become folded thinking events");
        PTAssert([thinking[@"text"] isEqual:@"先检查状态"], @"thinking text should be preserved");

        NSDictionary *tool = PTEventFromAssistantBlock(
            @{@"type": @"tool_use", @"name": @"Read",
              @"input": @{@"file_path": @"/tmp/a.m"}}, @"k2", @"t", @"Claude");
        PTAssert([tool[@"kind"] isEqual:@"tool"], @"ordinary tool calls should become tool events");
        PTAssert([tool[@"text"] containsString:@"a.m"], @"tool inputs should remain inspectable");

        NSDictionary *error = PTEventFromToolResultBlock(
            @{@"type": @"tool_result", @"is_error": @YES,
              @"content": @"permission denied"}, @"k3", @"t");
        PTAssert([error[@"kind"] isEqual:@"error"], @"failed tool results should be expanded error events");
        PTAssert([error[@"text"] isEqual:@"permission denied"], @"tool result text should be preserved");

        puts("PTAgentStateTests: PASS");
    }
    return 0;
}
