#import <Foundation/Foundation.h>

#define main PTPrettyTermApplicationMain
#import "../Sources/PrettyTerm.m"
#undef main

static void PTParserAssert(BOOL condition, NSString *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(1);
}

static void PTAppendText(NSString *path, NSString *text) {
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

int main(void) {
    @autoreleasepool {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-parser-%@.jsonl", NSUUID.UUID.UUIDString]];
        NSString *userLine = @"{\"type\":\"user\",\"sessionId\":\"session-a\",\"cwd\":\"/tmp/project\",\"uuid\":\"u1\",\"message\":{\"role\":\"user\",\"content\":\"hello\"}}\n";
        [userLine writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSUInteger parsedSize = 0;
        PTSessionInfo *initial = PTParseSession(
            path, [NSDate dateWithTimeIntervalSince1970:1], &parsedSize);
        PTParserAssert(initial.assistantMessages.count == 1,
            @"initial parse should contain the first user message");
        PTParserAssert(parsedSize == [NSData dataWithContentsOfFile:path].length,
            @"initial parse offset should end at the completed JSONL byte");

        NSString *assistantLine = @"{\"type\":\"assistant\",\"sessionId\":\"session-a\",\"cwd\":\"/tmp/project\",\"uuid\":\"a1\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-5\",\"content\":[{\"type\":\"text\",\"text\":\"world\"}]}}\n";
        PTAppendText(path, assistantLine);
        NSUInteger appendedSize = 0;
        PTSessionInfo *appended = PTParseSessionAppending(
            path, [NSDate dateWithTimeIntervalSince1970:2], parsedSize, initial, &appendedSize);
        PTParserAssert(appended.assistantMessages.count == 2,
            @"incremental parse should append exactly one assistant message");
        PTParserAssert([appended.assistantMessages.lastObject[@"text"] isEqual:@"world"],
            @"incremental parse should preserve the appended message content");
        PTParserAssert(appendedSize == [NSData dataWithContentsOfFile:path].length,
            @"incremental parse offset should advance to the appended JSONL byte");

        NSString *partial = @"{\"type\":\"assistant\",\"sessionId\":\"session-a\",\"uuid\":\"a2\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-5\",\"content\":[{\"type\":\"text\",\"text\":\"later\"}]";
        PTAppendText(path, partial);
        NSUInteger partialSize = 0;
        PTSessionInfo *unchanged = PTParseSessionAppending(
            path, [NSDate dateWithTimeIntervalSince1970:3], appendedSize, appended, &partialSize);
        PTParserAssert(unchanged.assistantMessages.count == 2 && partialSize == appendedSize,
            @"an incomplete final JSONL record must remain pending without reparsing history");

        PTAppendText(path, @"}}\n");
        NSUInteger completedSize = 0;
        PTSessionInfo *completed = PTParseSessionAppending(
            path, [NSDate dateWithTimeIntervalSince1970:4], partialSize, unchanged, &completedSize);
        PTParserAssert(completed.assistantMessages.count == 3,
            @"the pending record should parse once its newline-terminated JSON becomes complete");
        PTParserAssert(completedSize == [NSData dataWithContentsOfFile:path].length,
            @"completed pending JSONL should advance the parse offset");

        NSUInteger fullSize = 0;
        PTSessionInfo *full = PTParseSession(
            path, [NSDate dateWithTimeIntervalSince1970:5], &fullSize);
        PTParserAssert(full.assistantMessages.count == completed.assistantMessages.count,
            @"incremental and forced full parses must converge on the same message count");
        PTParserAssert([full.assistantMessages.lastObject[@"text"] isEqual:@"later"],
            @"incremental and forced full parses must converge on the same final content");
        PTParserAssert(PTConversationTurnCount(@[
            @{ @"role": @"user", @"text": @"first" },
            @{ @"kind": @"tool", @"text": @"call" },
            @{ @"kind": @"tool", @"text": @"result" },
            @{ @"role": @"assistant", @"text": @"done" },
            @{ @"role": @"user", @"text": @"second" }
        ]) == 2, @"conversation turn count must exclude tool calls and tool results");

        NSString *contextOutput = @"<local-command-stdout>\x1B[1mContext Usage\x1B[22m\n"
            @"claude-sonnet-5\n56.6k/967k tokens (6%)\n"
            @"System prompt: 9.3k tokens (1.0%)\n"
            @"System tools: 17.1k tokens (1.8%)\n"
            @"Memory files: 5.5k tokens (0.6%)\n"
            @"Skills: 2.2k tokens (0.2%)\n"
            @"Messages: 22.5k tokens (2.3%)\n"
            @"Free space: 877.4k (90.7%)\n"
            @"Autocompact buffer: 33k tokens (3.4%)</local-command-stdout>";
        NSDictionary *contextRecord = @{
            @"type": @"system", @"subtype": @"local_command",
            @"sessionId": @"session-a", @"uuid": @"context-1",
            @"content": contextOutput
        };
        NSData *contextJSON = [NSJSONSerialization dataWithJSONObject:contextRecord options:0 error:nil];
        PTAppendText(path, [[NSString alloc] initWithFormat:@"%@\n",
            [[NSString alloc] initWithData:contextJSON encoding:NSUTF8StringEncoding]]);
        PTSessionInfo *withContext = PTParseSessionAppending(
            path, [NSDate dateWithTimeIntervalSince1970:5.5], fullSize, full, NULL);
        PTParserAssert(withContext.contextUsed == 56600 && withContext.contextWindow == 967000,
            @"the real /context summary must replace the coarse model-window estimate");
        PTParserAssert(withContext.contextBreakdown.count == 7,
            @"the real /context category breakdown must survive transcript parsing");
        PTParserAssert([withContext.contextBreakdown.firstObject[@"category"] isEqual:@"system_prompt"] &&
            [withContext.contextBreakdown.lastObject[@"category"] isEqual:@"autocompact_buffer"],
            @"context categories must preserve Claude Code display order");

        NSDictionary *markdownContext = PTContextSnapshotFromText(
            @"## Context Usage\n\n**Tokens:** 56.6k / 967k (6%)\n\n"
             "| Category | Tokens | Percentage |\n|---|---|---|\n"
             "| System prompt | 9.3k | 1.0% |\n"
             "| MCP tools (deferred) | 7.6k | 0.8% |\n"
             "| Messages | 22.5k | 2.3% |\n"
             "| Free space | 877.4k | 90.7% |\n"
             "| Autocompact buffer | 33k | 3.4% |\n");
        PTParserAssert([markdownContext[@"categories"] count] == 4,
            @"Markdown /context parsing must ignore deferred tools that are not loaded");

        NSString *addDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-add-dir-%@", NSUUID.UUID.UUIDString]];
        NSString *addDirectoryText = [NSString stringWithFormat:
            @"<local-command-stdout>Added \x1B[1m%@\x1B[22m as a working directory for this session \x1B[2m· /permissions to manage\x1B[22m</local-command-stdout>",
            addDirectoryPath];
        NSDictionary *addDirectoryRecord = @{
            @"type": @"user",
            @"sessionId": @"session-add-dir",
            @"cwd": @"/tmp/project",
            @"uuid": @"add-dir-u1",
            @"message": @{ @"role": @"user", @"content": addDirectoryText }
        };
        NSData *addDirectoryJSON = [NSJSONSerialization dataWithJSONObject:addDirectoryRecord
            options:0 error:nil];
        NSMutableData *addDirectoryJSONL = [addDirectoryJSON mutableCopy];
        [addDirectoryJSONL appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        NSString *addDirectoryFile = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-add-dir-parser-%@.jsonl", NSUUID.UUID.UUIDString]];
        [addDirectoryJSONL writeToFile:addDirectoryFile atomically:YES];
        NSString *readDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-agent-read-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:readDirectory
            withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *readFile = [readDirectory stringByAppendingPathComponent:@"Notes.md"];
        NSString *bashDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-agent-bash-%@", NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:bashDirectory
            withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *agentAccessRecord = @{
            @"type": @"assistant",
            @"sessionId": @"session-add-dir",
            @"cwd": @"/tmp/project",
            @"uuid": @"agent-access-a1",
            @"message": @{
                @"role": @"assistant",
                @"model": @"claude-sonnet-5",
                @"content": @[
                    @{ @"type": @"tool_use", @"name": @"Read",
                       @"input": @{ @"file_path": readFile } },
                    @{ @"type": @"tool_use", @"name": @"Bash",
                       @"input": @{ @"command": [NSString stringWithFormat:@"ls \"%@\"", bashDirectory] } }
                ]
            }
        };
        NSData *agentAccessJSON = [NSJSONSerialization dataWithJSONObject:agentAccessRecord
            options:0 error:nil];
        PTAppendText(addDirectoryFile, [[[NSString alloc] initWithData:agentAccessJSON
            encoding:NSUTF8StringEncoding] stringByAppendingString:@"\n"]);
        PTSessionInfo *addDirectorySession = PTParseSession(
            addDirectoryFile, [NSDate dateWithTimeIntervalSince1970:6], NULL);
        PTParserAssert([addDirectorySession.accessedDirectories containsObject:
            addDirectoryPath.stringByStandardizingPath],
            @"ANSI-colored /add-dir output must add its directory to the session immediately");
        PTParserAssert([addDirectorySession.accessedDirectories containsObject:
            readFile.stringByDeletingLastPathComponent.stringByStandardizingPath],
            @"structured Agent file access must remember the containing directory");
        PTParserAssert([addDirectorySession.accessedDirectories containsObject:
            bashDirectory.stringByStandardizingPath],
            @"quoted absolute paths in Agent Bash commands must be remembered");
        PTParserAssert(!PTStoredDirectoryPathIsValid(@"/missing-loop.jsonl; do\necho"),
            @"legacy Bash fragments must be removed from persisted directory memory");
        PTParserAssert(PTStoredDirectoryPathIsValid(@"/Volumes/Temporarily Offline/Project"),
            @"temporarily unmounted external-volume directories must remain remembered");

        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [NSFileManager.defaultManager removeItemAtPath:addDirectoryFile error:nil];
        [NSFileManager.defaultManager removeItemAtPath:readDirectory error:nil];
        [NSFileManager.defaultManager removeItemAtPath:bashDirectory error:nil];

        // AskUserQuestion：待答时落成一条 kind=="question" 事件；老师（或 Terminal 里
        // 手动作答）之后追加的 tool_result 必须原地把它改成 answered=YES，
        // 而不是另起一条工具结果气泡。
        NSString *questionFile = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"prettyterm-question-%@.jsonl", NSUUID.UUID.UUIDString]];
        NSDictionary *questionRecord = @{
            @"type": @"assistant", @"sessionId": @"session-q", @"uuid": @"q-a1",
            @"message": @{
                @"role": @"assistant", @"model": @"claude-sonnet-5",
                @"content": @[ @{
                    @"type": @"tool_use", @"id": @"toolu_test1", @"name": @"AskUserQuestion",
                    @"input": @{ @"questions": @[ @{
                        @"question": @"选哪个？", @"header": @"H", @"multiSelect": @NO,
                        @"options": @[
                            @{ @"label": @"甲", @"description": @"d1" },
                            @{ @"label": @"乙", @"description": @"d2" }
                        ]
                    } ] }
                } ]
            }
        };
        NSData *questionJSON = [NSJSONSerialization dataWithJSONObject:questionRecord options:0 error:nil];
        NSString *questionLine = [NSString stringWithFormat:@"%@\n",
            [[NSString alloc] initWithData:questionJSON encoding:NSUTF8StringEncoding]];
        [questionLine writeToFile:questionFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSUInteger questionSize = 0;
        PTSessionInfo *pendingQuestion = PTParseSession(
            questionFile, [NSDate dateWithTimeIntervalSince1970:1], &questionSize);
        PTParserAssert(pendingQuestion.assistantMessages.count == 1,
            @"AskUserQuestion tool_use must produce exactly one event");
        NSDictionary *pendingEvent = pendingQuestion.assistantMessages.firstObject;
        PTParserAssert([pendingEvent[@"kind"] isEqual:@"question"],
            @"AskUserQuestion tool_use must parse as kind==question, not a generic tool bubble");
        PTParserAssert([pendingEvent[@"answered"] isEqual:@NO],
            @"a freshly-asked question must start as answered=NO");
        PTParserAssert([pendingEvent[@"toolUseId"] isEqual:@"toolu_test1"],
            @"the question event must carry the tool_use id for later answer matching");

        NSDictionary *answerRecord = @{
            @"type": @"user", @"sessionId": @"session-q", @"uuid": @"q-u1",
            @"message": @{
                @"role": @"user",
                @"content": @[ @{
                    @"type": @"tool_result", @"tool_use_id": @"toolu_test1",
                    @"content": @"The user answered: \"选哪个？\"=\"甲\""
                } ]
            },
            @"toolUseResult": @{ @"answers": @{ @"选哪个？": @"甲" } }
        };
        NSData *answerJSON = [NSJSONSerialization dataWithJSONObject:answerRecord options:0 error:nil];
        NSString *answerLine = [NSString stringWithFormat:@"%@\n",
            [[NSString alloc] initWithData:answerJSON encoding:NSUTF8StringEncoding]];
        PTAppendText(questionFile, answerLine);
        NSUInteger answeredSize = 0;
        PTSessionInfo *answeredQuestion = PTParseSessionAppending(
            questionFile, [NSDate dateWithTimeIntervalSince1970:2], questionSize, pendingQuestion, &answeredSize);
        PTParserAssert(answeredQuestion.assistantMessages.count == 1,
            @"answering the question must update the existing event in place, not append a second bubble");
        NSDictionary *answeredEvent = answeredQuestion.assistantMessages.firstObject;
        PTParserAssert([answeredEvent[@"answered"] isEqual:@YES],
            @"the tool_result carrying this toolUseId must flip the event to answered=YES");
        PTParserAssert([answeredEvent[@"answerText"] isEqual:@"选哪个？：甲"],
            @"answerText must come from toolUseResult.answers, formatted as question：answer");

        [NSFileManager.defaultManager removeItemAtPath:questionFile error:nil];

        puts("PTSessionParserTests: PASS");
    }
    return 0;
}
