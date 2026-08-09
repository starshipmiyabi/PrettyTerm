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

        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        puts("PTSessionParserTests: PASS");
    }
    return 0;
}
