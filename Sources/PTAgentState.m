#import "PTAgentState.h"
#import <fcntl.h>

@implementation PTAgentState

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedSessionID = @"";
        _boundSessionID = @"";
    }
    return self;
}

- (BOOL)commandsEnabled {
    return self.selectedSessionID.length > 0;
}

@end

@implementation PTRefreshGate {
    BOOL _refreshing;
    BOOL _pending;
}

- (BOOL)beginRefresh {
    @synchronized (self) {
        if (_refreshing) {
            _pending = YES;
            return NO;
        }
        _refreshing = YES;
        return YES;
    }
}

- (BOOL)finishRefreshNeedsAnotherPass {
    @synchronized (self) {
        _refreshing = NO;
        BOOL needsAnotherPass = _pending;
        _pending = NO;
        return needsAnotherPass;
    }
}

@end

@implementation PTTranscriptWatcher {
    dispatch_queue_t _queue;
    dispatch_source_t _source;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.yuuka.prettyterm.transcript-watch", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)watchFileAtPath:(NSString *)path onChange:(dispatch_block_t)onChange {
    [self stopWatching];
    if (![path isKindOfClass:NSString.class] || path.length == 0 || !onChange) return NO;

    int descriptor = open(path.fileSystemRepresentation, O_EVTONLY);
    if (descriptor < 0) return NO;
    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_VNODE,
        (uintptr_t)descriptor,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE |
            DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE,
        _queue
    );
    if (!source) {
        close(descriptor);
        return NO;
    }
    dispatch_source_set_event_handler(source, ^{
        onChange();
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(descriptor);
    });
    _source = source;
    dispatch_resume(source);
    return YES;
}

- (void)stopWatching {
    if (!_source) return;
    dispatch_source_cancel(_source);
    _source = nil;
}

- (void)dealloc {
    [self stopWatching];
}

@end

BOOL PTIsSupportedImagePath(NSString *path) {
    if (![path isKindOfClass:NSString.class] || path.length == 0) return NO;
    static NSSet<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[
            @"png", @"jpg", @"jpeg", @"heic", @"heif",
            @"webp", @"gif", @"tif", @"tiff", @"bmp"
        ]];
    });
    return [extensions containsObject:path.pathExtension.lowercaseString];
}

NSString *PTMessageForClaudeAttachments(NSString *message, NSUInteger imageCount) {
    NSString *trimmed = [[message ?: @"" stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
    if (trimmed.length || imageCount == 0) return trimmed;
    // Claude Code 已经通过 Ctrl+V 在输入缓冲区建立原生 [Image #N] 附件；
    // 图片-only 回合仍需一个字符让现有 Terminal 提交路径执行 Return。
    return @" ";
}

static NSString *PTXMLAttachmentPath(NSString *path) {
    NSString *escaped = [path stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    return [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
}

NSString *PTMessageByAppendingClaudeAttachMarkers(
    NSString *message,
    NSArray<NSString *> *filePaths
) {
    NSString *trimmed = [[message ?: @"" stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
    NSMutableOrderedSet<NSString *> *references = [NSMutableOrderedSet orderedSet];
    for (NSString *path in filePaths ?: @[]) {
        if (![path isKindOfClass:NSString.class] || path.length == 0 || ![path hasPrefix:@"/"]) continue;
        NSString *standardized = path.stringByStandardizingPath;
        if (standardized.length == 0) continue;
        [references addObject:[NSString stringWithFormat:@"<attach>%@</attach>",
            PTXMLAttachmentPath(standardized)]];
    }
    if (references.count == 0) return trimmed;
    NSString *fileBlock = [references.array componentsJoinedByString:@"\n"];
    return trimmed.length
        ? [NSString stringWithFormat:@"%@\n\n%@", trimmed, fileBlock]
        : fileBlock;
}

NSString *PTNormalizedTerminalPasteText(NSString *message) {
    NSString *value = message ?: @"";
    NSString *normalized = [[value stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSMutableString *safe = [NSMutableString stringWithCapacity:normalized.length];
    [normalized enumerateSubstringsInRange:NSMakeRange(0, normalized.length)
        options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            (void)substringRange;
            (void)enclosingRange;
            (void)stop;
            if (substring.length == 0) return;
            unichar first = [substring characterAtIndex:0];
            BOOL permittedWhitespace = first == '\n' || first == '\t';
            BOOL control = first < 0x20 || (first >= 0x7F && first <= 0x9F);
            if (!control || permittedWhitespace) [safe appendString:substring];
        }];
    return safe;
}

NSString *PTTerminalSubmissionPayload(NSString *message) {
    NSString *normalized = PTNormalizedTerminalPasteText(message);
    if ([normalized rangeOfString:@"\n"].location == NSNotFound) return normalized;

    // Terminal 的 `do script` 会在正文末尾自动追加且只追加一次 CR。
    // 多行正文必须先放进 bracketed-paste 区间：Claude 把其中的换行当作
    // 一条消息的内容，区间外由 Terminal 追加的 CR 才是提交动作。
    NSString *escape = [NSString stringWithFormat:@"%C", (unichar)0x1B];
    return [NSString stringWithFormat:@"%@[200~%@%@[201~",
        escape, normalized, escape];
}

NSInteger PTLatestTerminalPasteMarker(NSString *contents) {
    if (contents.length == 0) return -1;
    static NSRegularExpression *pattern;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:
            @"\\[Pasted text #([0-9]+)(?: [^\\]]*)?\\]"
            options:0 error:nil];
    });
    __block NSInteger latest = -1;
    [pattern enumerateMatchesInString:contents options:0
        range:NSMakeRange(0, contents.length)
        usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            (void)flags;
            (void)stop;
            if (match.numberOfRanges < 2) return;
            NSInteger value = [[contents substringWithRange:[match rangeAtIndex:1]] integerValue];
            latest = MAX(latest, value);
        }];
    return latest;
}

static NSString *PTAppleScriptEmbeddedText(NSString *value) {
    NSString *escaped = [value ?: @"" stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *escape = [NSString stringWithFormat:@"%C", (unichar)0x1B];
    escaped = [escaped stringByReplacingOccurrencesOfString:escape
        withString:@"\" & (ASCII character 27) & \""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n\n"
        withString:@"\" & linefeed & linefeed & \""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n"
        withString:@"\" & linefeed & \""];
    return [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@""];
}

NSString *PTTerminalAutomationScript(
    NSString *tty,
    pid_t claudePID,
    NSString *message,
    PTTerminalAutomationAction action
) {
    if (tty.length == 0 || claudePID <= 0) return @"";
    NSString *writeCommand = nil;
    switch (action) {
        case PTTerminalAutomationActionWriteText:
            if (message.length == 0) return @"";
            writeCommand = [NSString stringWithFormat:@"do script \"%@\" in theTab",
                PTAppleScriptEmbeddedText(message)];
            break;
        case PTTerminalAutomationActionSubmitReturn:
            // Terminal 会自动在每次 do script 后附加一个 CR。传入空字符串正好
            // 只产生这一个提交回车；显式传入 CR 会变成两个连续回车。
            writeCommand = @"do script \"\" in theTab";
            break;
        case PTTerminalAutomationActionPasteImage:
            // Terminal 会给 do script 自动追加 CR；若用它发送 Ctrl-V，图片会在
            // 正文写入前被立即提交成独立回合。改为真实按键事件，只把图片放进
            // Claude 当前输入缓冲区，最终由统一的正文提交动作发送整条消息。
            writeCommand =
                @"set selected tab of theWindow to theTab\n"
                 "set index of theWindow to 1\n"
                 "activate\n"
                 "tell application \"System Events\" to key code 9 using control down";
            break;
        case PTTerminalAutomationActionInterruptEscape:
            writeCommand =
                @"set selected tab of theWindow to theTab\n"
                 "set index of theWindow to 1\n"
                 "activate\n"
                 "tell application \"System Events\" to key code 53";
            break;
    }
    NSString *shortTTY = tty.lastPathComponent;
    return [NSString stringWithFormat:
        @"tell application id \"com.apple.Terminal\"\n"
         "repeat with theWindow in windows\n"
         "repeat with theTab in tabs of theWindow\n"
         "if (tty of theTab) is \"%@\" then\n"
         "set liveTTY to my (do shell script \"/bin/ps -p %d -o tty= | /usr/bin/xargs\")\n"
         "if liveTTY is not \"%@\" then return \"mismatch\"\n"
         "set isClaudeProcess to false\n"
         // 必须先落到一个本地变量：直接 repeat with p in (processes of theTab) 时，
         // p 仍是 "item N of «class prcs» of item N of every ttab of ..." 这样的多层
         // 嵌套引用，(contents of p) as text 会以 -1700 强转失败。先赋值一次即完成解引用。
         "set processNames to processes of theTab\n"
         "repeat with p in processNames\n"
         "set processName to (contents of p) as text\n"
         "if processName is \"claude\" then set isClaudeProcess to true\n"
         "end repeat\n"
         "if isClaudeProcess is false then return \"mismatch\"\n"
         "%@\n"
         "return \"ok\"\n"
         "end if\n"
         "end repeat\n"
         "end repeat\n"
         "return \"missing\"\n"
         "end tell",
         PTAppleScriptEmbeddedText(tty), claudePID,
         PTAppleScriptEmbeddedText(shortTTY), writeCommand];
}

PTComposerKeyAction PTComposerActionForKey(
    unsigned short keyCode,
    BOOL commandDown,
    BOOL shiftDown,
    BOOL hasMarkedText
) {
    BOOL isReturn = keyCode == 36 || keyCode == 76;
    if (!isReturn || hasMarkedText) return PTComposerKeyActionDefer;
    return (commandDown || shiftDown)
        ? PTComposerKeyActionInsertNewline
        : PTComposerKeyActionSubmit;
}

PTFloatingConversationAction PTFloatingConversationActionForState(
    BOOL visible,
    NSString *pinnedSessionID,
    NSString *selectedSessionID
) {
    if (selectedSessionID.length == 0) return PTFloatingConversationActionNone;
    if (visible && [pinnedSessionID isEqual:selectedSessionID]) {
        return PTFloatingConversationActionClose;
    }
    return PTFloatingConversationActionOpen;
}

BOOL PTSessionRenderNeedsUpdate(
    NSString *renderedSessionID,
    NSDate *renderedModifiedAt,
    NSUInteger renderedMessageCount,
    NSString *sessionID,
    NSDate *modifiedAt,
    NSUInteger messageCount
) {
    if (sessionID.length == 0) return NO;
    if (![renderedSessionID isEqual:sessionID]) return YES;
    if (renderedMessageCount != messageCount) return YES;
    if (!renderedModifiedAt || !modifiedAt) return YES;
    return ![renderedModifiedAt isEqualToDate:modifiedAt];
}

static NSArray<NSString *> *PTLines(NSString *value) {
    NSString *normalized = [[value ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    return normalized.length ? [normalized componentsSeparatedByString:@"\n"] : @[];
}

NSDictionary<NSString *, NSNumber *> *PTDiffStats(NSString *oldText, NSString *newText) {
    NSArray<NSString *> *before = PTLines(oldText);
    NSArray<NSString *> *after = PTLines(newText);
    NSOrderedCollectionDifference<NSString *> *difference = [after differenceFromArray:before];
    return @{
        @"added": @(difference.insertions.count),
        @"removed": @(difference.removals.count)
    };
}

NSArray<NSDictionary *> *PTAggregateChangedFiles(NSArray<NSDictionary *> *events) {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *byPath = [NSMutableDictionary dictionary];
    for (NSDictionary *event in events) {
        if (![event[@"kind"] isEqual:@"diff"]) continue;
        NSString *path = [event[@"filePath"] isKindOfClass:NSString.class] ? event[@"filePath"] : @"";
        if (![path hasPrefix:@"/"]) continue;
        NSDictionary *stats = PTDiffStats(event[@"oldText"], event[@"newText"]);
        NSMutableDictionary *summary = byPath[path];
        if (!summary) {
            summary = [@{
                @"filePath": path,
                @"displayName": path.lastPathComponent ?: path,
                @"added": @0,
                @"removed": @0,
                @"changeCount": @0
            } mutableCopy];
            byPath[path] = summary;
        }
        summary[@"added"] = @([summary[@"added"] unsignedIntegerValue] + [stats[@"added"] unsignedIntegerValue]);
        summary[@"removed"] = @([summary[@"removed"] unsignedIntegerValue] + [stats[@"removed"] unsignedIntegerValue]);
        summary[@"changeCount"] = @([summary[@"changeCount"] unsignedIntegerValue] + 1);
    }
    NSArray<NSString *> *paths = [byPath.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSString *path in paths) [result addObject:[byPath[path] copy]];
    return result;
}

static NSString *PTInspectableText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if (!value || value == NSNull.null) return @"";
    if ([NSJSONSerialization isValidJSONObject:value]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:value
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (text.length) return text;
    }
    return [value description] ?: @"";
}

NSDictionary *PTEventFromAssistantBlock(
    NSDictionary *block,
    NSString *messageKey,
    NSString *timestamp,
    NSString *model
) {
    NSString *type = [block[@"type"] isKindOfClass:NSString.class] ? block[@"type"] : @"";
    NSDictionary *base = @{
        @"messageKey": messageKey ?: @"",
        @"timestamp": timestamp ?: @"",
        @"model": model ?: @"Claude",
        @"role": @"tool"
    };
    if ([type isEqual:@"thinking"]) {
        NSString *text = [block[@"thinking"] isKindOfClass:NSString.class]
            ? block[@"thinking"]
            : ([block[@"text"] isKindOfClass:NSString.class] ? block[@"text"] : @"");
        if (!text.length) return nil;
        NSMutableDictionary *event = [base mutableCopy];
        event[@"kind"] = @"thinking";
        event[@"text"] = text;
        event[@"role"] = @"assistant";
        return event;
    }
    if (![type isEqual:@"tool_use"]) return nil;

    NSString *toolName = [block[@"name"] isKindOfClass:NSString.class] ? block[@"name"] : @"工具调用";
    NSDictionary *input = [block[@"input"] isKindOfClass:NSDictionary.class] ? block[@"input"] : @{};
    NSMutableDictionary *event = [base mutableCopy];
    event[@"toolName"] = toolName;
    if ([toolName isEqual:@"Edit"] || [toolName isEqual:@"Write"]) {
        NSString *filePath = [input[@"file_path"] isKindOfClass:NSString.class] ? input[@"file_path"] : @"";
        NSString *oldText = [toolName isEqual:@"Edit"] && [input[@"old_string"] isKindOfClass:NSString.class]
            ? input[@"old_string"] : @"";
        NSString *newText = [toolName isEqual:@"Edit"] && [input[@"new_string"] isKindOfClass:NSString.class]
            ? input[@"new_string"]
            : ([input[@"content"] isKindOfClass:NSString.class] ? input[@"content"] : @"");
        if (filePath.length && [filePath hasPrefix:@"/"]) {
            event[@"kind"] = @"diff";
            event[@"filePath"] = filePath;
            event[@"oldText"] = oldText;
            event[@"newText"] = newText;
            event[@"startLine"] = [toolName isEqual:@"Write"] ? @1 : @0;
            return event;
        }
    }
    if ([toolName isEqual:@"AskUserQuestion"]) {
        NSArray *questions = [input[@"questions"] isKindOfClass:NSArray.class] ? input[@"questions"] : @[];
        NSString *toolUseId = [block[@"id"] isKindOfClass:NSString.class] ? block[@"id"] : @"";
        if (questions.count > 0 && toolUseId.length > 0) {
            event[@"kind"] = @"question";
            event[@"toolUseId"] = toolUseId;
            event[@"questions"] = questions;
            event[@"answered"] = @NO;
            event[@"answerText"] = @"";
            return event;
        }
    }
    event[@"kind"] = @"tool";
    event[@"text"] = PTInspectableText(input);
    return event;
}

// transcript 里的答案落在 toolUseResult.answers（question 文本 -> 答案文本的字典），
// 比 tool_result.content 里那段"The user answered..."的提示语干净，拼成多行展示文本。
NSString *PTFormattedQuestionAnswers(NSDictionary *answers) {
    if (![answers isKindOfClass:NSDictionary.class] || answers.count == 0) return @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:answers.count];
    [answers enumerateKeysAndObjectsUsingBlock:^(id question, id answer, BOOL *_Nonnull stop) {
        (void)stop;
        if (![question isKindOfClass:NSString.class] || ![answer isKindOfClass:NSString.class]) return;
        [lines addObject:[NSString stringWithFormat:@"%@：%@", question, answer]];
    }];
    return [lines componentsJoinedByString:@"\n"];
}

NSDictionary *PTEventFromToolResultBlock(
    NSDictionary *block,
    NSString *messageKey,
    NSString *timestamp
) {
    if (![block[@"type"] isEqual:@"tool_result"]) return nil;
    BOOL isError = [block[@"is_error"] boolValue];
    return @{
        @"messageKey": messageKey ?: @"",
        @"kind": isError ? @"error" : @"tool",
        @"toolName": isError ? @"工具执行失败" : @"工具结果",
        @"text": PTInspectableText(block[@"content"]),
        @"timestamp": timestamp ?: @"",
        @"role": @"tool"
    };
}
