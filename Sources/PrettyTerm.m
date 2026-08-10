#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Security/Security.h>
#import <signal.h>
#import "PTAgentState.h"
#import "PTGitReview.h"
#import "PTLocalization.h"
#import "PTUsageMetrics.h"

static NSString *PTRunTool(NSString *path, NSArray<NSString *> *arguments);

static NSData *PTClaudeCredentialData(NSError **error) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"Claude Code-credentials",
        (__bridge id)kSecAttrAccount: NSUserName(),
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        if (error) {
            NSString *description = CFBridgingRelease(SecCopyErrorMessageString(status, NULL))
                ?: [NSString stringWithFormat:@"Keychain 状态 %d", (int)status];
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                userInfo:@{NSLocalizedDescriptionKey: description}];
        }
        if (result) CFRelease(result);
        return nil;
    }
    id value = CFBridgingRelease(result);
    return [value isKindOfClass:NSData.class] ? value : nil;
}

static NSColor *PTColor(CGFloat red, CGFloat green, CGFloat blue) {
    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:1.0];
}

static NSColor *PTWarmDynamicColor(
    CGFloat lightRed, CGFloat lightGreen, CGFloat lightBlue,
    CGFloat darkRed, CGFloat darkGreen, CGFloat darkBlue
) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]];
        BOOL dark = [match isEqual:NSAppearanceNameDarkAqua];
        return PTColor(
            dark ? darkRed : lightRed,
            dark ? darkGreen : lightGreen,
            dark ? darkBlue : lightBlue
        );
    }];
}

static NSColor *PTWarmCanvasColor(void) {
    return PTWarmDynamicColor(0.953, 0.922, 0.867, 0.129, 0.098, 0.071);
}

static NSColor *PTWarmCardColor(void) {
    return PTWarmDynamicColor(0.988, 0.969, 0.925, 0.176, 0.129, 0.094);
}

static NSColor *PTWarmChipColor(void) {
    return PTWarmDynamicColor(0.973, 0.937, 0.878, 0.220, 0.153, 0.106);
}

static NSColor *PTWarmBorderColor(void) {
    return PTWarmDynamicColor(0.835, 0.733, 0.608, 0.376, 0.259, 0.173);
}

static NSColor *PTWarmAccentColor(void) {
    return PTWarmDynamicColor(0.639, 0.278, 0.090, 0.910, 0.537, 0.286);
}

typedef NS_ENUM(NSInteger, PTAppearanceSurfaceStyle) {
    PTAppearanceSurfaceStyleCanvas,
    PTAppearanceSurfaceStyleCard,
    PTAppearanceSurfaceStyleChip
};

@interface PTAppearanceSurfaceView : NSView
@property(nonatomic) PTAppearanceSurfaceStyle surfaceStyle;
@end

// Finder 被拉到前台后，PrettyTerm 会变成非活动窗口。普通 recessed button 的
// 第一次鼠标按下只负责激活窗口，老师看到的就是“点不动”。这个按钮明确允许
// click-through，让同一次点击既激活窗口也执行定位动作。
@interface PTFirstMouseButton : NSButton
@end

@implementation PTFirstMouseButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}
@end

@implementation PTAppearanceSurfaceView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) self.wantsLayer = YES;
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *background = PTWarmCanvasColor();
        NSColor *border = NSColor.clearColor;
        if (self.surfaceStyle == PTAppearanceSurfaceStyleCard) {
            background = PTWarmCardColor();
            border = PTWarmBorderColor();
        } else if (self.surfaceStyle == PTAppearanceSurfaceStyleChip) {
            background = PTWarmChipColor();
            border = PTWarmBorderColor();
        }
        self.layer.backgroundColor = background.CGColor;
        self.layer.borderColor = border.CGColor;
    }];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}

@end

static NSString *PTShortText(NSString *value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class]) return @"";
    // firstPrompt 有时是几十 KB 的粘贴内容；先粗截到一个安全上限，
    // 避免下面的折叠双空格 while 循环对超长字符串做 O(n^2) 的重复 replace。
    NSString *value2 = value;
    if (value2.length > 400) {
        NSRange safeRange = [value2 rangeOfComposedCharacterSequenceAtIndex:400];
        value2 = [value2 substringToIndex:NSMaxRange(safeRange)];
    }
    NSString *trimmed = [value2 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    trimmed = [trimmed stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    while ([trimmed containsString:@"  "]) {
        trimmed = [trimmed stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    if (trimmed.length <= limit) return trimmed;
    // substringToIndex: 按 UTF-16 code unit 切，会劈开 emoji 的代理对变乱码；
    // 用 rangeOfComposedCharacterSequenceAtIndex 对齐到完整字符边界。
    NSRange lastCharRange = [trimmed rangeOfComposedCharacterSequenceAtIndex:limit - 1];
    return [[trimmed substringToIndex:NSMaxRange(lastCharRange)] stringByAppendingString:@"…"];
}

static NSString *PTCompactTokenCount(NSUInteger tokens) {
    if (tokens >= 999500) return [NSString stringWithFormat:@"%.1fM", tokens / 1000000.0];
    if (tokens >= 1000) return [NSString stringWithFormat:@"%.0fK", tokens / 1000.0];
    return [NSString stringWithFormat:@"%lu", (unsigned long)tokens];
}

static NSString *PTMarkdownQuote(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length == 0 || text.length > 20000) return nil;
    NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    if ([[normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] == 0) {
        return nil;
    }
    normalized = [normalized stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *quoted = [NSMutableArray array];
    for (NSString *line in [normalized componentsSeparatedByString:@"\n"]) {
        [quoted addObject:[@"> " stringByAppendingString:line]];
    }
    // 末尾不加空的 >，直接用换行符结束
    return [[NSString stringWithFormat:@"> Attached context:\n%@\n\n",
        [quoted componentsJoinedByString:@"\n"]] copy];
}

static NSString *PTTextFromMessageContent(id content) {
    if ([content isKindOfClass:NSString.class]) return content;
    if (![content isKindOfClass:NSArray.class]) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id block in (NSArray *)content) {
        if (![block isKindOfClass:NSDictionary.class]) continue;
        if ([block[@"type"] isEqual:@"text"] && [block[@"text"] isKindOfClass:NSString.class]) {
            [parts addObject:block[@"text"]];
        }
    }
    return [parts componentsJoinedByString:@"\n"];
}

@interface PTSessionInfo : NSObject
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *cwd;
@property(nonatomic, copy) NSString *filePath;
@property(nonatomic, copy) NSString *model;
@property(nonatomic, strong) NSDate *modifiedAt;
@property(nonatomic, strong) NSArray<NSString *> *accessedDirectories;
@property(nonatomic, strong) NSArray<NSDictionary *> *assistantMessages;
@property(nonatomic, strong) NSArray<NSDictionary *> *changedFiles;
@property(nonatomic, strong) NSArray<NSDictionary *> *tasks;
@property(nonatomic) NSUInteger contextUsed;
@property(nonatomic) NSUInteger contextWindow;
@property(nonatomic) double apiEquivalentCostUSD;
@property(nonatomic) BOOL apiCostAvailable;
@property(nonatomic, copy) NSString *parseCustomTitle;
@property(nonatomic, copy) NSString *parseGeneratedTitle;
@property(nonatomic, copy) NSString *parseLastPrompt;
@property(nonatomic, copy) NSString *parseFirstPrompt;
@property(nonatomic, strong) NSSet<NSString *> *parseMessageKeys;
@property(nonatomic, strong) NSSet<NSString *> *parseUsageMessageKeys;
@end

@implementation PTSessionInfo
@end

static NSArray<NSDictionary *> *PTLoadTasksForSession(NSString *sessionID) {
    if (!sessionID.length) return @[];
    NSString *tasksDir = [NSHomeDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@".claude/tasks/%@", sessionID]];
    NSArray<NSString *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:tasksDir error:nil];
    if (!files) return @[];
    NSMutableArray<NSDictionary *> *tasks = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file.pathExtension isEqual:@"json"] || [file hasPrefix:@"."]) continue;
        NSString *path = [tasksDir stringByAppendingPathComponent:file];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        NSDictionary *task = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([task isKindOfClass:NSDictionary.class]) [tasks addObject:task];
    }
    [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger idA = [a[@"id"] integerValue];
        NSInteger idB = [b[@"id"] integerValue];
        return idA < idB ? NSOrderedAscending : (idA > idB ? NSOrderedDescending : NSOrderedSame);
    }];
    return tasks;
}

static PTSessionInfo *PTParseSessionData(
    NSData *data,
    NSString *filePath,
    NSDate *modifiedAt,
    PTSessionInfo *baseSession
) {
    if (!data) return nil;
    // Claude 还在往这个文件追加写的时候，文件末尾可能截在一个多字节 UTF-8
    // 字符的中间，导致整段 initWithData:encoding: 直接返回 nil，
    // 让这个正在活跃的会话从侧栏"消失"一下又"回来"，一直闪烁。
    // 按行切开后逐行解码，坏掉的只是最后半行，不会拖垮整个 session。
    NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!source) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        NSUInteger lineStart = 0;
        const char *bytes = data.bytes;
        NSUInteger length = data.length;
        for (NSUInteger index = 0; index < length; index++) {
            if (bytes[index] != '\n') continue;
            NSData *lineData = [data subdataWithRange:NSMakeRange(lineStart, index - lineStart)];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line) [lines addObject:line];
            lineStart = index + 1;
        }
        if (lines.count == 0) return nil;
        source = [lines componentsJoinedByString:@"\n"];
    }

    PTSessionInfo *session = [[PTSessionInfo alloc] init];
    session.sessionID = baseSession.sessionID.length
        ? baseSession.sessionID : filePath.lastPathComponent.stringByDeletingPathExtension;
    session.filePath = filePath;
    session.modifiedAt = modifiedAt;
    session.cwd = baseSession.cwd ?: @"";
    session.model = baseSession.model ?: @"";
    session.contextUsed = baseSession.contextUsed;
    session.contextWindow = baseSession ? baseSession.contextWindow : 200000;
    session.apiEquivalentCostUSD = baseSession.apiEquivalentCostUSD;
    session.apiCostAvailable = baseSession.apiCostAvailable;

    NSString *customTitle = baseSession.parseCustomTitle ?: @"";
    NSString *generatedTitle = baseSession.parseGeneratedTitle ?: @"";
    NSString *lastPrompt = baseSession.parseLastPrompt ?: @"";
    NSString *firstPrompt = baseSession.parseFirstPrompt ?: @"";
    NSMutableArray<NSDictionary *> *messages = baseSession
        ? [baseSession.assistantMessages mutableCopy] : [NSMutableArray array];
    NSMutableSet<NSString *> *messageKeys = baseSession
        ? [baseSession.parseMessageKeys mutableCopy] : [NSMutableSet set];
    NSMutableSet<NSString *> *usageMessageKeys = baseSession
        ? [baseSession.parseUsageMessageKeys mutableCopy] : [NSMutableSet set];
    NSMutableOrderedSet<NSString *> *accessedDirectories = [NSMutableOrderedSet orderedSetWithArray:
        baseSession.accessedDirectories ?: @[]];

    for (NSString *line in [source componentsSeparatedByString:@"\n"]) {
        if (line.length < 2) continue;
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
        if (![object isKindOfClass:NSDictionary.class]) continue;

        NSString *type = object[@"type"];
        NSString *objectSessionID = object[@"sessionId"];
        if ([objectSessionID isKindOfClass:NSString.class] && objectSessionID.length > 0) {
            session.sessionID = objectSessionID;
        }
        // 只认第一次出现的 cwd（= Claude 进程真正启动时所在目录，跟 lsof 探测到的
        // OS 级 cwd 是同一个东西）。之前每行都覆盖，Bash 工具在会话中途 cd 到别的
        // 项目目录后，transcript 里记录的 cwd 会跟着漂移，但 Claude 主进程的 OS cwd
        // 从头到尾不会变——用最后一次覆盖的值去跟 lsof 比对，必然对不上。
        NSString *recordedCWD = [object[@"cwd"] isKindOfClass:NSString.class]
            ? [object[@"cwd"] stringByStandardizingPath] : @"";
        if (recordedCWD.length > 0 && [recordedCWD hasPrefix:@"/"]) {
            [accessedDirectories addObject:recordedCWD];
        }
        if (session.cwd.length == 0 && recordedCWD.length > 0) {
            session.cwd = recordedCWD;
        }

        if ([type isEqual:@"custom-title"] && [object[@"customTitle"] isKindOfClass:NSString.class]) {
            customTitle = object[@"customTitle"];
        } else if ([type isEqual:@"ai-title"]) {
            NSString *candidate = object[@"title"] ?: object[@"aiTitle"];
            if ([candidate isKindOfClass:NSString.class]) generatedTitle = candidate;
        } else if ([type isEqual:@"last-prompt"] && [object[@"lastPrompt"] isKindOfClass:NSString.class]) {
            lastPrompt = object[@"lastPrompt"];
        } else if ([type isEqual:@"user"]) {
            if ([object[@"isSidechain"] boolValue]) continue;
            NSDictionary *message = object[@"message"];
            if (![message isKindOfClass:NSDictionary.class]) continue; // 防止 message 不是字典时 message[@"content"] 直接崩掉
            id rawContent = message[@"content"];
            if ([rawContent isKindOfClass:NSArray.class]) {
                NSUInteger resultIndex = 0;
                for (NSDictionary *block in (NSArray *)rawContent) {
                    if (![block isKindOfClass:NSDictionary.class] ||
                        ![block[@"type"] isEqual:@"tool_result"]) {
                        resultIndex++;
                        continue;
                    }
                    NSString *uuid = object[@"uuid"] ?: message[@"id"] ?: NSUUID.UUID.UUIDString;
                    NSString *key = [NSString stringWithFormat:@"%@:result:%lu",
                        uuid, (unsigned long)resultIndex];
                    NSDictionary *event = PTEventFromToolResultBlock(
                        block, key, object[@"timestamp"] ?: @"");
                    if (event && ![messageKeys containsObject:key]) {
                        [messageKeys addObject:key];
                        [messages addObject:event];
                    }
                    resultIndex++;
                }
            }
            NSString *text = PTTextFromMessageContent(message[@"content"]);
            BOOL isMeta = [object[@"isMeta"] boolValue];
            if (firstPrompt.length == 0 && text.length > 0 && !isMeta) {
                firstPrompt = text;
            }
            // text 为空说明这条 user 记录其实是 tool_result（工具调用结果），不是老师真正打的字，跳过。
            if (text.length > 0 && !isMeta) {
                NSString *uuid = object[@"uuid"] ?: message[@"id"] ?: NSUUID.UUID.UUIDString;
                NSString *key = [NSString stringWithFormat:@"%@:user", uuid];
                if (![messageKeys containsObject:key]) {
                    [messageKeys addObject:key];
                    [messages addObject:@{
                        @"messageKey": key,
                        @"text": text,
                        @"timestamp": object[@"timestamp"] ?: @"",
                        @"role": @"user"
                    }];
                }
            }
        } else if ([type isEqual:@"assistant"]) {
            NSDictionary *message = object[@"message"];
            if (![message isKindOfClass:NSDictionary.class] || ![message[@"role"] isEqual:@"assistant"]) continue;
            NSString *model = message[@"model"];
            if ([model isEqual:@"<synthetic>"]) continue;
            NSDictionary *usage = message[@"usage"];
            NSString *usageKey = object[@"uuid"] ?: message[@"id"];
            if ([usage isKindOfClass:NSDictionary.class] && usageKey.length > 0 &&
                ![usageMessageKeys containsObject:usageKey]) {
                [usageMessageKeys addObject:usageKey];
                BOOL supported = NO;
                double cost = PTAPIEquivalentCostForUsage(model ?: @"", usage, NSDate.date, &supported);
                if (supported) {
                    session.apiEquivalentCostUSD += cost;
                    session.apiCostAvailable = YES;
                }
            }
            if ([object[@"isSidechain"] boolValue] || [object[@"isApiErrorMessage"] boolValue]) continue;
            if ([model isKindOfClass:NSString.class] && model.length > 0) {
                session.model = model;
                NSString *lowerModel = model.lowercaseString;
                if ([lowerModel containsString:@"sonnet-5"] ||
                    [lowerModel containsString:@"opus-5"] ||
                    [lowerModel containsString:@"fable-5"]) {
                    session.contextWindow = 1000000;
                } else {
                    session.contextWindow = 200000;
                }
            }
            if ([usage isKindOfClass:NSDictionary.class]) {
                session.contextUsed =
                    [usage[@"input_tokens"] unsignedIntegerValue] +
                    [usage[@"cache_creation_input_tokens"] unsignedIntegerValue] +
                    [usage[@"cache_read_input_tokens"] unsignedIntegerValue];
            }

            NSArray *content = message[@"content"];
            if (![content isKindOfClass:NSArray.class]) continue;
            NSUInteger blockIndex = 0;
            for (NSDictionary *block in content) {
                if (![block isKindOfClass:NSDictionary.class]) {
                    blockIndex++;
                    continue;
                }
                NSString *blockType = block[@"type"];
                NSString *uuid = object[@"uuid"] ?: message[@"id"] ?: NSUUID.UUID.UUIDString;
                NSString *key = [NSString stringWithFormat:@"%@:%lu", uuid, (unsigned long)blockIndex];
                if ([messageKeys containsObject:key]) {
                    blockIndex++;
                    continue;
                }

                if ([blockType isEqual:@"text"]) {
                    NSString *text = block[@"text"];
                    if (![text isKindOfClass:NSString.class] || text.length == 0) {
                        blockIndex++;
                        continue;
                    }
                    [messageKeys addObject:key];
                    [messages addObject:@{
                        @"messageKey": key,
                        @"text": text,
                        @"timestamp": object[@"timestamp"] ?: @"",
                        @"model": model ?: @"Claude",
                        @"role": @"assistant"
                    }];
                    blockIndex++;
                    continue;
                }

                NSDictionary *event = PTEventFromAssistantBlock(
                    block, key, object[@"timestamp"] ?: @"", model ?: @"Claude");
                if (event) {
                    [messageKeys addObject:key];
                    [messages addObject:event];
                }
                blockIndex++;
            }
        }
    }

    NSString *title = customTitle.length ? customTitle :
        (generatedTitle.length ? generatedTitle :
        (lastPrompt.length ? lastPrompt : firstPrompt));
    session.title = PTShortText(title.length ? title : @"未命名会话", 58);
    session.parseCustomTitle = customTitle;
    session.parseGeneratedTitle = generatedTitle;
    session.parseLastPrompt = lastPrompt;
    session.parseFirstPrompt = firstPrompt;
    session.parseMessageKeys = messageKeys;
    session.parseUsageMessageKeys = usageMessageKeys;
    session.accessedDirectories = accessedDirectories.array;
    session.assistantMessages = messages;
    session.changedFiles = PTAggregateChangedFiles(messages);
    session.tasks = PTLoadTasksForSession(session.sessionID);
    if (session.assistantMessages.count == 0 && firstPrompt.length == 0 && customTitle.length == 0) {
        return nil;
    }
    return session;
}

static NSUInteger PTCompleteJSONLLength(NSData *data) {
    if (data.length == 0) return 0;
    const uint8_t *bytes = data.bytes;
    NSUInteger lastNewline = NSNotFound;
    for (NSUInteger index = data.length; index > 0; index--) {
        if (bytes[index - 1] == '\n') {
            lastNewline = index;
            break;
        }
    }
    if (lastNewline == data.length) return data.length;
    NSUInteger tailStart = lastNewline == NSNotFound ? 0 : lastNewline;
    NSData *tail = [data subdataWithRange:NSMakeRange(tailStart, data.length - tailStart)];
    id object = tail.length
        ? [NSJSONSerialization JSONObjectWithData:tail options:0 error:nil] : nil;
    if ([object isKindOfClass:NSDictionary.class]) return data.length;
    return lastNewline == NSNotFound ? 0 : lastNewline;
}

static NSData *PTReadFileDataFromOffset(NSString *filePath, NSUInteger offset) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!handle) return nil;
    @try {
        [handle seekToFileOffset:offset];
        NSData *data = [handle readDataToEndOfFile];
        [handle closeFile];
        return data;
    } @catch (__unused NSException *exception) {
        [handle closeFile];
        return nil;
    }
}

static PTSessionInfo *PTParseSession(
    NSString *filePath,
    NSDate *modifiedAt,
    NSUInteger *parsedSize
) {
    NSData *data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    NSUInteger completeLength = PTCompleteJSONLLength(data);
    if (parsedSize) *parsedSize = completeLength;
    if (completeLength == 0) return nil;
    NSData *completeData = completeLength == data.length
        ? data : [data subdataWithRange:NSMakeRange(0, completeLength)];
    return PTParseSessionData(completeData, filePath, modifiedAt, nil);
}

static PTSessionInfo *PTParseSessionAppending(
    NSString *filePath,
    NSDate *modifiedAt,
    NSUInteger previousParsedSize,
    PTSessionInfo *baseSession,
    NSUInteger *parsedSize
) {
    NSData *newData = PTReadFileDataFromOffset(filePath, previousParsedSize);
    if (!newData) return nil;
    NSUInteger completeLength = PTCompleteJSONLLength(newData);
    if (parsedSize) *parsedSize = previousParsedSize + completeLength;
    if (completeLength == 0) {
        baseSession.modifiedAt = modifiedAt;
        return baseSession;
    }
    NSData *completeData = completeLength == newData.length
        ? newData : [newData subdataWithRange:NSMakeRange(0, completeLength)];
    return PTParseSessionData(completeData, filePath, modifiedAt, baseSession);
}

@interface PTSessionStore : NSObject
@property(nonatomic, copy) void (^sessionsChanged)(NSArray<PTSessionInfo *> *sessions);
@property(nonatomic, copy) void (^globalModelChanged)(NSString *model);
- (void)refresh;
- (void)refreshForcingPath:(NSString *)filePath
                completion:(void (^)(PTSessionInfo * _Nullable session))completion;
- (void)startWatchingGlobalSettings;
- (void)stopWatchingGlobalSettings;
@end

@implementation PTSessionStore {
    dispatch_queue_t _queue;
    NSMutableDictionary<NSString *, NSDictionary *> *_cache;
    PTRefreshGate *_refreshGate;
    dispatch_source_t _settingsWatcher;
    int _settingsFD;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.yuuka.prettyterm.session-reader", DISPATCH_QUEUE_SERIAL);
        _cache = [NSMutableDictionary dictionary];
        _refreshGate = [[PTRefreshGate alloc] init];
        _settingsFD = -1;
    }
    return self;
}

- (void)startWatchingGlobalSettings {
    NSString *settingsPath = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/settings.json"];
    int fd = open(settingsPath.UTF8String, O_EVTONLY);
    if (fd < 0) return;
    _settingsFD = fd;
    _settingsWatcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd,
        DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_RENAME,
        dispatch_get_main_queue());
    if (!_settingsWatcher) {
        close(fd);
        _settingsFD = -1;
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_settingsWatcher, ^{
        PTSessionStore *self = weakSelf;
        if (!self) return;
        NSData *data = [NSData dataWithContentsOfFile:settingsPath];
        if (!data) return;
        NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![settings isKindOfClass:NSDictionary.class]) return;
        NSString *model = [settings[@"model"] isKindOfClass:NSString.class] ? settings[@"model"] : @"";
        if (model.length && self.globalModelChanged) {
            self.globalModelChanged(model);
        }
    });
    dispatch_source_set_cancel_handler(_settingsWatcher, ^{
        if (self->_settingsFD >= 0) {
            close(self->_settingsFD);
            self->_settingsFD = -1;
        }
    });
    dispatch_resume(_settingsWatcher);
}

- (void)stopWatchingGlobalSettings {
    if (_settingsWatcher) {
        dispatch_source_cancel(_settingsWatcher);
        _settingsWatcher = nil;
    }
}

- (void)dealloc {
    [self stopWatchingGlobalSettings];
}

- (void)refresh {
    if (![_refreshGate beginRefresh]) return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        PTSessionStore *self = weakSelf;
        if (!self) return;

        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/projects"];
        NSDirectoryEnumerator<NSURL *> *enumerator = [NSFileManager.defaultManager
            enumeratorAtURL:[NSURL fileURLWithPath:root]
            includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLContentModificationDateKey, NSURLFileSizeKey]
            options:NSDirectoryEnumerationSkipsHiddenFiles
            errorHandler:nil];

        NSMutableArray<PTSessionInfo *> *sessions = [NSMutableArray array];
        NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
        for (NSURL *url in enumerator) {
            if (![url.pathExtension.lowercaseString isEqual:@"jsonl"]) continue;
            NSNumber *regular = nil;
            NSDate *modified = nil;
            NSNumber *size = nil;
            [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
            if (!regular.boolValue) continue;
            [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
            [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            [seenPaths addObject:url.path];

            NSDictionary *cached = self->_cache[url.path];
            PTSessionInfo *session = nil;
            NSUInteger parsedSize = 0;
            if (cached && [cached[@"modified"] isEqual:modified] && [cached[@"size"] isEqual:size]) {
                session = cached[@"session"];
            } else {
                NSUInteger previousParsedSize = [cached[@"parsedSize"] unsignedIntegerValue];
                BOOL canAppend = cached[@"session"] && size.unsignedIntegerValue > previousParsedSize;
                session = canAppend
                    ? PTParseSessionAppending(
                        url.path, modified ?: NSDate.distantPast, previousParsedSize,
                        cached[@"session"], &parsedSize)
                    : PTParseSession(url.path, modified ?: NSDate.distantPast, &parsedSize);
                if (session) {
                    self->_cache[url.path] = @{
                        @"modified": modified ?: NSDate.distantPast,
                        @"size": size ?: @0,
                        @"parsedSize": @(parsedSize),
                        @"session": session
                    };
                } else {
                    [self->_cache removeObjectForKey:url.path];
                }
            }
            if (session) [sessions addObject:session];
        }

        for (NSString *path in self->_cache.allKeys.copy) {
            if (![seenPaths containsObject:path]) [self->_cache removeObjectForKey:path];
        }
        [sessions sortUsingComparator:^NSComparisonResult(PTSessionInfo *a, PTSessionInfo *b) {
            return [b.modifiedAt compare:a.modifiedAt];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL needsAnotherPass = [self->_refreshGate finishRefreshNeedsAnotherPass];
            if (self.sessionsChanged) self.sessionsChanged(sessions);
            if (needsAnotherPass) [self refresh];
        });
    });
}

- (void)refreshForcingPath:(NSString *)filePath
                completion:(void (^)(PTSessionInfo * _Nullable session))completion {
    if (filePath.length == 0) {
        if (completion) completion(nil);
        return;
    }
    dispatch_async(_queue, ^{
        NSURL *url = [NSURL fileURLWithPath:filePath];
        NSNumber *regular = nil;
        NSDate *modified = nil;
        NSNumber *size = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        NSUInteger parsedSize = 0;
        PTSessionInfo *session = regular.boolValue
            ? PTParseSession(filePath, modified ?: NSDate.distantPast, &parsedSize)
            : nil;
        if (session) {
            self->_cache[filePath] = @{
                @"modified": modified ?: NSDate.distantPast,
                @"size": size ?: @0,
                @"parsedSize": @(parsedSize),
                @"session": session
            };
        } else {
            [self->_cache removeObjectForKey:filePath];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(session);
        });
    });
}
@end

@interface PTClaudeBridge : NSObject
@property(nonatomic, copy) void (^statusChanged)(NSString *status);
@property(nonatomic, copy) void (^outputObserved)(NSString *chunk);
@property(nonatomic, readonly) NSString *sessionID;
@property(nonatomic, readonly) BOOL running;
- (void)connectToSession:(PTSessionInfo *)session;
- (BOOL)sendMessage:(NSString *)message;
- (BOOL)sendMessage:(NSString *)message withImages:(NSArray<NSImage *> *)images;
- (BOOL)enableRemoteControl;
- (void)stop;
@end

static NSString *PTRunTool(NSString *path, NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    task.standardOutput = pipe;
    // stderr 丢给 /dev/null：如果还用 NSPipe 但没人读，lsof/ps 一吐 warning
    // 管道缓冲区（约 64KB）就会写满，readDataToEndOfFile 永久卡死。
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return @"";
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *PTRunGit(NSString *directory, NSArray<NSString *> *arguments, int *exitStatus) {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSMutableArray<NSString *> *allArguments = [NSMutableArray arrayWithObjects:@"-C", directory, nil];
    [allArguments addObjectsFromArray:arguments];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.arguments = allArguments;
    NSMutableDictionary<NSString *, NSString *> *environment =
        [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"GIT_TERMINAL_PROMPT"] = @"0";
    task.environment = environment;
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (exitStatus) *exitStatus = -1;
        return launchError.localizedDescription ?: PTL(@"无法启动 Git", @"Unable to launch Git");
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (exitStatus) *exitStatus = task.terminationStatus;
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    const NSUInteger limit = 600000;
    if (output.length > limit) {
        output = [[output substringToIndex:limit]
            stringByAppendingString:PTL(@"\n\n… Git diff 过大，已在 600,000 字符处截断。", @"\n\n… Git diff is too large and was truncated at 600,000 characters.")];
    }
    return output;
}

static NSDictionary<NSString *, NSString *> *PTGitReviewSnapshotForDirectory(NSString *directory) {
    BOOL isDirectory = NO;
    BOOL exists = directory.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory];
    if (!exists || !isDirectory) {
        return @{ @"directory": directory ?: @"", @"error": PTL(@"所选 Git 观察目录不存在。", @"The selected Git observation directory does not exist.") };
    }

    int rootStatus = 0;
    NSString *root = [PTRunGit(directory, @[@"rev-parse", @"--show-toplevel"], &rootStatus)
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (rootStatus != 0 || root.length == 0) {
        return @{
            @"directory": directory,
            @"error": PTL(@"这里不是 Git 仓库。切换目录只影响 PrettyTerm 的 Git 探测，不会改变 Claude Code；需要 Claude 访问该目录时，请在 Claude Code 执行 /add-dir。", @"This is not a Git repository. Changing this directory only affects PrettyTerm's Git probe and does not change Claude Code; run /add-dir in Claude Code when Claude needs access.")
        };
    }

    int branchCode = 0;
    NSString *branch = [PTRunGit(directory, @[@"branch", @"--show-current"], &branchCode)
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    int upstreamCode = 0;
    NSString *upstream = [PTRunGit(directory,
        @[@"rev-parse", @"--abbrev-ref", @"--symbolic-full-name", @"@{upstream}"], &upstreamCode)
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    int statusCode = 0;
    NSString *status = PTRunGit(directory,
        @[@"-c", @"core.quotepath=false", @"status", @"--short", @"--untracked-files=normal"],
        &statusCode);
    int diffCode = 0;
    NSString *diff = PTRunGit(directory,
        @[@"-c", @"core.quotepath=false", @"diff", @"--no-ext-diff", @"--no-color",
          @"--unified=3", @"HEAD", @"--", @"."], &diffCode);
    if (diffCode != 0) {
        diff = PTRunGit(directory,
            @[@"-c", @"core.quotepath=false", @"diff", @"--no-ext-diff", @"--no-color",
              @"--unified=3", @"--", @"."], &diffCode);
    }
    if (statusCode != 0 || diffCode != 0) {
        return @{
            @"directory": directory,
            @"root": root,
            @"error": [NSString stringWithFormat:PTL(@"Git 探测失败：%@%@", @"Git probe failed: %@%@"),
                status ?: @"", diff ?: @""]
        };
    }
    return @{
        @"directory": directory,
        @"root": root,
        @"branch": branchCode == 0 ? branch : @"HEAD",
        @"upstream": upstreamCode == 0 ? upstream : @"",
        @"status": status ?: @"",
        @"diff": diff ?: @""
    };
}

static NSString *PTAppleScriptString(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    // bracketed-paste 的 ESC 不能原样塞进 AppleScript 字面量，否则不同系统版本
    // 可能把控制字符当作脚本源码；显式拼成 ASCII character 27 更稳定。
    NSString *escape = [NSString stringWithFormat:@"%C", (unichar)0x1B];
    escaped = [escaped stringByReplacingOccurrencesOfString:escape
        withString:@"\" & (ASCII character 27) & \""];
    // 先处理连续换行，避免产生空字符串 ""
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\" & linefeed & linefeed & \""];
    // 再处理单个换行
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\" & linefeed & \""];
    return [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@""];
}

static NSArray<NSDictionary<NSString *, NSData *> *> *PTSnapshotPasteboard(NSPasteboard *pasteboard) {
    NSMutableArray<NSDictionary<NSString *, NSData *> *> *snapshot = [NSMutableArray array];
    for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
        NSMutableDictionary<NSString *, NSData *> *dataByType = [NSMutableDictionary dictionary];
        for (NSPasteboardType type in item.types) {
            NSData *data = [item dataForType:type];
            if (data) dataByType[type] = data;
        }
        if (dataByType.count) [snapshot addObject:dataByType];
    }
    return snapshot;
}

static void PTRestorePasteboard(
    NSPasteboard *pasteboard,
    NSArray<NSDictionary<NSString *, NSData *> *> *snapshot
) {
    [pasteboard clearContents];
    NSMutableArray<NSPasteboardItem *> *items = [NSMutableArray array];
    for (NSDictionary<NSString *, NSData *> *dataByType in snapshot) {
        NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
        for (NSString *type in dataByType) {
            [item setData:dataByType[type] forType:type];
        }
        if (item.types.count) [items addObject:item];
    }
    if (items.count) [pasteboard writeObjects:items];
}

static BOOL PTWriteImageToPasteboard(NSImage *image, NSPasteboard *pasteboard) {
    NSData *tiff = image.TIFFRepresentation;
    NSBitmapImageRep *representation = tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
    NSData *png = [representation representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png.length) return NO;
    [pasteboard clearContents];
    return [pasteboard setData:png forType:NSPasteboardTypePNG];
}

// NSPasteboard 的数据提供回调就是“目标应用已经实际请求这份数据”的确认信号。
// 它比固定 sleep 后恢复剪贴板可靠：Terminal 没读到就不会误报发送成功。
@interface PTPasteboardLease : NSObject <NSPasteboardItemDataProvider>
@property(atomic, readonly) BOOL served;
- (instancetype)initWithText:(NSString *)text;
@end

@implementation PTPasteboardLease {
    NSString *_text;
    BOOL _served;
}

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) _text = [text copy] ?: @"";
    return self;
}

- (BOOL)served {
    @synchronized (self) { return _served; }
}

- (void)pasteboard:(NSPasteboard *)pasteboard
              item:(NSPasteboardItem *)item
provideDataForType:(NSPasteboardType)type {
    (void)pasteboard;
    if (![type isEqual:NSPasteboardTypeString]) return;
    [item setString:_text forType:type];
    @synchronized (self) { _served = YES; }
}
@end

static BOOL PTRunLoopUntil(NSTimeInterval timeout, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        NSDate *nextPass = [NSDate dateWithTimeIntervalSinceNow:
            MIN(0.02, MAX(0.001, deadline.timeIntervalSinceNow))];
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:nextPass];
    }
    return condition();
}

static BOOL PTPostKeyToProcess(pid_t processID, CGKeyCode keyCode, CGEventFlags flags) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventRef down = CGEventCreateKeyboardEvent(source, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, keyCode, false);
    if (!source || !down || !up) {
        if (down) CFRelease(down);
        if (up) CFRelease(up);
        if (source) CFRelease(source);
        return NO;
    }
    if (down) CGEventSetFlags(down, flags);
    if (up) CGEventSetFlags(up, flags);
    if (down) CGEventPostToPid(processID, down);
    if (up) CGEventPostToPid(processID, up);
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    if (source) CFRelease(source);
    return YES;
}

@implementation PTClaudeBridge {
    NSString *_sessionID;
    NSString *_terminalTTY;
    pid_t _terminalPID;
    BOOL _running;
    NSUInteger _connectionGeneration;
    dispatch_queue_t _ioQueue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ioQueue = dispatch_queue_create("com.yuuka.prettyterm.bridge-io", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)sessionID { return _sessionID; }
- (BOOL)running { return _running; }

// 老师常常同时开好几个 Terminal 标签页跑不同的 Claude 对话，很多都是直接在主目录里
// 起的、cwd 一模一样——只看"最前面窗口的选中标签页"没法区分到底是哪一个，
// 严重的话甚至会在 cwd 恰好相同时悄悄接错会话都不报错。这里改成拿到全部标签页的 tty，
// 交给 connectToSession 按 cwd 精确匹配、遇到歧义就明确告诉老师，而不是瞎猜一个。
- (NSArray<NSString *> *)allTerminalTTYsWithError:(NSString **)errorMessage {
    NSString *source =
        @"tell application id \"com.apple.Terminal\"\n"
         "set ttyList to {}\n"
         "repeat with theWindow in windows\n"
         "repeat with theTab in tabs of theWindow\n"
         "set end of ttyList to (tty of theTab)\n"
         "end repeat\n"
         "end repeat\n"
         "return ttyList\n"
         "end tell";
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result =
        [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (!result) {
        if (errorMessage) {
            NSNumber *number = error[NSAppleScriptErrorNumber];
            *errorMessage = number.integerValue == -1743
                ? @"请在系统设置中允许 PrettyTerm 控制 Terminal"
                : [NSString stringWithFormat:@"无法读取 Terminal：%@",
                    error[NSAppleScriptErrorMessage] ?: @"未知错误"];
        }
        return @[];
    }
    NSMutableArray<NSString *> *ttys = [NSMutableArray array];
    for (NSInteger index = 1; index <= result.numberOfItems; index++) {
        NSString *tty = [result descriptorAtIndex:index].stringValue;
        if (tty.length) [ttys addObject:tty];
    }
    return ttys;
}

- (pid_t)claudePIDForTTY:(NSString *)tty {
    NSString *shortTTY = tty.lastPathComponent;
    // comm= 会被截断到 16 字符、且可能含空格，靠它按空白分列很脆。
    // 只留 pid/tty 两个不含空格的字段，剩下全部当 args 整体处理。
    NSString *output = PTRunTool(@"/bin/ps", @[@"-Ao", @"pid=,tty=,args="]);
    static NSRegularExpression *claudePattern;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        claudePattern = [NSRegularExpression regularExpressionWithPattern:@"(^|/)claude(\\s|$)"
                                                                   options:NSRegularExpressionCaseInsensitive
                                                                     error:nil];
    });
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmedLine.length == 0) continue;
        NSRange firstSpace = [trimmedLine rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet];
        if (firstSpace.location == NSNotFound) continue;
        NSString *pidToken = [trimmedLine substringToIndex:firstSpace.location];
        NSString *rest = [[trimmedLine substringFromIndex:firstSpace.location]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSRange secondSpace = [rest rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *ttyToken = secondSpace.location == NSNotFound ? rest : [rest substringToIndex:secondSpace.location];
        NSString *args = secondSpace.location == NSNotFound ? @"" :
            [[rest substringFromIndex:secondSpace.location]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![ttyToken isEqual:shortTTY] || args.length == 0) continue;
        if ([claudePattern firstMatchInString:args options:0 range:NSMakeRange(0, args.length)]) {
            return (pid_t)pidToken.intValue;
        }
    }
    return 0;
}

- (NSString *)cwdForPID:(pid_t)pid {
    if (pid <= 0) return @"";
    NSString *output = PTRunTool(@"/usr/sbin/lsof",
        @[@"-a", @"-p", [NSString stringWithFormat:@"%d", pid], @"-d", @"cwd", @"-Fn"]);
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"n"] && line.length > 1) return [line substringFromIndex:1];
    }
    return @"";
}

// Claude Code 2.1+ 会为每个仍在运行的交互会话写入
// ~/.claude/sessions/<pid>.json。这里面的 sessionId 才是 Terminal 进程与
// transcript 的可靠连接键；cwd 只能筛候选，因为多个会话完全可能从同一目录启动。
- (NSDictionary *)sessionMetadataForPID:(pid_t)pid {
    if (pid <= 0) return nil;
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@".claude/sessions/%d.json", pid]];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *metadata = object;
    if ([metadata[@"pid"] intValue] != pid) return nil;
    return metadata;
}

// 在同一段 AppleScript 执行内完成"确认 tab 里还跑着 claude"和"do script"，
// 把 Obj-C 侧 kill(pid,0) 探活 与 真正发送 之间的竞态窗口，收紧到一次 AppleEvent 执行内部，
// 避免 Claude 恰好退出的瞬间，消息被 shell 当命令执行。
- (BOOL)sendToTerminal:(NSString *)message {
    if (_terminalTTY.length == 0 || message.length == 0) return NO;
    NSString *source = PTTerminalAutomationScript(
        _terminalTTY, _terminalPID, message, PTTerminalAutomationActionWriteText);
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result =
        [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    NSString *outcome = result.stringValue;
    if ([outcome isEqual:@"unsafe"]) {
        _running = NO;
        if (self.statusChanged) {
            self.statusChanged(@"检测到该 Terminal 标签页里 Claude 已退出，已取消发送以防误执行命令");
        }
        return NO;
    }
    if (!result || ![outcome isEqual:@"ok"]) {
        _running = NO;
        if (self.statusChanged) {
            NSNumber *number = error[NSAppleScriptErrorNumber];
            self.statusChanged(number.integerValue == -1743
                ? @"请在系统设置中允许 PrettyTerm 控制 Terminal"
                : [NSString stringWithFormat:@"Terminal 写入失败（%@）：%@",
                    number ?: @0,
                    error[NSAppleScriptErrorMessage] ?: (outcome.length ? outcome : @"标签页不可用")]);
        }
        return NO;
    }
    return YES;
}

- (NSString *)boundTerminalContents {
    if (_terminalTTY.length == 0) return @"";
    NSString *source = [NSString stringWithFormat:
        @"tell application id \"com.apple.Terminal\"\n"
         "repeat with theWindow in windows\n"
         "repeat with theTab in tabs of theWindow\n"
         "if (tty of theTab) is \"%@\" then return (contents of theTab) as text\n"
         "end repeat\n"
         "end repeat\n"
         "return \"\"\n"
         "end tell",
         PTAppleScriptString(_terminalTTY)];
    NSAppleEventDescriptor *result =
        [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:nil];
    return result.stringValue ?: @"";
}

- (BOOL)sendReturnToTerminal {
    if (_terminalTTY.length == 0) return NO;
    // 空字符串会被 AppleEvent 桥接成 Null descriptor，Terminal 实际没有
    // 可写数据。显式传入 CR 后，Terminal 自身再附加一枚 CR；marker 已
    // 确认闭合，因此第一枚负责提交，第二枚落在空输入上并被 Claude 忽略。
    NSString *source = PTTerminalAutomationScript(
        _terminalTTY, _terminalPID, @"", PTTerminalAutomationActionSubmitReturn);
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result =
        [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    NSString *outcome = result.stringValue;
    NSLog(@"PrettyTerm multiline Return: outcome=%@ errorNumber=%@ error=%@",
        outcome ?: @"(nil)", error[NSAppleScriptErrorNumber] ?: @0,
        error[NSAppleScriptErrorMessage] ?: @"(none)");
    if ([outcome isEqual:@"ok"]) return YES;
    if ([outcome isEqual:@"unsafe"] || [outcome isEqual:@"missing"]) _running = NO;
    if (self.statusChanged) {
        self.statusChanged([NSString stringWithFormat:@"Terminal 回车提交失败（%@）：%@",
            error[NSAppleScriptErrorNumber] ?: @0,
            error[NSAppleScriptErrorMessage] ?: outcome ?: @"标签页不可用"]);
    }
    return NO;
}

- (BOOL)sendMultilineMessage:(NSString *)message {
    NSInteger markerBefore = PTLatestTerminalPasteMarker([self boundTerminalContents]);
    if (![self sendToTerminal:PTTerminalSubmissionPayload(message)]) return NO;

    // `do script` 附加的第一枚 CR 与 bracketed-paste 数据处于同一批次，Claude
    // 会吞掉它而只显示 [Pasted text #N]。等屏幕上出现新的编号，证明粘贴帧
    // 已被完整解析，再单独写入一次空 do-script；它附加的 CR 才会稳定提交。
    __block NSInteger markerAfter = markerBefore;
    BOOL pasteAcknowledged = PTRunLoopUntil(0.8, ^BOOL{
        markerAfter = PTLatestTerminalPasteMarker([self boundTerminalContents]);
        return markerAfter >= 0 && markerAfter != markerBefore;
    });
    NSLog(@"PrettyTerm multiline paste: markerBefore=%ld markerAfter=%ld acknowledged=%@",
        (long)markerBefore, (long)markerAfter, pasteAcknowledged ? @"YES" : @"NO");
    return [self sendReturnToTerminal];
}

// 以下是早期的辅助功能粘贴实验，生产发送路径不再调用。当前多行发送只使用
// Terminal AppleEvent，并以 Claude 的可见 paste marker 作为提交确认点。
- (BOOL)prepareBoundTerminalTabForKeyboardInput {
    if (_terminalTTY.length == 0) return NO;
    NSString *source = [NSString stringWithFormat:
        @"tell application id \"com.apple.Terminal\"\n"
         "repeat with theWindow in windows\n"
         "repeat with theTab in tabs of theWindow\n"
         "if (tty of theTab) is \"%@\" then\n"
         "set isSafe to false\n"
         "set processNames to processes of theTab\n"
         "repeat with p in processNames\n"
         "set processName to (contents of p) as text\n"
         "if processName is \"claude\" then set isSafe to true\n"
         "end repeat\n"
         "if isSafe is false then return \"unsafe\"\n"
         "set selected tab of theWindow to theTab\n"
         "set frontmost of theWindow to true\n"
         "return \"ok\"\n"
         "end if\n"
         "end repeat\n"
         "end repeat\n"
         "return \"missing\"\n"
         "end tell",
         PTAppleScriptString(_terminalTTY)];
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result =
        [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    NSString *outcome = result.stringValue;
    if ([outcome isEqual:@"ok"]) return YES;
    if ([outcome isEqual:@"unsafe"]) _running = NO;
    if (self.statusChanged) {
        NSNumber *number = error[NSAppleScriptErrorNumber];
        self.statusChanged(number.integerValue == -1743
            ? @"请在系统设置中允许 PrettyTerm 控制 Terminal"
            : [NSString stringWithFormat:@"Terminal 多行输入准备失败（%@）：%@",
                number ?: @0,
                error[NSAppleScriptErrorMessage] ?: (outcome.length ? outcome : @"标签页不可用")]);
    }
    return NO;
}

- (BOOL)pasteAndSubmitMultilineMessage:(NSString *)message {
    if (!_running || message.length == 0 || ![self prepareBoundTerminalTabForKeyboardInput]) {
        return NO;
    }
    NSArray<NSRunningApplication *> *terminalApps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Terminal"];
    pid_t terminalProcessID = terminalApps.firstObject.processIdentifier;
    if (terminalProcessID <= 0) {
        if (self.statusChanged) self.statusChanged(@"Terminal 进程不可用，已取消多行发送");
        return NO;
    }
    if (!AXIsProcessTrusted()) {
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{
            (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES
        });
        if (self.statusChanged) {
            self.statusChanged(@"请在系统设置的辅助功能中允许 PrettyTerm，然后重试多行发送");
        }
        return NO;
    }

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSArray<NSDictionary<NSString *, NSData *> *> *snapshot = PTSnapshotPasteboard(pasteboard);
    NSString *pasteText = PTNormalizedTerminalPasteText(message);
    PTPasteboardLease *lease = [[PTPasteboardLease alloc] initWithText:pasteText];
    NSPasteboardItem *leaseItem = [[NSPasteboardItem alloc] init];
    [leaseItem setDataProvider:lease forTypes:@[NSPasteboardTypeString]];
    [pasteboard clearContents];
    if (![pasteboard writeObjects:@[leaseItem]]) {
        PTRestorePasteboard(pasteboard, snapshot);
        if (self.statusChanged) self.statusChanged(@"无法准备多行消息剪贴板，内容未发送");
        return NO;
    }

    // Cmd-V 和 Return 都定向投递给 Terminal 进程。目标 tab 已按 TTY 精确选中；
    // 中间留出 Claude Code 收纳 bracketed paste 的时间，且全程只有一个 Return。
    BOOL pasteEventPosted = PTPostKeyToProcess(terminalProcessID, 9, kCGEventFlagMaskCommand);
    BOOL pasteConsumed = pasteEventPosted && PTRunLoopUntil(1.0, ^BOOL{
        return lease.served;
    });
    if (!pasteConsumed) {
        PTRestorePasteboard(pasteboard, snapshot);
        [NSApp activateIgnoringOtherApps:YES];
        if (self.statusChanged) {
            self.statusChanged(@"Terminal 未确认读取多行消息，已取消提交并保留输入");
        }
        return NO;
    }
    // 数据提供回调已经证明 Terminal 取走正文；再给 Claude Code 一个短暂窗口
    // 完成 bracketed-paste 收纳。这里不再承担“猜测是否已粘贴”的职责。
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    // 粘贴与提交之间 Claude 若刚好退出，Return 会落到 shell。重新做一遍
    // TTY + processNames 安全检查；失败就只恢复剪贴板，不发送提交键。
    BOOL stillSafe = _terminalPID > 0 && kill(_terminalPID, 0) == 0 &&
        [self prepareBoundTerminalTabForKeyboardInput];
    BOOL submitted = stillSafe && PTPostKeyToProcess(terminalProcessID, 36, 0);
    PTRestorePasteboard(pasteboard, snapshot);
    [NSApp activateIgnoringOtherApps:YES];
    if (!submitted && self.statusChanged && _running) {
        self.statusChanged(@"多行消息未能安全提交，内容已保留，请重试");
    }
    return submitted;
}

// connectToSession 内部要跑 AppleScript + ps + lsof，慢的时候能到几秒；
// 全部挪到后台队列执行，只有最终结果（含 ivar 赋值和 statusChanged 回调）回主线程。
- (void)connectToSession:(PTSessionInfo *)session {
    [self stop];
    NSUInteger requestGeneration = _connectionGeneration;
    if (session.sessionID.length == 0 || session.cwd.length == 0) {
        if (self.statusChanged) self.statusChanged(@"会话缺少目录信息");
        return;
    }
    // 注意：这里不提前发一次"正在同步…"的中间态 statusChanged —— AppDelegate 那边
    // 用 _connecting 标志位驱动按钮文案，若这里也广播中间状态，两边会互相覆盖打脸。
    // 只有下面几个分支的"最终结果"才应该触发 statusChanged。

    NSString *sessionID = session.sessionID;
    NSString *sessionCWD = session.cwd.stringByStandardizingPath;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_ioQueue, ^{
        PTClaudeBridge *self = weakSelf;
        if (!self) return;

        NSString *appleScriptError = nil;
        NSArray<NSString *> *allTTYs = [self allTerminalTTYsWithError:&appleScriptError];
        if (allTTYs.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestGeneration != self->_connectionGeneration) return;
                if (self.statusChanged) {
                    self.statusChanged(appleScriptError ?: @"Terminal 没有可接入的标签页");
                }
            });
            return;
        }

        // 逐个标签页找它上面跑着的 claude 进程和 cwd，只挑 cwd 跟所选会话精确匹配的。
        // cwd 只负责缩小范围，最终必须优先使用 Claude 自己记录的 sessionId 精确绑定。
        NSMutableArray<NSString *> *matchedTTYs = [NSMutableArray array];
        NSMutableArray<NSNumber *> *matchedPIDs = [NSMutableArray array];
        NSMutableArray<NSString *> *matchedSessionIDs = [NSMutableArray array];
        for (NSString *tty in allTTYs) {
            pid_t candidatePID = [self claudePIDForTTY:tty];
            if (candidatePID <= 0) continue;
            NSString *candidateCWD = [self cwdForPID:candidatePID].stringByStandardizingPath;
            if (candidateCWD.length && [candidateCWD isEqual:sessionCWD]) {
                [matchedTTYs addObject:tty];
                [matchedPIDs addObject:@(candidatePID)];
                NSDictionary *metadata = [self sessionMetadataForPID:candidatePID];
                NSString *liveSessionID = [metadata[@"sessionId"] isKindOfClass:NSString.class]
                    ? metadata[@"sessionId"] : @"";
                [matchedSessionIDs addObject:liveSessionID];
            }
        }

        if (matchedTTYs.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestGeneration != self->_connectionGeneration) return;
                if (self.statusChanged) {
                    self.statusChanged([NSString stringWithFormat:
                        @"没找到目录是 %@ 的 Claude 标签页，请确认对应的 Terminal 标签页还在运行",
                        sessionCWD.lastPathComponent]);
                }
            });
            return;
        }

        NSMutableArray<NSNumber *> *exactIndexes = [NSMutableArray array];
        BOOL hasLiveSessionMetadata = NO;
        for (NSUInteger index = 0; index < matchedSessionIDs.count; index++) {
            NSString *liveSessionID = matchedSessionIDs[index];
            if (liveSessionID.length) hasLiveSessionMetadata = YES;
            if ([liveSessionID isEqual:sessionID]) [exactIndexes addObject:@(index)];
        }

        if (exactIndexes.count == 0 && (hasLiveSessionMetadata || matchedTTYs.count > 1)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestGeneration != self->_connectionGeneration) return;
                if (self.statusChanged) {
                    self.statusChanged(hasLiveSessionMetadata
                        ? @"所选会话当前没有在 Terminal 运行；已拒绝绑定到同目录的其他会话"
                        : @"同目录下有多个 Claude 标签页，但当前版本无法读取会话标识；已拒绝猜测目标");
                }
            });
            return;
        }

        if (exactIndexes.count > 1) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestGeneration != self->_connectionGeneration) return;
                if (self.statusChanged) {
                    self.statusChanged(@"检测到多个 Terminal 标签页声明了同一会话，已拒绝发送以防串线");
                }
            });
            return;
        }

        NSUInteger selectedIndex = exactIndexes.count == 1
            ? exactIndexes.firstObject.unsignedIntegerValue : 0;
        NSString *tty = matchedTTYs[selectedIndex];
        pid_t pid = matchedPIDs[selectedIndex].intValue;
        NSString *ambiguityNote = @"";
        if (exactIndexes.count == 0) {
            ambiguityNote = @"（当前 Claude 未提供会话标识；仅因该目录只有一个候选才允许接入）";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (requestGeneration != self->_connectionGeneration) return;
            self->_terminalTTY = tty;
            self->_terminalPID = pid;
            self->_sessionID = sessionID;
            self->_running = YES;
            if (self.statusChanged) {
                self.statusChanged([NSString stringWithFormat:@"已同步 Terminal · %@ %@",
                    tty.lastPathComponent, ambiguityNote]);
            }
        });
    });
}

- (BOOL)sendMessage:(NSString *)message {
    if (!_running || message.length == 0) return NO;
    if (_terminalPID <= 0 || kill(_terminalPID, 0) != 0) {
        [self stop];
        if (self.statusChanged) self.statusChanged(@"Terminal 中的 Claude 已结束");
        return NO;
    }
    BOOL isMultiline =
        [message rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound;
    BOOL sent = isMultiline
        ? [self sendMultilineMessage:message]
        : [self sendToTerminal:PTNormalizedTerminalPasteText(message)];
    if (sent) {
        if (self.statusChanged) self.statusChanged(@"已写入 Terminal，等待 Claude 回复…");
        return YES;
    }
    return NO;
}

- (BOOL)pasteCurrentClipboardImageIntoTerminal {
    if (_terminalTTY.length == 0) return NO;
    NSString *source = PTTerminalAutomationScript(
        _terminalTTY, _terminalPID, @"", PTTerminalAutomationActionPasteImage);
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result =
        [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    NSString *outcome = result.stringValue;
    if ([outcome isEqual:@"ok"]) return YES;

    if ([outcome isEqual:@"unsafe"]) _running = NO;
    if (self.statusChanged) {
        NSNumber *number = error[NSAppleScriptErrorNumber];
        NSString *detail = error[NSAppleScriptErrorMessage] ?: outcome ?: @"未知错误";
        BOOL denied = number.integerValue == -1743;
        self.statusChanged(denied
            ? @"请在系统设置中允许 PrettyTerm 控制 Terminal"
            : [NSString stringWithFormat:@"Claude 图片附件写入失败（%@）：%@",
                number ?: @0, detail]);
    }
    return NO;
}

- (BOOL)sendMessage:(NSString *)message withImages:(NSArray<NSImage *> *)images {
    if (images.count == 0) return [self sendMessage:message];
    if (!_running || _terminalPID <= 0 || kill(_terminalPID, 0) != 0) {
        [self stop];
        if (self.statusChanged) self.statusChanged(@"Terminal 中的 Claude 已结束");
        return NO;
    }

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSArray<NSDictionary<NSString *, NSData *> *> *snapshot = PTSnapshotPasteboard(pasteboard);
    BOOL attached = YES;
    for (NSImage *image in images) {
        if (!image.isValid || !PTWriteImageToPasteboard(image, pasteboard) ||
            ![self pasteCurrentClipboardImageIntoTerminal]) {
            attached = NO;
            break;
        }
    }
    PTRestorePasteboard(pasteboard, snapshot);
    [NSApp activateIgnoringOtherApps:YES];
    if (!attached) return NO;
    return [self sendMessage:message];
}

- (BOOL)enableRemoteControl {
    // Claude.ai Remote Control 需要在 Claude.ai 侧完成授权；PrettyTerm 不应
    // 代替用户发起该流程。保留方法只是为了兼容现有调用点，生产构建中硬禁用。
    if (self.statusChanged) self.statusChanged(@"官方 Remote Control 已禁用");
    return NO;
}

- (void)stop {
    _connectionGeneration++;
    _sessionID = nil;
    _terminalTTY = nil;
    _terminalPID = 0;
    _running = NO;
}

- (void)dealloc {
    [self stop];
}
@end

@interface PTSessionCellView : NSTableCellView
@property(nonatomic, strong) NSView *activityDot;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
@property(nonatomic, strong) NSTextField *timeLabel;
- (void)configure:(PTSessionInfo *)session;
@end

@interface PTSessionRowView : NSTableRowView
@end

@implementation PTSessionRowView
- (void)drawSelectionInRect:(NSRect)dirtyRect {
    if (!self.selected) return;
    NSRect selectionRect = NSInsetRect(self.bounds, 5, 2);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:11 yRadius:11];
    [[NSColor colorWithSRGBRed:0.16 green:0.62 blue:0.66 alpha:0.14] setFill];
    [path fill];
    [[NSColor colorWithSRGBRed:0.16 green:0.62 blue:0.66 alpha:0.24] setStroke];
    path.lineWidth = 1;
    [path stroke];
}
@end

@implementation PTSessionCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.activityDot = [[NSView alloc] initWithFrame:NSZeroRect];
        self.activityDot.translatesAutoresizingMaskIntoConstraints = NO;
        self.activityDot.wantsLayer = YES;
        self.activityDot.layer.cornerRadius = 4.5;
        [self addSubview:self.activityDot];

        self.titleLabel = [NSTextField labelWithString:@""];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:self.titleLabel];

        self.detailLabel = [NSTextField labelWithString:@""];
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
        self.detailLabel.textColor = NSColor.secondaryLabelColor;
        self.detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:self.detailLabel];

        self.timeLabel = [NSTextField labelWithString:@""];
        self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.timeLabel.font = [NSFont monospacedDigitSystemFontOfSize:9.5 weight:NSFontWeightRegular];
        self.timeLabel.textColor = NSColor.tertiaryLabelColor;
        self.timeLabel.alignment = NSTextAlignmentRight;
        [self addSubview:self.timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.activityDot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [self.activityDot.topAnchor constraintEqualToAnchor:self.topAnchor constant:17],
            [self.activityDot.widthAnchor constraintEqualToConstant:9],
            [self.activityDot.heightAnchor constraintEqualToConstant:9],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.activityDot.trailingAnchor constant:9],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.timeLabel.leadingAnchor constant:-6],
            [self.timeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.timeLabel.widthAnchor constraintLessThanOrEqualToConstant:58],
            [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:5]
        ]];
    }
    return self;
}

- (void)configure:(PTSessionInfo *)session {
    self.titleLabel.stringValue = session.title ?: PTL(@"未命名会话", @"Untitled conversation");
    NSString *folder = session.cwd.lastPathComponent.length ? session.cwd.lastPathComponent : session.cwd;
    // folder 为 @"" 时不是 nil，?: 不会生效，得显式判断 length 才能落到"未知目录"
    self.detailLabel.stringValue = [NSString stringWithFormat:PTL(@"%@ · %lu 条消息", @"%@ · %lu messages"),
        folder.length ? folder : PTL(@"未知目录", @"Unknown directory"),
        (unsigned long)session.assistantMessages.count];
    NSTimeInterval age = -session.modifiedAt.timeIntervalSinceNow;
    BOOL active = age < 600;
    self.activityDot.layer.backgroundColor =
        (active ? PTColor(0.16, 0.76, 0.48) : PTColor(0.58, 0.61, 0.66)).CGColor;
    self.activityDot.layer.shadowColor = active ? PTColor(0.16, 0.76, 0.48).CGColor : nil;
    self.activityDot.layer.shadowOpacity = active ? 0.28 : 0;
    self.activityDot.layer.shadowRadius = active ? 4 : 0;
    self.activityDot.layer.shadowOffset = CGSizeZero;
    if (age < 60) self.timeLabel.stringValue = PTL(@"刚刚", @"now");
    else if (age < 3600) self.timeLabel.stringValue = [NSString stringWithFormat:PTL(@"%ld分", @"%ldm"), (long)(age / 60)];
    else if (age < 86400) self.timeLabel.stringValue = [NSString stringWithFormat:PTL(@"%ld时", @"%ldh"), (long)(age / 3600)];
    else self.timeLabel.stringValue = [NSString stringWithFormat:PTL(@"%ld天", @"%ldd"), (long)(age / 86400)];
}
@end

@interface PTComposerTextView : NSTextView
@property(nonatomic, copy) dispatch_block_t submitHandler;
@property(nonatomic, copy) BOOL (^imagePasteHandler)(NSPasteboard *pasteboard);
- (void)clearAfterSuccessfulSubmissionMatchingText:(NSString *)submittedText;
@end

@implementation PTComposerTextView
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    BOOL commandPaste =
        (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) ==
            NSEventModifierFlagCommand &&
        (event.keyCode == 9 ||
         [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"v"]);
    if (commandPaste) {
        [self paste:self];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    BOOL commandPaste =
        (event.modifierFlags & NSEventModifierFlagCommand) != 0 &&
        (event.keyCode == 9 ||
         [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"v"]);
    if (commandPaste) {
        [self paste:self];
        return;
    }
    PTComposerKeyAction action = PTComposerActionForKey(
        event.keyCode,
        (event.modifierFlags & NSEventModifierFlagCommand) != 0,
        (event.modifierFlags & NSEventModifierFlagShift) != 0,
        self.hasMarkedText
    );
    if (action == PTComposerKeyActionSubmit && self.submitHandler) {
        self.submitHandler();
        return;
    }
    if (action == PTComposerKeyActionInsertNewline) {
        [self insertNewline:nil];
        return;
    }
    [super keyDown:event];
}

- (void)paste:(id)sender {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    if (self.imagePasteHandler && self.imagePasteHandler(pasteboard)) return;
    [super paste:sender];
}

- (void)clearAfterSuccessfulSubmissionMatchingText:(NSString *)submittedText {
    // NSTextView 的 string setter 在 keyDown: 尚未退出时偶尔会被输入系统的同一轮
    // 编辑事务覆盖回来。走 shouldChange/textStorage/didChangeText 的正式编辑链，
    // 并只清除仍与已发送快照一致的内容，避免误删老师紧接着输入的新文字。
    if (![self.string isEqualToString:submittedText ?: @""]) return;
    NSRange wholeRange = NSMakeRange(0, self.string.length);
    if (![self shouldChangeTextInRange:wholeRange replacementString:@""]) return;
    [self.textStorage beginEditing];
    [self.textStorage replaceCharactersInRange:wholeRange withString:@""];
    [self.textStorage endEditing];
    [self setSelectedRange:NSMakeRange(0, 0)];
    [self didChangeText];
    [self setNeedsDisplay:YES];
}
@end

@interface PTAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate, NSMenuDelegate, NSTextFieldDelegate>
@end

@implementation PTAppDelegate {
    NSWindow *_window;
    PTSessionStore *_store;
    PTClaudeBridge *_bridge;
    NSArray<PTSessionInfo *> *_sessions;
    PTSessionInfo *_selectedSession;
    NSTableView *_sessionTable;
    WKWebView *_conversationView;
    NSTextField *_conversationTitle;
    NSTextField *_conversationDetail;
    NSTextField *_statusLabel;
    NSTextField *_contextLabel;
    NSTextField *_quotaLabel;
    NSPopUpButton *_languagePicker;
    NSProgressIndicator *_contextBar;
    NSPopUpButton *_modelPicker;
    PTComposerTextView *_composerTextView;
    NSTextField *_composerTargetLabel;
    NSButton *_imageButton;
    NSScrollView *_imagePreviewScroll;
    NSStackView *_imagePreviewStack;
    NSLayoutConstraint *_composerHeightConstraint;
    NSLayoutConstraint *_imagePreviewHeightConstraint;
    NSMutableArray<NSDictionary *> *_pendingImages;
    NSMutableSet<NSString *> *_temporaryImagePaths;
    NSButton *_connectButton;
    NSButton *_floatingButton;
    NSMenuItem *_floatingMenuItem;
    NSButton *_remoteButton;
    NSButton *_sendButton;
    NSButton *_refreshButton;
    NSTimer *_refreshTimer;
    NSTimer *_usageRefreshTimer;
    BOOL _usageFetchInFlight;
    BOOL _planUsageAvailable;
    double _fiveHourPercent;
    double _sevenDayPercent;
    NSDate *_fiveHourResetAt;
    NSDate *_sevenDayResetAt;
    NSDate *_planUsageFetchedAt;
    NSString *_planUsageError;
    BOOL _webReady;
    NSPanel *_floatingPanel;
    WKWebView *_floatingConversationView;
    PTComposerTextView *_floatingComposerTextView;
    NSTextField *_floatingComposerLabel;
    NSButton *_floatingImageButton;
    NSScrollView *_floatingImagePreviewScroll;
    NSStackView *_floatingImagePreviewStack;
    NSLayoutConstraint *_floatingComposerHeightConstraint;
    NSLayoutConstraint *_floatingImagePreviewHeightConstraint;
    NSMutableArray<NSDictionary *> *_floatingPendingImages;
    NSButton *_floatingSendButton;
    NSString *_floatingSessionID;
    BOOL _floatingWebReady;
    BOOL _floatingRenderInFlight;
    PTSessionInfo *_pendingFloatingSession;
    NSString *_floatingRenderedSessionID;
    NSDate *_floatingRenderedModifiedAt;
    NSUInteger _floatingRenderedMessageCount;
    NSUInteger _floatingRenderGeneration;
    NSString *_sessionListSignature;
    NSString *_manualRefreshSessionID;
    NSString *_renderedSessionID;
    NSUInteger _renderedMessageCount;
    NSDate *_renderedModifiedAt;
    BOOL _renderInFlight;
    BOOL _renderRetrying;
    PTSessionInfo *_pendingRenderSession;
    NSSplitView *_splitView;
    NSView *_inspectorView;
    NSLayoutConstraint *_sidebarWidthConstraint;
    NSLayoutConstraint *_inspectorWidthConstraint;
    BOOL _committingSplitWidths;
    NSStackView *_changedFilesStack;
    NSArray<NSDictionary *> *_renderedChangedFiles;
    NSDictionary<NSString *, PTFirstMouseButton *> *_changedFileButtonsByPath;
    NSTextField *_inspectorConnectionLabel;
    NSTextField *_inspectorContextLabel;
    NSTextField *_inspectorQuotaLabel;
    NSTextField *_inspectorCostLabel;
    NSPopUpButton *_gitDirectoryPicker;
    NSButton *_removeGitDirectoryButton;
    NSTextField *_gitDirectoryInput;
    NSTextField *_gitDirectoryHintLabel;
    NSButton *_gitDiffToggleButton;
    NSButton *_gitDiffRefreshButton;
    NSButton *_gitPublishButton;
    NSProgressIndicator *_gitDiffProgress;
    NSScrollView *_gitDiffScroll;
    NSTextView *_gitDiffTextView;
    NSMutableArray<NSString *> *_gitDirectoryPaths;
    NSMutableSet<NSString *> *_gitDirectoriesSuppressedUntilSessionChange;
    NSString *_gitObservedDirectory;
    BOOL _gitDiffExpanded;
    BOOL _gitReviewShowsTranscriptEdits;
    NSArray<NSDictionary *> *_transcriptEditReviewEvents;
    BOOL _gitDirectoryManuallySelected;
    CGFloat _inspectorWidthBeforeGitDiff;
    NSUInteger _gitDiffGeneration;
    NSUInteger _gitDiffAnimationGeneration;
    NSPopover *_gitActionPopover;
    NSTextField *_gitActionBranchLabel;
    NSTextField *_gitCommitMessageField;
    NSButton *_gitIncludeUnstagedButton;
    NSButton *_gitCommitButton;
    NSButton *_gitCommitAndPushButton;
    NSButton *_gitPushButton;
    NSTextField *_gitActionStatusLabel;
    NSProgressIndicator *_gitActionProgress;
    BOOL _gitActionInFlight;
    NSTextField *_bottomStatusLabel;
    NSButton *_inspectorToggleButton;
    NSStackView *_tasksStack;
    NSArray<NSDictionary *> *_renderedTasks;
    PTAgentState *_agentState;
    PTTranscriptWatcher *_transcriptWatcher;
    NSString *_watchedTranscriptPath;
    BOOL _connecting;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    _agentState = [[PTAgentState alloc] init];
    _transcriptWatcher = [[PTTranscriptWatcher alloc] init];
    _pendingImages = [NSMutableArray array];
    _floatingPendingImages = [NSMutableArray array];
    _temporaryImagePaths = [NSMutableSet set];
    _gitDirectoryPaths = [NSMutableArray array];
    [self buildMainMenu];
    [self buildWindow];
    [self connectStoreAndBridge];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_splitView setPosition:270 ofDividerAtIndex:0]; // 只是初始位置，之后老师可以自己拖
    [_splitView setPosition:920 ofDividerAtIndex:1];
    [_store refresh];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(refreshSessions:) userInfo:nil repeats:YES];
    [self refreshClaudeUsage:nil];
    _usageRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(refreshClaudeUsage:) userInfo:nil repeats:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    if (!_planUsageFetchedAt || [[NSDate date] timeIntervalSinceDate:_planUsageFetchedAt] > 30.0) {
        [self refreshClaudeUsage:nil];
    }
}

- (void)changeInterfaceLanguage:(NSPopUpButton *)sender {
    NSString *language = [sender.selectedItem.representedObject isKindOfClass:NSString.class]
        ? sender.selectedItem.representedObject : @"zh-Hans";
    NSString *stored = PTInterfaceLanguageCode();
    if ([language isEqualToString:stored]) return;

    [NSUserDefaults.standardUserDefaults setObject:language
        forKey:PTInterfaceLanguageDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    // Rebuild only PrettyTerm's presentation tree. The session store, Terminal bridge,
    // selected Claude session, pending attachments, and unsent draft remain untouched.
    NSString *draft = _composerTextView.string ?: @"";
    NSRect previousFrame = _window.frame;
    CGFloat sidebarWidth = _splitView.subviews.count >= 3
        ? NSWidth(_splitView.subviews[0].frame) : 270.0;
    CGFloat inspectorWidth = _splitView.subviews.count >= 3
        ? NSWidth(_splitView.subviews[2].frame) : 260.0;
    BOOL inspectorWasHidden = _inspectorView.hidden;
    NSWindow *previousWindow = _window;
    [_conversationView.configuration.userContentController
        removeScriptMessageHandlerForName:@"quoteSelection"];
    [_conversationView.configuration.userContentController
        removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
    if (_floatingConversationView) {
        [_floatingConversationView.configuration.userContentController
            removeScriptMessageHandlerForName:@"quoteSelection"];
        [_floatingConversationView.configuration.userContentController
            removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
    }
    [_floatingPanel orderOut:nil];
    _floatingPanel = nil;
    _floatingConversationView = nil;
    _floatingWebReady = NO;
    [previousWindow orderOut:nil];

    _webReady = NO;
    _renderInFlight = NO;
    _renderedSessionID = nil;
    _renderedModifiedAt = nil;
    _renderedMessageCount = 0;
    _gitDiffExpanded = NO;
    _gitReviewShowsTranscriptEdits = NO;
    _transcriptEditReviewEvents = nil;
    [self buildMainMenu];
    [self buildWindow];
    [_window setFrame:previousFrame display:NO];
    [_splitView setPosition:sidebarWidth ofDividerAtIndex:0];
    [_splitView setPosition:NSWidth(_splitView.bounds) - inspectorWidth
          ofDividerAtIndex:1];
    _inspectorView.hidden = inspectorWasHidden;
    _composerTextView.string = draft;
    [self updateImagePreviews];
    [_sessionTable reloadData];
    if (_selectedSession) {
        [self updateInspectorForSession:_selectedSession];
        [self updateContextAndModelForSession:_selectedSession];
    }
    [self refreshAgentStateAndControls];
    [self updateConnectButtonTitle];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

// 之前没建 mainMenu，输入框粘不了字（Cmd+V）、Cmd+Q 也退不出去。
// 补一个最小够用的 App 菜单 + Edit 菜单，标准 selector 会自动接到 NSTextField 的响应链上。
- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    NSString *appName = NSProcessInfo.processInfo.processName;
    [appMenu addItemWithTitle:[NSString stringWithFormat:PTL(@"关于 %@", @"About %@"), appName]
                       action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:PTL(@"隐藏 %@", @"Hide %@"), appName]
                       action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:PTL(@"隐藏其他", @"Hide Others")
                       action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:PTL(@"显示全部", @"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    _floatingMenuItem = [appMenu addItemWithTitle:PTL(@"悬浮当前对话", @"Float Current Conversation")
                       action:@selector(toggleFloatingConversation:) keyEquivalent:@"o"];
    _floatingMenuItem.target = self;
    _floatingMenuItem.enabled = NO;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:PTL(@"退出 %@", @"Quit %@"), appName]
                       action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:PTL(@"编辑", @"Edit")];
    [editMenu addItemWithTitle:PTL(@"撤销", @"Undo") action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:PTL(@"重做", @"Redo") action:@selector(redo:) keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:PTL(@"剪切", @"Cut") action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:PTL(@"拷贝", @"Copy") action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:PTL(@"粘贴", @"Paste") action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:PTL(@"全选", @"Select All") action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;

    NSApp.mainMenu = mainMenu;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_refreshTimer invalidate];
    [_usageRefreshTimer invalidate];
    [_conversationView.configuration.userContentController removeScriptMessageHandlerForName:@"quoteSelection"];
    [_conversationView.configuration.userContentController removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
    [_floatingConversationView.configuration.userContentController removeScriptMessageHandlerForName:@"quoteSelection"];
    [_floatingConversationView.configuration.userContentController removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
    [_bridge stop];
    [_transcriptWatcher stopWatching];
    [_store stopWatchingGlobalSettings];
    for (NSString *path in _temporaryImagePaths.copy) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}

- (void)buildWindow {
    NSDictionary *bundleInfo = NSBundle.mainBundle.infoDictionary ?: @{};
    NSString *displayName = bundleInfo[@"CFBundleDisplayName"] ?: @"PrettyTerm Beta";
    NSString *shortVersion = bundleInfo[@"CFBundleShortVersionString"] ?: @"—";
    NSString *buildVersion = bundleInfo[@"CFBundleVersion"] ?: @"—";
    NSString *visibleAppVersion = [NSString stringWithFormat:@"%@ · v%@ (%@)",
        displayName, shortVersion, buildVersion];
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 760)
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = visibleAppVersion;
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.backgroundColor = PTWarmCanvasColor();
    _window.minSize = NSMakeSize(900, 600);
    [_window center];

    NSView *root = _window.contentView;
    root.wantsLayer = YES;
    root.layer.backgroundColor = NSColor.clearColor.CGColor;

    PTAppearanceSurfaceView *topBar = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    topBar.surfaceStyle = PTAppearanceSurfaceStyleChip;
    [root addSubview:topBar];

    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.image = NSApp.applicationIconImage;
    logo.imageScaling = NSImageScaleProportionallyUpOrDown;
    [topBar addSubview:logo];

    NSTextField *title = [self label:visibleAppVersion size:17 weight:NSFontWeightBold color:NSColor.labelColor];
    title.toolTip = [NSString stringWithFormat:PTL(@"当前运行版本：v%@，构建 %@", @"Running version: v%@, build %@"),
        shortVersion, buildVersion];
    [topBar addSubview:title];
    NSTextField *subtitle = [self label:PTL(@"Claude Code 终端伴生 Agent", @"Claude Code terminal companion") size:10.5 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [topBar addSubview:subtitle];

    _statusLabel = [self label:PTL(@"正在读取本地会话…", @"Reading local conversations…") size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    _statusLabel.alignment = NSTextAlignmentRight;
    [topBar addSubview:_statusLabel];

    _contextLabel = [self label:@"ctx —" size:10 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    _contextLabel.alignment = NSTextAlignmentRight;
    [topBar addSubview:_contextLabel];

    _quotaLabel = [self label:@"5h — · 7d —" size:10 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    _quotaLabel.alignment = NSTextAlignmentRight;
    _quotaLabel.toolTip = PTL(@"正在读取 Claude 套餐额度", @"Reading Claude plan limits");
    [topBar addSubview:_quotaLabel];

    _languagePicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _languagePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [_languagePicker addItemWithTitle:@"中文"];
    _languagePicker.lastItem.representedObject = @"zh-Hans";
    [_languagePicker addItemWithTitle:@"English"];
    _languagePicker.lastItem.representedObject = @"en";
    [_languagePicker selectItemAtIndex:PTInterfaceLanguageIsEnglish() ? 1 : 0];
    _languagePicker.target = self;
    _languagePicker.action = @selector(changeInterfaceLanguage:);
    _languagePicker.toolTip = PTL(@"界面语言", @"Interface language");
    [topBar addSubview:_languagePicker];

    _contextBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _contextBar.translatesAutoresizingMaskIntoConstraints = NO;
    _contextBar.indeterminate = NO;
    _contextBar.minValue = 0;
    _contextBar.maxValue = 1;
    _contextBar.doubleValue = 0;
    _contextBar.style = NSProgressIndicatorStyleBar;
    _contextBar.controlSize = NSControlSizeSmall;
    [topBar addSubview:_contextBar];

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    split.translatesAutoresizingMaskIntoConstraints = NO;
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.delegate = self;
    [root addSubview:split];
    _splitView = split;

    NSView *sidebar = [self buildSidebar];
    NSView *conversation = [self buildConversation];
    NSView *inspector = [self buildInspector];
    [split addArrangedSubview:sidebar];
    [split addArrangedSubview:conversation];
    [split addArrangedSubview:inspector];
    // NSSplitView 必须直接管理三个 pane 的宽度。对 arrangedSubview 追加 widthAnchor
    // 会在每次鼠标拖动后把 frame 解回最小值，表现为分隔条完全拖不动。
    // 宽度范围改由 delegate 的拖动坐标约束处理。两个边栏仍需要一个
    // 可更新的宽度锚点，否则 Auto Layout 会在 mouseDragged 后按 intrinsic
    // content size 把刚设置的 frame 弹回去。
    _sidebarWidthConstraint = [sidebar.widthAnchor constraintEqualToConstant:270.0];
    _sidebarWidthConstraint.priority = NSLayoutPriorityDefaultHigh;
    _sidebarWidthConstraint.active = YES;
    _inspectorWidthConstraint = [inspector.widthAnchor constraintEqualToConstant:260.0];
    _inspectorWidthConstraint.priority = NSLayoutPriorityDefaultHigh;
    _inspectorWidthConstraint.active = YES;
    [split setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
    [split setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:2];

    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:64],
        [split.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [split.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [split.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [split.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [logo.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:76],
        [logo.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor constant:9],
        [logo.widthAnchor constraintEqualToConstant:40],
        [logo.heightAnchor constraintEqualToConstant:40],
        [title.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:11],
        [title.topAnchor constraintEqualToAnchor:logo.topAnchor constant:1],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-16],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_statusLabel.widthAnchor constraintLessThanOrEqualToConstant:260],
        [_contextLabel.trailingAnchor constraintEqualToAnchor:_statusLabel.leadingAnchor constant:-12],
        [_contextLabel.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_contextLabel.widthAnchor constraintEqualToConstant:96],
        [_contextBar.trailingAnchor constraintEqualToAnchor:_contextLabel.leadingAnchor constant:-8],
        [_contextBar.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_contextBar.widthAnchor constraintEqualToConstant:92],
        [_contextBar.heightAnchor constraintEqualToConstant:7],
        [_quotaLabel.trailingAnchor constraintEqualToAnchor:_contextBar.leadingAnchor constant:-10],
        [_quotaLabel.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_quotaLabel.widthAnchor constraintEqualToConstant:114],
        [_languagePicker.trailingAnchor constraintEqualToAnchor:_quotaLabel.leadingAnchor constant:-8],
        [_languagePicker.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_languagePicker.widthAnchor constraintEqualToConstant:84],
        [_languagePicker.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:20]
    ]];
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainSplitPosition:(CGFloat)proposedPosition
           ofSubviewAt:(NSInteger)dividerIndex {
    CGFloat thickness = splitView.dividerThickness;
    if (dividerIndex == 0) {
        return MIN(420.0, MAX(220.0, proposedPosition));
    }
    if (dividerIndex == 1 && splitView.subviews.count >= 3) {
        NSView *conversation = splitView.subviews[1];
        CGFloat minimum = MAX(NSMinX(conversation.frame) + 480.0,
            NSWidth(splitView.bounds) - 720.0 - thickness);
        CGFloat maximum = NSWidth(splitView.bounds) - 210.0 - thickness;
        return MIN(maximum, MAX(minimum, proposedPosition));
    }
    return proposedPosition;
}

- (NSRect)splitView:(NSSplitView *)splitView
       effectiveRect:(NSRect)proposedEffectiveRect
        forDrawnRect:(NSRect)drawnRect
    ofDividerAtIndex:(NSInteger)dividerIndex {
    (void)splitView;
    (void)drawnRect;
    (void)dividerIndex;
    // 细分隔条视觉上仍保持 1px，但左右各扩充命中范围，移动窗口后也容易抓住。
    return NSInsetRect(proposedEffectiveRect, -5.0, 0.0);
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    NSSplitView *splitView = notification.object;
    if (splitView != _splitView || splitView.subviews.count < 3 || _committingSplitWidths) return;
    _committingSplitWidths = YES;
    CGFloat sidebarWidth = NSWidth(splitView.subviews[0].frame);
    CGFloat inspectorWidth = NSWidth(splitView.subviews[2].frame);
    if (sidebarWidth > 0.0) {
        _sidebarWidthConstraint.constant = MIN(420.0, MAX(220.0, sidebarWidth));
    }
    if (inspectorWidth > 0.0 && !_inspectorView.hidden) {
        _inspectorWidthConstraint.constant = MIN(720.0, MAX(210.0, inspectorWidth));
    }
    _sidebarWidthConstraint.active = YES;
    _inspectorWidthConstraint.active = YES;
    _committingSplitWidths = NO;
}

- (void)splitViewWillResizeSubviews:(NSNotification *)notification {
    if (notification.object != _splitView || _committingSplitWidths) return;
    // 暂时释放旧宽度，允许 NSSplitView 在本次 mouseDragged 中真正改 frame；
    // didResize 随即把新 frame 持久化，下一轮布局不会再弹回。
    _sidebarWidthConstraint.active = NO;
    _inspectorWidthConstraint.active = NO;
}

- (NSView *)buildSidebar {
    PTAppearanceSurfaceView *sidebar = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.surfaceStyle = PTAppearanceSurfaceStyleChip;

    NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:header];
    NSTextField *heading = [self label:PTL(@"会话", @"Conversations") size:14 weight:NSFontWeightBold color:NSColor.labelColor];
    [header addSubview:heading];
    _refreshButton = [NSButton buttonWithTitle:@"↻" target:self action:@selector(refreshSessions:)];
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    _refreshButton.bezelStyle = NSBezelStyleInline;
    _refreshButton.font = [NSFont systemFontOfSize:17 weight:NSFontWeightMedium];
    _refreshButton.contentTintColor = PTWarmAccentColor();
    _refreshButton.toolTip = PTL(@"刷新本地会话", @"Refresh local conversations");
    [header addSubview:_refreshButton];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    _sessionTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _sessionTable.headerView = nil;
    _sessionTable.backgroundColor = NSColor.clearColor;
    _sessionTable.rowHeight = 66;
    _sessionTable.intercellSpacing = NSMakeSize(0, 2);
    _sessionTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _sessionTable.dataSource = self;
    _sessionTable.delegate = self;
    // 右键菜单的条目在 menuNeedsUpdate: 里按 clickedRow 现场重建，所以这里只挂一个空壳。
    // autoenablesItems 关掉，否则 AppKit 会忽略我们自己算出来的 enabled（文件已被删时要变灰）。
    NSMenu *sessionMenu = [[NSMenu alloc] init];
    sessionMenu.delegate = self;
    sessionMenu.autoenablesItems = NO;
    _sessionTable.menu = sessionMenu;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"session"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_sessionTable addTableColumn:column];
    scroll.documentView = _sessionTable;
    [sidebar addSubview:scroll];

    NSTextField *privacy = [self label:PTL(@"仅在本机读取 ~/.claude/projects", @"Reads ~/.claude/projects locally only") size:9.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    privacy.alignment = NSTextAlignmentCenter;
    [sidebar addSubview:privacy];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:48],
        [heading.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:14],
        [heading.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_refreshButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [_refreshButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [privacy.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:8],
        [privacy.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-8],
        [privacy.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-9],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:5],
        [scroll.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-5],
        [scroll.bottomAnchor constraintEqualToAnchor:privacy.topAnchor constant:-8]
    ]];
    return sidebar;
}

- (NSView *)buildInspector {
    NSVisualEffectView *inspector = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    inspector.translatesAutoresizingMaskIntoConstraints = NO;
    inspector.material = NSVisualEffectMaterialSidebar;
    inspector.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    inspector.state = NSVisualEffectStateActive;
    [inspector setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    _inspectorView = inspector;

    NSTextField *title = [self label:PTL(@"检查器", @"Inspector") size:13 weight:NSFontWeightBold color:NSColor.labelColor];
    [inspector addSubview:title];
    NSButton *collapse = [NSButton buttonWithTitle:PTL(@"收起 ›", @"Collapse ›") target:self action:@selector(toggleInspector:)];
    collapse.translatesAutoresizingMaskIntoConstraints = NO;
    collapse.bezelStyle = NSBezelStyleInline;
    collapse.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    [inspector addSubview:collapse];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    [inspector addSubview:scroll];

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(2, 10, 12, 10);
    scroll.documentView = stack;

    NSView* (^makeCard)(NSString *, NSTextField **) = ^NSView *(NSString *heading, NSTextField **valueOut) {
        PTAppearanceSurfaceView *card = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.surfaceStyle = PTAppearanceSurfaceStyleCard;
        card.layer.cornerRadius = 14;
        card.layer.borderWidth = 0.6;
        NSTextField *headingLabel = [self label:heading size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
        NSTextField *value = [self label:@"—" size:12 weight:NSFontWeightMedium color:NSColor.labelColor];
        value.lineBreakMode = NSLineBreakByWordWrapping;
        value.maximumNumberOfLines = 3;
        [card addSubview:headingLabel];
        [card addSubview:value];
        [NSLayoutConstraint activateConstraints:@[
            [headingLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:11],
            [headingLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
            [headingLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
            [value.topAnchor constraintEqualToAnchor:headingLabel.bottomAnchor constant:6],
            [value.leadingAnchor constraintEqualToAnchor:headingLabel.leadingAnchor],
            [value.trailingAnchor constraintEqualToAnchor:headingLabel.trailingAnchor],
            [value.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]
        ]];
        if (valueOut) *valueOut = value;
        return card;
    };

    NSTextField *connectionValue = nil;
    NSTextField *contextValue = nil;
    NSTextField *quotaValue = nil;
    NSTextField *costValue = nil;
    NSView *connectionCard = makeCard(PTL(@"TERMINAL 连接", @"TERMINAL CONNECTION"), &connectionValue);
    NSView *contextCard = makeCard(PTL(@"上下文使用", @"CONTEXT USAGE"), &contextValue);
    NSView *quotaCard = makeCard(PTL(@"CLAUDE 套餐额度", @"CLAUDE PLAN LIMITS"), &quotaValue);
    NSView *costCard = makeCard(PTL(@"本会话 API 等价成本", @"API-EQUIVALENT SESSION COST"), &costValue);
    _inspectorConnectionLabel = connectionValue;
    _inspectorContextLabel = contextValue;
    _inspectorQuotaLabel = quotaValue;
    _inspectorCostLabel = costValue;
    [stack addArrangedSubview:connectionCard];
    [stack addArrangedSubview:contextCard];
    [stack addArrangedSubview:quotaCard];
    [stack addArrangedSubview:costCard];
    [connectionCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [contextCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [quotaCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [costCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;

    PTAppearanceSurfaceView *gitCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    gitCard.translatesAutoresizingMaskIntoConstraints = NO;
    gitCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    gitCard.layer.cornerRadius = 14;
    gitCard.layer.borderWidth = 0.6;
    NSStackView *gitStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    gitStack.translatesAutoresizingMaskIntoConstraints = NO;
    gitStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    gitStack.alignment = NSLayoutAttributeLeading;
    gitStack.spacing = 7;
    [gitStack setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    [gitCard addSubview:gitStack];

    NSTextField *gitTitle = [self label:PTL(@"GIT 观察目录", @"GIT OBSERVED DIRECTORY") size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [gitStack addArrangedSubview:gitTitle];
    _gitDirectoryPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _gitDirectoryPicker.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDirectoryPicker.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _gitDirectoryPicker.target = self;
    _gitDirectoryPicker.action = @selector(gitDirectorySelectionChanged:);
    [_gitDirectoryPicker addItemWithTitle:PTL(@"等待会话目录…", @"Waiting for conversation directory…")];
    _gitDirectoryPicker.enabled = NO;
    NSStackView *directoryRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    directoryRow.translatesAutoresizingMaskIntoConstraints = NO;
    directoryRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    directoryRow.alignment = NSLayoutAttributeCenterY;
    directoryRow.spacing = 6;
    _removeGitDirectoryButton = [NSButton buttonWithTitle:PTL(@"删除", @"Remove")
        target:self action:@selector(removeSelectedGitDirectory:)];
    _removeGitDirectoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    _removeGitDirectoryButton.bezelStyle = NSBezelStyleRounded;
    _removeGitDirectoryButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _removeGitDirectoryButton.toolTip = PTL(@"从 PrettyTerm 记忆中删除当前目录", @"Remove the current directory from PrettyTerm memory");
    _removeGitDirectoryButton.enabled = NO;
    [directoryRow addArrangedSubview:_gitDirectoryPicker];
    [directoryRow addArrangedSubview:_removeGitDirectoryButton];
    [_removeGitDirectoryButton.widthAnchor constraintEqualToConstant:48].active = YES;
    [gitStack addArrangedSubview:directoryRow];

    NSStackView *manualRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    manualRow.translatesAutoresizingMaskIntoConstraints = NO;
    manualRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    manualRow.alignment = NSLayoutAttributeCenterY;
    manualRow.spacing = 6;
    _gitDirectoryInput = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _gitDirectoryInput.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDirectoryInput.placeholderString = PTL(@"手动输入文件夹路径", @"Enter a folder path manually");
    _gitDirectoryInput.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    NSButton *addDirectoryButton = [NSButton buttonWithTitle:PTL(@"添加", @"Add") target:self action:@selector(addManualGitDirectory:)];
    addDirectoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    addDirectoryButton.bezelStyle = NSBezelStyleRounded;
    addDirectoryButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    [manualRow addArrangedSubview:_gitDirectoryInput];
    [manualRow addArrangedSubview:addDirectoryButton];
    [_gitDirectoryInput.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;
    [addDirectoryButton.widthAnchor constraintEqualToConstant:48].active = YES;
    [gitStack addArrangedSubview:manualRow];

    _gitDirectoryHintLabel = [self label:PTL(@"这里只切换 PrettyTerm 的 Git diff 探测目录，不会改变 Claude Code。要让 Claude 访问新目录，请在 Claude Code 执行 /add-dir <路径>。", @"This only changes PrettyTerm's Git diff probe; it does not change Claude Code. Run /add-dir <path> in Claude Code to grant Claude access.") size:9.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    _gitDirectoryHintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _gitDirectoryHintLabel.maximumNumberOfLines = 0;
    [_gitDirectoryHintLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [gitStack addArrangedSubview:_gitDirectoryHintLabel];

    NSStackView *gitActionRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    gitActionRow.translatesAutoresizingMaskIntoConstraints = NO;
    gitActionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    gitActionRow.alignment = NSLayoutAttributeCenterY;
    gitActionRow.spacing = 6;
    _gitDiffToggleButton = [NSButton buttonWithTitle:PTL(@"展开 Git 审阅  ›", @"Expand Git Review  ›") target:self action:@selector(toggleGitDiff:)];
    _gitDiffToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDiffToggleButton.bezelStyle = NSBezelStyleRounded;
    _gitDiffToggleButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    _gitDiffRefreshButton = [NSButton buttonWithTitle:PTL(@"刷新", @"Refresh") target:self action:@selector(refreshGitDiff:)];
    _gitDiffRefreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDiffRefreshButton.bezelStyle = NSBezelStyleRounded;
    _gitDiffRefreshButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _gitDiffRefreshButton.hidden = YES;
    _gitPublishButton = [NSButton buttonWithTitle:PTL(@"提交或推送…", @"Commit or Push…")
        target:self action:@selector(showGitActions:)];
    _gitPublishButton.translatesAutoresizingMaskIntoConstraints = NO;
    _gitPublishButton.bezelStyle = NSBezelStyleRounded;
    _gitPublishButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    _gitPublishButton.contentTintColor = PTWarmAccentColor();
    _gitPublishButton.toolTip = PTL(@"手动填写提交信息后提交，或推送已有提交", @"Enter a commit message manually, or push existing commits");
    _gitPublishButton.enabled = NO;
    _gitDiffProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _gitDiffProgress.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDiffProgress.style = NSProgressIndicatorStyleSpinning;
    _gitDiffProgress.controlSize = NSControlSizeSmall;
    _gitDiffProgress.displayedWhenStopped = NO;
    _gitDiffProgress.hidden = YES;
    [gitActionRow addArrangedSubview:_gitDiffToggleButton];
    [gitActionRow addArrangedSubview:_gitDiffRefreshButton];
    [gitActionRow addArrangedSubview:_gitPublishButton];
    [gitActionRow addArrangedSubview:_gitDiffProgress];
    [_gitDiffProgress.widthAnchor constraintEqualToConstant:14].active = YES;
    [_gitDiffProgress.heightAnchor constraintEqualToConstant:14].active = YES;
    [gitStack addArrangedSubview:gitActionRow];

    _gitDiffScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _gitDiffScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDiffScroll.hasVerticalScroller = YES;
    _gitDiffScroll.hasHorizontalScroller = YES;
    _gitDiffScroll.autohidesScrollers = YES;
    _gitDiffScroll.borderType = NSNoBorder;
    _gitDiffScroll.drawsBackground = YES;
    _gitDiffScroll.backgroundColor = PTWarmCardColor();
    _gitDiffScroll.wantsLayer = YES;
    _gitDiffScroll.layer.cornerRadius = 10.0;
    _gitDiffScroll.layer.borderWidth = 0.7;
    _gitDiffScroll.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.7].CGColor;
    _gitDiffScroll.layer.masksToBounds = YES;
    _gitDiffScroll.hidden = YES;
    // 隐藏状态不能携带一个 560px 的初始 frame，否则它会通过 scroll/stack 的
    // fitting size 把整个检查器锁宽，分隔条看似又“拖不动”。展开后由外层宽度决定。
    _gitDiffTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 0, 360)];
    _gitDiffTextView.editable = NO;
    _gitDiffTextView.selectable = YES;
    _gitDiffTextView.richText = YES;
    _gitDiffTextView.drawsBackground = NO;
    _gitDiffTextView.usesFindBar = YES;
    _gitDiffTextView.usesAdaptiveColorMappingForDarkAppearance = YES;
    _gitDiffTextView.font = [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightRegular];
    _gitDiffTextView.textContainerInset = NSMakeSize(10, 10);
    _gitDiffTextView.horizontallyResizable = YES;
    _gitDiffTextView.verticallyResizable = YES;
    _gitDiffTextView.minSize = NSMakeSize(0, 0);
    _gitDiffTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _gitDiffTextView.textContainer.widthTracksTextView = NO;
    _gitDiffTextView.string = PTL(@"选择目录后展开 Git 审阅。", @"Select a directory, then expand Git Review.");
    _gitDiffScroll.documentView = _gitDiffTextView;
    [_gitDiffScroll.heightAnchor constraintEqualToConstant:360].active = YES;
    [gitStack addArrangedSubview:_gitDiffScroll];
    [stack addArrangedSubview:gitCard];
    [gitCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [gitStack.topAnchor constraintEqualToAnchor:gitCard.topAnchor constant:11],
        [gitStack.leadingAnchor constraintEqualToAnchor:gitCard.leadingAnchor constant:12],
        [gitStack.trailingAnchor constraintEqualToAnchor:gitCard.trailingAnchor constant:-12],
        [gitStack.bottomAnchor constraintEqualToAnchor:gitCard.bottomAnchor constant:-12],
        [directoryRow.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor],
        [manualRow.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor],
        [_gitDirectoryHintLabel.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor],
        [gitActionRow.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor],
        [_gitDiffScroll.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor]
    ]];

    PTAppearanceSurfaceView *changesCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    changesCard.translatesAutoresizingMaskIntoConstraints = NO;
    changesCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    changesCard.layer.cornerRadius = 14;
    changesCard.layer.borderWidth = 0.6;
    NSTextField *changesTitle = [self label:PTL(@"本轮改动", @"CURRENT CHANGES") size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [changesCard addSubview:changesTitle];
    _changedFilesStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _changedFilesStack.translatesAutoresizingMaskIntoConstraints = NO;
    _changedFilesStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _changedFilesStack.alignment = NSLayoutAttributeLeading;
    _changedFilesStack.spacing = 4;
    [changesCard addSubview:_changedFilesStack];
    [stack addArrangedSubview:changesCard];

    PTAppearanceSurfaceView *tasksCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    tasksCard.translatesAutoresizingMaskIntoConstraints = NO;
    tasksCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    tasksCard.layer.cornerRadius = 14;
    tasksCard.layer.borderWidth = 0.6;
    NSTextField *tasksTitle = [self label:PTL(@"任务列表", @"TASKS") size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [tasksCard addSubview:tasksTitle];
    _tasksStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _tasksStack.translatesAutoresizingMaskIntoConstraints = NO;
    _tasksStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _tasksStack.alignment = NSLayoutAttributeLeading;
    _tasksStack.spacing = 4;
    [tasksCard addSubview:_tasksStack];
    [stack addArrangedSubview:tasksCard];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:inspector.topAnchor constant:17],
        [title.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:14],
        [collapse.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-10],
        [collapse.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [scroll.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:inspector.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentView.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [changesCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20],
        [changesTitle.topAnchor constraintEqualToAnchor:changesCard.topAnchor constant:11],
        [changesTitle.leadingAnchor constraintEqualToAnchor:changesCard.leadingAnchor constant:12],
        [changesTitle.trailingAnchor constraintEqualToAnchor:changesCard.trailingAnchor constant:-12],
        [_changedFilesStack.topAnchor constraintEqualToAnchor:changesTitle.bottomAnchor constant:8],
        [_changedFilesStack.leadingAnchor constraintEqualToAnchor:changesCard.leadingAnchor constant:8],
        [_changedFilesStack.trailingAnchor constraintEqualToAnchor:changesCard.trailingAnchor constant:-8],
        [_changedFilesStack.bottomAnchor constraintEqualToAnchor:changesCard.bottomAnchor constant:-8],
        [tasksCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20],
        [tasksTitle.topAnchor constraintEqualToAnchor:tasksCard.topAnchor constant:11],
        [tasksTitle.leadingAnchor constraintEqualToAnchor:tasksCard.leadingAnchor constant:12],
        [tasksTitle.trailingAnchor constraintEqualToAnchor:tasksCard.trailingAnchor constant:-12],
        [_tasksStack.topAnchor constraintEqualToAnchor:tasksTitle.bottomAnchor constant:8],
        [_tasksStack.leadingAnchor constraintEqualToAnchor:tasksCard.leadingAnchor constant:8],
        [_tasksStack.trailingAnchor constraintEqualToAnchor:tasksCard.trailingAnchor constant:-8],
        [_tasksStack.bottomAnchor constraintEqualToAnchor:tasksCard.bottomAnchor constant:-8]
    ]];
    return inspector;
}

- (NSView *)buildConversation {
    PTAppearanceSurfaceView *pane = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    pane.surfaceStyle = PTAppearanceSurfaceStyleCanvas;

    NSVisualEffectView *header = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.material = NSVisualEffectMaterialHeaderView;
    header.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    header.state = NSVisualEffectStateActive;
    [pane addSubview:header];

    _conversationTitle = [self label:PTL(@"选择一个 Claude 会话", @"Select a conversation") size:14 weight:NSFontWeightBold color:NSColor.labelColor];
    [_conversationTitle setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addSubview:_conversationTitle];
    _conversationDetail = [self label:PTL(@"显示老师和 Claude 的文本对话", @"Claude transcript view") size:10.5 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [_conversationDetail setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addSubview:_conversationDetail];

    _modelPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _modelPicker.translatesAutoresizingMaskIntoConstraints = NO;
    _modelPicker.bezelStyle = NSBezelStyleRounded;
    _modelPicker.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _modelPicker.target = self;
    _modelPicker.action = @selector(changeModel:);
    [_modelPicker addItemWithTitle:PTL(@"当前模型", @"Current model")];
    NSArray<NSArray<NSString *> *> *models = @[
        @[@"Claude Fable 5", @"claude-fable-5"],
        @[@"Claude Opus 5", @"claude-opus-5"],
        @[@"Claude Sonnet 5", @"claude-sonnet-5"],
        @[@"Claude Haiku 4.5", @"claude-haiku-4-5"]
    ];
    for (NSArray<NSString *> *entry in models) {
        [_modelPicker addItemWithTitle:entry[0]];
        _modelPicker.lastItem.representedObject = entry[1];
    }
    _modelPicker.enabled = NO;
    [header addSubview:_modelPicker];

    _remoteButton = [NSButton buttonWithTitle:PTL(@"RC禁用", @"RC Off") target:nil action:nil];
    _remoteButton.translatesAutoresizingMaskIntoConstraints = NO;
    _remoteButton.bezelStyle = NSBezelStyleRounded;
    _remoteButton.enabled = NO;
    _remoteButton.toolTip = PTL(@"Claude.ai Remote Control 已禁用", @"Claude.ai Remote Control is disabled");
    [header addSubview:_remoteButton];

    _inspectorToggleButton = [NSButton buttonWithTitle:PTL(@"检查器", @"Inspect") target:self action:@selector(toggleInspector:)];
    _inspectorToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    _inspectorToggleButton.bezelStyle = NSBezelStyleRounded;
    _inspectorToggleButton.toolTip = PTL(@"显示或收起检查器", @"Show or collapse the inspector");
    [header addSubview:_inspectorToggleButton];

    _connectButton = [NSButton buttonWithTitle:PTL(@"同步 Terminal", @"Sync") target:self action:@selector(connectSelectedSession:)];
    _connectButton.translatesAutoresizingMaskIntoConstraints = NO;
    _connectButton.bezelStyle = NSBezelStyleRounded;
    _connectButton.contentTintColor = PTWarmAccentColor();
    _connectButton.enabled = NO;
    _connectButton.toolTip = PTL(@"同步选中的 Terminal Claude Code 会话", @"Sync the selected Terminal Claude Code conversation");
    [header addSubview:_connectButton];

    _floatingButton = [NSButton buttonWithImage:
        [NSImage imageWithSystemSymbolName:@"pin" accessibilityDescription:PTL(@"悬浮当前对话", @"Float current conversation")]
        target:self action:@selector(toggleFloatingConversation:)];
    _floatingButton.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingButton.bezelStyle = NSBezelStyleRounded;
    _floatingButton.toolTip = PTL(@"悬浮当前对话（⌘O）", @"Float current conversation (⌘O)");
    _floatingButton.enabled = NO;
    [header addSubview:_floatingButton];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    [configuration.userContentController addScriptMessageHandler:self name:@"quoteSelection"];
    [configuration.userContentController addScriptMessageHandler:self name:@"openTranscriptEditReview"];
    _conversationView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    _conversationView.translatesAutoresizingMaskIntoConstraints = NO;
    _conversationView.navigationDelegate = self;
    if (@available(macOS 12.0, *)) _conversationView.underPageBackgroundColor = NSColor.clearColor;
    [pane addSubview:_conversationView];
    NSURL *htmlURL = [NSBundle.mainBundle URLForResource:@"index" withExtension:@"html"];
    if (htmlURL) [_conversationView loadFileURL:htmlURL allowingReadAccessToURL:NSBundle.mainBundle.resourceURL];

    NSVisualEffectView *composerBar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    composerBar.translatesAutoresizingMaskIntoConstraints = NO;
    composerBar.material = NSVisualEffectMaterialContentBackground;
    composerBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    composerBar.state = NSVisualEffectStateActive;
    [pane addSubview:composerBar];

    _composerTargetLabel = [self label:PTL(@"只读 · 请先同步当前会话", @"Read only · sync this conversation first") size:10.5 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [composerBar addSubview:_composerTargetLabel];

    _imagePreviewScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _imagePreviewScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _imagePreviewScroll.drawsBackground = NO;
    _imagePreviewScroll.hasHorizontalScroller = YES;
    _imagePreviewScroll.hasVerticalScroller = NO;
    _imagePreviewScroll.autohidesScrollers = YES;
    _imagePreviewScroll.hidden = YES;
    [composerBar addSubview:_imagePreviewScroll];

    _imagePreviewStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _imagePreviewStack.translatesAutoresizingMaskIntoConstraints = NO;
    _imagePreviewStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _imagePreviewStack.alignment = NSLayoutAttributeCenterY;
    _imagePreviewStack.spacing = 7;
    _imagePreviewStack.edgeInsets = NSEdgeInsetsMake(2, 0, 2, 0);
    _imagePreviewScroll.documentView = _imagePreviewStack;

    _imageButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"photo.badge.plus"
        accessibilityDescription:PTL(@"添加图片", @"Add images")] target:self action:@selector(chooseImages:)];
    _imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _imageButton.bezelStyle = NSBezelStyleRounded;
    _imageButton.toolTip = PTL(@"添加图片（仅支持图片文件）", @"Add images (image files only)");
    _imageButton.enabled = NO;
    [composerBar addSubview:_imageButton];

    NSScrollView *composerScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    composerScroll.translatesAutoresizingMaskIntoConstraints = NO;
    composerScroll.borderType = NSBezelBorder;
    composerScroll.hasVerticalScroller = YES;
    composerScroll.autohidesScrollers = YES;
    composerScroll.drawsBackground = YES;
    composerScroll.backgroundColor = PTWarmCardColor();
    composerScroll.wantsLayer = YES;
    composerScroll.layer.cornerRadius = 12;
    composerScroll.layer.masksToBounds = YES;
    [composerBar addSubview:composerScroll];

    _composerTextView = [[PTComposerTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 52)];
    _composerTextView.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    _composerTextView.drawsBackground = NO;
    _composerTextView.richText = NO;
    _composerTextView.allowsUndo = YES;
    _composerTextView.verticallyResizable = YES;
    _composerTextView.horizontallyResizable = NO;
    _composerTextView.textContainer.widthTracksTextView = YES;
    _composerTextView.textContainerInset = NSMakeSize(8, 8);
    _composerTextView.editable = NO;
    __weak typeof(self) weakSelf = self;
    _composerTextView.submitHandler = ^{
        [weakSelf sendMessage:nil];
    };
    _composerTextView.imagePasteHandler = ^BOOL(NSPasteboard *pasteboard) {
        return [weakSelf handleImagePasteboard:pasteboard];
    };
    composerScroll.documentView = _composerTextView;

    _sendButton = [NSButton buttonWithTitle:PTL(@"发送 ↗", @"Send ↗") target:self action:@selector(sendMessage:)];
    _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    _sendButton.bezelStyle = NSBezelStyleRounded;
    _sendButton.contentTintColor = PTWarmAccentColor();
    _sendButton.enabled = NO;
    [composerBar addSubview:_sendButton];

    NSVisualEffectView *statusBar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    statusBar.material = NSVisualEffectMaterialHeaderView;
    statusBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    statusBar.state = NSVisualEffectStateActive;
    [pane addSubview:statusBar];
    _bottomStatusLabel = [self label:PTL(@"只读 · Terminal 是唯一执行引擎", @"Read only · Terminal is the sole execution engine") size:10 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [statusBar addSubview:_bottomStatusLabel];

    _composerHeightConstraint = [composerBar.heightAnchor constraintEqualToConstant:116];
    _imagePreviewHeightConstraint = [_imagePreviewScroll.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:pane.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:60],
        [_conversationTitle.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:18],
        [_conversationTitle.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
        [_conversationDetail.leadingAnchor constraintEqualToAnchor:_conversationTitle.leadingAnchor],
        [_conversationDetail.topAnchor constraintEqualToAnchor:_conversationTitle.bottomAnchor constant:2],
        [_connectButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-14],
        [_connectButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_floatingButton.trailingAnchor constraintEqualToAnchor:_connectButton.leadingAnchor constant:-8],
        [_floatingButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_floatingButton.widthAnchor constraintEqualToConstant:34],
        [_floatingButton.heightAnchor constraintEqualToConstant:28],
        [_remoteButton.trailingAnchor constraintEqualToAnchor:_floatingButton.leadingAnchor constant:-8],
        [_remoteButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_inspectorToggleButton.trailingAnchor constraintEqualToAnchor:_remoteButton.leadingAnchor constant:-8],
        [_inspectorToggleButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_modelPicker.trailingAnchor constraintEqualToAnchor:_inspectorToggleButton.leadingAnchor constant:-8],
        [_modelPicker.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_modelPicker.widthAnchor constraintEqualToConstant:110],
        [_inspectorToggleButton.widthAnchor constraintEqualToConstant:62],
        [_remoteButton.widthAnchor constraintEqualToConstant:60],
        [_connectButton.widthAnchor constraintEqualToConstant:84],
        [_conversationTitle.trailingAnchor constraintLessThanOrEqualToAnchor:_modelPicker.leadingAnchor constant:-12],
        [_conversationDetail.trailingAnchor constraintLessThanOrEqualToAnchor:_modelPicker.leadingAnchor constant:-12],

        [composerBar.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [composerBar.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [composerBar.bottomAnchor constraintEqualToAnchor:statusBar.topAnchor],
        _composerHeightConstraint,
        [_composerTargetLabel.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:18],
        [_composerTargetLabel.topAnchor constraintEqualToAnchor:composerBar.topAnchor constant:8],
        [_imagePreviewScroll.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:18],
        [_imagePreviewScroll.trailingAnchor constraintEqualToAnchor:composerBar.trailingAnchor constant:-16],
        [_imagePreviewScroll.topAnchor constraintEqualToAnchor:_composerTargetLabel.bottomAnchor constant:4],
        _imagePreviewHeightConstraint,
        [_imagePreviewStack.leadingAnchor constraintEqualToAnchor:_imagePreviewScroll.contentView.leadingAnchor],
        [_imagePreviewStack.topAnchor constraintEqualToAnchor:_imagePreviewScroll.contentView.topAnchor],
        [_imagePreviewStack.bottomAnchor constraintEqualToAnchor:_imagePreviewScroll.contentView.bottomAnchor],
        [_imageButton.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:24],
        [_imageButton.widthAnchor constraintEqualToConstant:36],
        [_imageButton.heightAnchor constraintEqualToConstant:36],
        [composerScroll.leadingAnchor constraintEqualToAnchor:_imageButton.trailingAnchor constant:10],
        [composerScroll.topAnchor constraintEqualToAnchor:_imagePreviewScroll.bottomAnchor constant:6],
        [composerScroll.bottomAnchor constraintEqualToAnchor:composerBar.bottomAnchor constant:-10],
        [_imageButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [_sendButton.leadingAnchor constraintEqualToAnchor:composerScroll.trailingAnchor constant:12],
        [_sendButton.trailingAnchor constraintEqualToAnchor:composerBar.trailingAnchor constant:-24],
        [_sendButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [statusBar.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [statusBar.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [statusBar.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor],
        [statusBar.heightAnchor constraintEqualToConstant:26],
        [_bottomStatusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:18],
        [_bottomStatusLabel.trailingAnchor constraintEqualToAnchor:statusBar.trailingAnchor constant:-16],
        [_bottomStatusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],

        [_conversationView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [_conversationView.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [_conversationView.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [_conversationView.bottomAnchor constraintEqualToAnchor:composerBar.topAnchor]
    ]];
    return pane;
}

- (PTSessionInfo *)sessionWithID:(NSString *)sessionID {
    if (sessionID.length == 0) return nil;
    for (PTSessionInfo *session in _sessions) {
        if ([session.sessionID isEqual:sessionID]) return session;
    }
    return nil;
}

- (void)updateFloatingControls {
    BOOL hasSelection = _selectedSession.sessionID.length > 0;
    BOOL showingSelection = _floatingPanel.visible &&
        [_floatingSessionID isEqual:_selectedSession.sessionID];
    _floatingButton.enabled = hasSelection;
    _floatingButton.image = [NSImage imageWithSystemSymbolName:(showingSelection ? @"pin.fill" : @"pin")
        accessibilityDescription:(showingSelection ? @"关闭悬浮对话" : @"悬浮当前对话")];
    _floatingButton.toolTip = showingSelection ? @"关闭悬浮对话（⌘O）" : @"悬浮当前对话（⌘O）";
    _floatingMenuItem.enabled = hasSelection;
    _floatingMenuItem.title = showingSelection ? @"关闭悬浮对话" : @"悬浮当前对话";
}

- (void)buildFloatingPanelIfNeeded {
    if (_floatingPanel) return;
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow |
        NSWindowStyleMaskNonactivatingPanel;
    _floatingPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 640)
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    _floatingPanel.delegate = self;
    _floatingPanel.level = NSFloatingWindowLevel;
    _floatingPanel.floatingPanel = YES;
    _floatingPanel.hidesOnDeactivate = NO;
    _floatingPanel.becomesKeyOnlyIfNeeded = YES;
    _floatingPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    _floatingPanel.minSize = NSMakeSize(360, 320);
    _floatingPanel.releasedWhenClosed = NO;
    _floatingPanel.titlebarAppearsTransparent = YES;
    _floatingPanel.backgroundColor = PTWarmCanvasColor();

    PTAppearanceSurfaceView *surface = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    surface.surfaceStyle = PTAppearanceSurfaceStyleCanvas;
    _floatingPanel.contentView = surface;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    [configuration.userContentController addScriptMessageHandler:self name:@"quoteSelection"];
    [configuration.userContentController addScriptMessageHandler:self name:@"openTranscriptEditReview"];
    _floatingConversationView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    _floatingConversationView.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingConversationView.navigationDelegate = self;
    if (@available(macOS 12.0, *)) _floatingConversationView.underPageBackgroundColor = NSColor.clearColor;
    [surface addSubview:_floatingConversationView];

    NSVisualEffectView *composerBar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    composerBar.translatesAutoresizingMaskIntoConstraints = NO;
    composerBar.material = NSVisualEffectMaterialContentBackground;
    composerBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    composerBar.state = NSVisualEffectStateActive;
    [surface addSubview:composerBar];

    _floatingComposerLabel = [self label:PTL(@"未同步此会话", @"Conversation not synced") size:10.5
        weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [composerBar addSubview:_floatingComposerLabel];

    _floatingImagePreviewScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _floatingImagePreviewScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingImagePreviewScroll.drawsBackground = NO;
    _floatingImagePreviewScroll.hasHorizontalScroller = YES;
    _floatingImagePreviewScroll.hasVerticalScroller = NO;
    _floatingImagePreviewScroll.autohidesScrollers = YES;
    _floatingImagePreviewScroll.hidden = YES;
    [composerBar addSubview:_floatingImagePreviewScroll];

    _floatingImagePreviewStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _floatingImagePreviewStack.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingImagePreviewStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _floatingImagePreviewStack.alignment = NSLayoutAttributeCenterY;
    _floatingImagePreviewStack.spacing = 6;
    _floatingImagePreviewScroll.documentView = _floatingImagePreviewStack;

    _floatingImageButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"photo.badge.plus"
        accessibilityDescription:PTL(@"添加图片", @"Add images")] target:self action:@selector(chooseFloatingImages:)];
    _floatingImageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingImageButton.bezelStyle = NSBezelStyleRounded;
    _floatingImageButton.toolTip = PTL(@"添加图片（仅支持图片文件）", @"Add images (image files only)");
    _floatingImageButton.enabled = NO;
    [composerBar addSubview:_floatingImageButton];

    NSScrollView *composerScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    composerScroll.translatesAutoresizingMaskIntoConstraints = NO;
    composerScroll.borderType = NSBezelBorder;
    composerScroll.hasVerticalScroller = YES;
    composerScroll.autohidesScrollers = YES;
    composerScroll.drawsBackground = YES;
    composerScroll.backgroundColor = PTWarmCardColor();
    composerScroll.wantsLayer = YES;
    composerScroll.layer.cornerRadius = 11;
    composerScroll.layer.masksToBounds = YES;
    [composerBar addSubview:composerScroll];

    _floatingComposerTextView = [[PTComposerTextView alloc] initWithFrame:NSMakeRect(0, 0, 360, 44)];
    _floatingComposerTextView.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
    _floatingComposerTextView.drawsBackground = NO;
    _floatingComposerTextView.richText = NO;
    _floatingComposerTextView.allowsUndo = YES;
    _floatingComposerTextView.verticallyResizable = YES;
    _floatingComposerTextView.horizontallyResizable = NO;
    _floatingComposerTextView.textContainer.widthTracksTextView = YES;
    _floatingComposerTextView.textContainerInset = NSMakeSize(7, 7);
    _floatingComposerTextView.editable = NO;
    __weak typeof(self) weakSelf = self;
    _floatingComposerTextView.submitHandler = ^{
        [weakSelf sendFloatingMessage:nil];
    };
    _floatingComposerTextView.imagePasteHandler = ^BOOL(NSPasteboard *pasteboard) {
        return [weakSelf handleFloatingImagePasteboard:pasteboard];
    };
    composerScroll.documentView = _floatingComposerTextView;

    _floatingSendButton = [NSButton buttonWithTitle:PTL(@"发送 ↗", @"Send ↗") target:self action:@selector(sendFloatingMessage:)];
    _floatingSendButton.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingSendButton.bezelStyle = NSBezelStyleRounded;
    _floatingSendButton.contentTintColor = PTWarmAccentColor();
    _floatingSendButton.enabled = NO;
    [composerBar addSubview:_floatingSendButton];

    _floatingComposerHeightConstraint = [composerBar.heightAnchor constraintEqualToConstant:110];
    _floatingImagePreviewHeightConstraint = [_floatingImagePreviewScroll.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_floatingConversationView.topAnchor constraintEqualToAnchor:surface.topAnchor],
        [_floatingConversationView.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [_floatingConversationView.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [_floatingConversationView.bottomAnchor constraintEqualToAnchor:composerBar.topAnchor],
        [composerBar.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [composerBar.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [composerBar.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor],
        _floatingComposerHeightConstraint,
        [_floatingComposerLabel.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:14],
        [_floatingComposerLabel.trailingAnchor constraintEqualToAnchor:composerBar.trailingAnchor constant:-14],
        [_floatingComposerLabel.topAnchor constraintEqualToAnchor:composerBar.topAnchor constant:7],
        [_floatingImagePreviewScroll.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:14],
        [_floatingImagePreviewScroll.trailingAnchor constraintEqualToAnchor:composerBar.trailingAnchor constant:-12],
        [_floatingImagePreviewScroll.topAnchor constraintEqualToAnchor:_floatingComposerLabel.bottomAnchor constant:3],
        _floatingImagePreviewHeightConstraint,
        [_floatingImagePreviewStack.leadingAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.contentView.leadingAnchor],
        [_floatingImagePreviewStack.topAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.contentView.topAnchor],
        [_floatingImagePreviewStack.bottomAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.contentView.bottomAnchor],
        [_floatingImageButton.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:18],
        [_floatingImageButton.widthAnchor constraintEqualToConstant:34],
        [_floatingImageButton.heightAnchor constraintEqualToConstant:34],
        [composerScroll.leadingAnchor constraintEqualToAnchor:_floatingImageButton.trailingAnchor constant:9],
        [composerScroll.topAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.bottomAnchor constant:5],
        [composerScroll.bottomAnchor constraintEqualToAnchor:composerBar.bottomAnchor constant:-9],
        [_floatingImageButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [_floatingSendButton.leadingAnchor constraintEqualToAnchor:composerScroll.trailingAnchor constant:10],
        [_floatingSendButton.trailingAnchor constraintEqualToAnchor:composerBar.trailingAnchor constant:-18],
        [_floatingSendButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor]
    ]];

    NSURL *htmlURL = [NSBundle.mainBundle URLForResource:@"index" withExtension:@"html"];
    if (htmlURL) {
        [_floatingConversationView loadFileURL:htmlURL allowingReadAccessToURL:NSBundle.mainBundle.resourceURL];
    }
}

- (void)positionFloatingPanelNearMainWindow {
    NSScreen *screen = _window.screen ?: NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;
    NSRect mainFrame = _window.frame;
    NSRect panelFrame = _floatingPanel.frame;
    panelFrame.origin.x = MIN(NSMaxX(mainFrame) - panelFrame.size.width - 22,
                              NSMaxX(visible) - panelFrame.size.width - 12);
    panelFrame.origin.x = MAX(panelFrame.origin.x, NSMinX(visible) + 12);
    panelFrame.origin.y = MIN(NSMaxY(mainFrame) - panelFrame.size.height - 22,
                              NSMaxY(visible) - panelFrame.size.height - 12);
    panelFrame.origin.y = MAX(panelFrame.origin.y, NSMinY(visible) + 12);
    [_floatingPanel setFrame:panelFrame display:NO];
}

- (void)renderFloatingSession:(PTSessionInfo *)session {
    if (!_floatingWebReady || !_floatingPanel.visible || !session) return;
    if (_floatingRenderInFlight) {
        if (!_pendingFloatingSession ||
            ![_pendingFloatingSession.sessionID isEqual:session.sessionID] ||
            [_pendingFloatingSession.modifiedAt compare:session.modifiedAt] != NSOrderedDescending) {
            _pendingFloatingSession = session;
        }
        return;
    }
    if (!PTSessionRenderNeedsUpdate(
        _floatingRenderedSessionID,
        _floatingRenderedModifiedAt,
        _floatingRenderedMessageCount,
        session.sessionID,
        session.modifiedAt,
        session.assistantMessages.count
    )) return;

    NSDictionary *payload = @{
        @"sessionId": session.sessionID ?: @"",
        @"title": session.title ?: @"未命名会话",
        @"cwd": session.cwd ?: @"",
        @"model": session.model ?: @"Claude",
        @"interfaceLanguage": PTInterfaceLanguageCode(),
        @"messages": session.assistantMessages ?: @[]
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : nil;
    if (!json) return;

    NSUInteger messageCount = session.assistantMessages.count;
    BOOL canAppend = [_floatingRenderedSessionID isEqual:session.sessionID] &&
        _floatingRenderedModifiedAt != nil && _floatingRenderedMessageCount < messageCount;
    NSString *script = nil;
    if (canAppend) {
        NSArray *incoming = [session.assistantMessages subarrayWithRange:
            NSMakeRange(_floatingRenderedMessageCount, messageCount - _floatingRenderedMessageCount)];
        NSData *incomingData = [NSJSONSerialization dataWithJSONObject:incoming options:0 error:nil];
        NSString *incomingJSON = incomingData
            ? [[NSString alloc] initWithData:incomingData encoding:NSUTF8StringEncoding] : nil;
        if (incomingJSON) {
            script = [NSString stringWithFormat:
                @"window.appendClaudeMessages(%@, %@); null;", json, incomingJSON];
        }
    }
    if (!script) script = [NSString stringWithFormat:@"window.setClaudeSession(%@); null;", json];
    NSUInteger generation = _floatingRenderGeneration;
    NSString *targetSessionID = [session.sessionID copy];
    NSDate *targetModifiedAt = session.modifiedAt;
    _floatingRenderInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [_floatingConversationView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        self->_floatingRenderInFlight = NO;
        BOOL stillCurrent = generation == self->_floatingRenderGeneration &&
            self->_floatingPanel.visible && [self->_floatingSessionID isEqual:targetSessionID];
        if (stillCurrent && !error) {
            self->_floatingRenderedSessionID = targetSessionID;
            self->_floatingRenderedModifiedAt = targetModifiedAt;
            self->_floatingRenderedMessageCount = session.assistantMessages.count;
        } else if (stillCurrent) {
            self->_floatingRenderedSessionID = nil;
            self->_floatingRenderedModifiedAt = nil;
            self->_floatingRenderedMessageCount = 0;
            self->_floatingPanel.title = @"悬浮对话 · 显示更新失败";
        }
        self->_pendingFloatingSession = nil;
        PTSessionInfo *pending = [self sessionWithID:self->_floatingSessionID];
        if (pending && self->_floatingPanel.visible) {
            [self renderFloatingSession:pending];
        } else if (!stillCurrent && self->_floatingPanel.visible) {
            [self refreshFloatingConversation];
        }
    }];
}

- (void)refreshFloatingConversation {
    if (!_floatingPanel.visible || _floatingSessionID.length == 0) return;
    PTSessionInfo *session = [self sessionWithID:_floatingSessionID];
    if (!session) return;
    [self updateFloatingTitleForSession:session];
    [self renderFloatingSession:session];
    [self updateFloatingComposerState];
}

- (void)toggleFloatingConversation:(id)sender {
    (void)sender;
    PTFloatingConversationAction action = PTFloatingConversationActionForState(
        _floatingPanel.visible,
        _floatingSessionID,
        _selectedSession.sessionID
    );
    if (action == PTFloatingConversationActionNone) {
        NSBeep();
        return;
    }
    if (action == PTFloatingConversationActionClose) {
        [_floatingPanel close];
        return;
    }

    BOOL wasVisible = _floatingPanel.visible;
    [self buildFloatingPanelIfNeeded];
    if (_floatingSessionID.length && ![_floatingSessionID isEqual:_selectedSession.sessionID]) {
        [self clearFloatingPendingImagesAfterSuccessfulSend];
        _floatingComposerTextView.string = @"";
    }
    _floatingSessionID = [_selectedSession.sessionID copy];
    _floatingRenderedSessionID = nil;
    _floatingRenderedModifiedAt = nil;
    _floatingRenderedMessageCount = 0;
    _pendingFloatingSession = nil;
    _floatingRenderGeneration += 1;
    if (!wasVisible) [self positionFloatingPanelNearMainWindow];
    [_floatingPanel orderFrontRegardless];
    [self refreshFloatingConversation];
    [self updateFloatingControls];
    [self updateFloatingComposerState];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object != _floatingPanel) return;
    _floatingRenderGeneration += 1;
    _floatingSessionID = nil;
    _floatingRenderedSessionID = nil;
    _floatingRenderedModifiedAt = nil;
    _floatingRenderedMessageCount = 0;
    _pendingFloatingSession = nil;
    [self clearFloatingPendingImagesAfterSuccessfulSend];
    _floatingComposerTextView.string = @"";
    [self updateFloatingControls];
    [self updateFloatingComposerState];
}

- (NSArray<NSImage *> *)pendingImagesForClaude {
    NSMutableArray<NSImage *> *images = [NSMutableArray arrayWithCapacity:_pendingImages.count];
    for (NSDictionary *item in _pendingImages) {
        NSImage *image = [item[@"image"] isKindOfClass:NSImage.class] ? item[@"image"] : nil;
        if (image.isValid) [images addObject:image];
    }
    return images;
}

- (NSArray<NSImage *> *)floatingPendingImagesForClaude {
    NSMutableArray<NSImage *> *images = [NSMutableArray arrayWithCapacity:_floatingPendingImages.count];
    for (NSDictionary *item in _floatingPendingImages) {
        NSImage *image = [item[@"image"] isKindOfClass:NSImage.class] ? item[@"image"] : nil;
        if (image.isValid) [images addObject:image];
    }
    return images;
}

- (BOOL)addFloatingImageURL:(NSURL *)url temporary:(BOOL)temporary {
    if (!url.isFileURL || !PTIsSupportedImagePath(url.path)) return NO;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory] || isDirectory) return NO;
    for (NSDictionary *item in _floatingPendingImages) {
        if ([item[@"path"] isEqual:url.path]) return YES;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image || !image.isValid) return NO;
    [_floatingPendingImages addObject:@{
        @"path": url.path,
        @"image": image,
        @"temporary": @(temporary)
    }];
    if (temporary) [_temporaryImagePaths addObject:url.path];
    [self updateFloatingImagePreviews];
    return YES;
}

- (BOOL)handleFloatingImagePasteboard:(NSPasteboard *)pasteboard {
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    NSArray<NSURL *> *fileURLs = [pasteboard readObjectsForClasses:@[NSURL.class] options:options];
    if (fileURLs.count > 0) {
        for (NSURL *url in fileURLs) {
            if (!PTIsSupportedImagePath(url.path) || ![[NSImage alloc] initWithContentsOfURL:url]) {
                _floatingComposerLabel.stringValue = @"仅支持粘贴图片，其他文件已拒绝";
                return YES;
            }
        }
        for (NSURL *url in fileURLs) [self addFloatingImageURL:url temporary:NO];
        _floatingComposerLabel.stringValue = [NSString stringWithFormat:@"已添加 %lu 张图片",
            (unsigned long)fileURLs.count];
        return YES;
    }

    NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
    if (!image || !image.isValid) return NO;
    NSURL *temporaryURL = [self writeTemporaryPasteImage:image];
    if (!temporaryURL || ![self addFloatingImageURL:temporaryURL temporary:YES]) {
        _floatingComposerLabel.stringValue = @"无法读取剪贴板图片";
        return YES;
    }
    _floatingComposerLabel.stringValue = @"已从剪贴板添加图片";
    return YES;
}

- (void)chooseFloatingImages:(id)sender {
    (void)sender;
    BOOL ready = _bridge.running && [_bridge.sessionID isEqual:_floatingSessionID];
    if (!ready) {
        _floatingComposerLabel.stringValue = @"请先同步此 Terminal 会话";
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择图片";
    panel.prompt = @"添加";
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;
    panel.resolvesAliases = YES;
    NSMutableArray<UTType *> *imageTypes = [NSMutableArray array];
    for (NSString *extension in @[@"png", @"jpg", @"jpeg", @"heic", @"heif",
        @"webp", @"gif", @"tif", @"tiff", @"bmp"]) {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if (type) [imageTypes addObject:type];
    }
    panel.allowedContentTypes = imageTypes;
    [panel beginSheetModalForWindow:_floatingPanel completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSUInteger added = 0;
        for (NSURL *url in panel.URLs) {
            if ([self addFloatingImageURL:url temporary:NO]) added++;
        }
        self->_floatingComposerLabel.stringValue = added
            ? [NSString stringWithFormat:@"已添加 %lu 张图片", (unsigned long)added]
            : @"没有可用的图片";
    }];
}

- (void)removeFloatingPendingImage:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    NSUInteger index = [_floatingPendingImages indexOfObjectPassingTest:
        ^BOOL(NSDictionary *item, NSUInteger itemIndex, BOOL *stop) {
            (void)itemIndex;
            (void)stop;
            return [item[@"path"] isEqual:path];
        }];
    if (index == NSNotFound) return;
    NSDictionary *item = _floatingPendingImages[index];
    [_floatingPendingImages removeObjectAtIndex:index];
    if ([item[@"temporary"] boolValue]) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [self updateFloatingImagePreviews];
}

- (void)updateFloatingImagePreviews {
    for (NSView *view in _floatingImagePreviewStack.arrangedSubviews.copy) {
        [_floatingImagePreviewStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *item in _floatingPendingImages) {
        PTAppearanceSurfaceView *chip = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.surfaceStyle = PTAppearanceSurfaceStyleChip;
        chip.layer.cornerRadius = 9;
        chip.layer.borderWidth = 0.6;

        NSImageView *thumbnail = [[NSImageView alloc] initWithFrame:NSZeroRect];
        thumbnail.translatesAutoresizingMaskIntoConstraints = NO;
        thumbnail.image = item[@"image"];
        thumbnail.imageScaling = NSImageScaleProportionallyUpOrDown;
        thumbnail.wantsLayer = YES;
        thumbnail.layer.cornerRadius = 6;
        thumbnail.layer.masksToBounds = YES;
        [chip addSubview:thumbnail];

        NSButton *remove = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
            accessibilityDescription:@"移除图片"] target:self action:@selector(removeFloatingPendingImage:)];
        remove.translatesAutoresizingMaskIntoConstraints = NO;
        remove.bezelStyle = NSBezelStyleInline;
        remove.contentTintColor = NSColor.tertiaryLabelColor;
        remove.identifier = item[@"path"];
        [chip addSubview:remove];
        [_floatingImagePreviewStack addArrangedSubview:chip];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:64],
            [chip.heightAnchor constraintEqualToConstant:42],
            [thumbnail.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:5],
            [thumbnail.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [thumbnail.widthAnchor constraintEqualToConstant:32],
            [thumbnail.heightAnchor constraintEqualToConstant:32],
            [remove.leadingAnchor constraintEqualToAnchor:thumbnail.trailingAnchor constant:3],
            [remove.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-3],
            [remove.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.widthAnchor constraintEqualToConstant:20]
        ]];
    }
    BOOL hasImages = _floatingPendingImages.count > 0;
    _floatingImagePreviewScroll.hidden = !hasImages;
    _floatingImagePreviewHeightConstraint.constant = hasImages ? 46 : 0;
    _floatingComposerHeightConstraint.constant = hasImages ? 158 : 110;
    [_floatingPanel.contentView layoutSubtreeIfNeeded];
}

- (void)clearFloatingPendingImagesAfterSuccessfulSend {
    for (NSDictionary *item in _floatingPendingImages.copy) {
        if (![item[@"temporary"] boolValue]) continue;
        NSString *path = item[@"path"];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [_floatingPendingImages removeAllObjects];
    [self updateFloatingImagePreviews];
}

- (BOOL)addImageURL:(NSURL *)url temporary:(BOOL)temporary {
    if (!url.isFileURL || !PTIsSupportedImagePath(url.path)) return NO;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory] || isDirectory) return NO;
    for (NSDictionary *item in _pendingImages) {
        if ([item[@"path"] isEqual:url.path]) return YES;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image || !image.isValid) return NO;
    [_pendingImages addObject:@{
        @"path": url.path,
        @"image": image,
        @"temporary": @(temporary)
    }];
    if (temporary) [_temporaryImagePaths addObject:url.path];
    [self updateImagePreviews];
    return YES;
}

- (NSURL *)writeTemporaryPasteImage:(NSImage *)image {
    NSData *tiff = image.TIFFRepresentation;
    NSBitmapImageRep *representation = tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
    NSData *png = [representation representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png.length) return nil;
    NSString *fileName = [NSString stringWithFormat:@"PrettyTerm-paste-%@.png", NSUUID.UUID.UUIDString];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    return [png writeToFile:path atomically:YES] ? [NSURL fileURLWithPath:path] : nil;
}

- (BOOL)handleImagePasteboard:(NSPasteboard *)pasteboard {
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    NSArray<NSURL *> *fileURLs = [pasteboard readObjectsForClasses:@[NSURL.class] options:options];
    if (fileURLs.count > 0) {
        for (NSURL *url in fileURLs) {
            if (!PTIsSupportedImagePath(url.path) || ![[NSImage alloc] initWithContentsOfURL:url]) {
                _statusLabel.stringValue = @"仅支持粘贴图片，其他文件已拒绝";
                return YES;
            }
        }
        for (NSURL *url in fileURLs) [self addImageURL:url temporary:NO];
        _statusLabel.stringValue = [NSString stringWithFormat:@"已添加 %lu 张图片",
            (unsigned long)fileURLs.count];
        return YES;
    }

    NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
    if (!image || !image.isValid) return NO;
    NSURL *temporaryURL = [self writeTemporaryPasteImage:image];
    if (!temporaryURL || ![self addImageURL:temporaryURL temporary:YES]) {
        _statusLabel.stringValue = @"无法读取剪贴板图片";
        return YES;
    }
    _statusLabel.stringValue = @"已从剪贴板添加图片";
    return YES;
}

- (void)chooseImages:(id)sender {
    if (!_agentState.commandsEnabled) {
        _statusLabel.stringValue = @"请先同步当前选中的 Terminal 会话";
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择图片";
    panel.prompt = @"添加";
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;
    panel.resolvesAliases = YES;
    NSMutableArray<UTType *> *imageTypes = [NSMutableArray array];
    for (NSString *extension in @[@"png", @"jpg", @"jpeg", @"heic", @"heif",
        @"webp", @"gif", @"tif", @"tiff", @"bmp"]) {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if (type) [imageTypes addObject:type];
    }
    panel.allowedContentTypes = imageTypes;
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSUInteger added = 0;
        for (NSURL *url in panel.URLs) {
            if ([self addImageURL:url temporary:NO]) added++;
        }
        self->_statusLabel.stringValue = added
            ? [NSString stringWithFormat:@"已添加 %lu 张图片", (unsigned long)added]
            : @"没有可用的图片";
    }];
}

- (void)removePendingImage:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    NSUInteger index = [_pendingImages indexOfObjectPassingTest:
        ^BOOL(NSDictionary *item, NSUInteger itemIndex, BOOL *stop) {
            (void)itemIndex;
            (void)stop;
            return [item[@"path"] isEqual:path];
        }];
    if (index == NSNotFound) return;
    NSDictionary *item = _pendingImages[index];
    [_pendingImages removeObjectAtIndex:index];
    if ([item[@"temporary"] boolValue]) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [self updateImagePreviews];
}

- (void)updateImagePreviews {
    for (NSView *view in _imagePreviewStack.arrangedSubviews.copy) {
        [_imagePreviewStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *item in _pendingImages) {
        PTAppearanceSurfaceView *chip = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.surfaceStyle = PTAppearanceSurfaceStyleChip;
        chip.layer.cornerRadius = 10;
        chip.layer.borderWidth = 0.6;

        NSImageView *thumbnail = [[NSImageView alloc] initWithFrame:NSZeroRect];
        thumbnail.translatesAutoresizingMaskIntoConstraints = NO;
        thumbnail.image = item[@"image"];
        thumbnail.imageScaling = NSImageScaleProportionallyUpOrDown;
        thumbnail.wantsLayer = YES;
        thumbnail.layer.cornerRadius = 7;
        thumbnail.layer.masksToBounds = YES;
        [chip addSubview:thumbnail];

        NSString *path = item[@"path"];
        NSTextField *name = [self label:path.lastPathComponent ?: @"图片"
            size:10.5 weight:NSFontWeightMedium color:NSColor.labelColor];
        name.toolTip = path;
        [chip addSubview:name];

        NSButton *remove = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
            accessibilityDescription:@"移除图片"] target:self action:@selector(removePendingImage:)];
        remove.translatesAutoresizingMaskIntoConstraints = NO;
        remove.bezelStyle = NSBezelStyleInline;
        remove.contentTintColor = NSColor.tertiaryLabelColor;
        remove.identifier = path;
        [chip addSubview:remove];

        [_imagePreviewStack addArrangedSubview:chip];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:180],
            [chip.heightAnchor constraintEqualToConstant:40],
            [thumbnail.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:5],
            [thumbnail.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [thumbnail.widthAnchor constraintEqualToConstant:30],
            [thumbnail.heightAnchor constraintEqualToConstant:30],
            [name.leadingAnchor constraintEqualToAnchor:thumbnail.trailingAnchor constant:7],
            [name.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:5],
            [remove.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-5],
            [remove.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.widthAnchor constraintEqualToConstant:20],
            [name.widthAnchor constraintLessThanOrEqualToConstant:108]
        ]];
    }
    BOOL hasImages = _pendingImages.count > 0;
    _imagePreviewScroll.hidden = !hasImages;
    _imagePreviewHeightConstraint.constant = hasImages ? 44 : 0;
    _composerHeightConstraint.constant = hasImages ? 160 : 116;
    [_window.contentView layoutSubtreeIfNeeded];
}

- (void)clearPendingImagesAfterSuccessfulSend {
    for (NSDictionary *item in _pendingImages.copy) {
        if (![item[@"temporary"] boolValue]) continue;
        NSString *path = item[@"path"];
        // Ctrl+V 返回后 Claude Code 已经把图片读入自己的输入缓冲区并在提交时
        // 写进 JSONL 的 base64 block；PrettyTerm 的预览临时文件无需继续保留。
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [_pendingImages removeAllObjects];
    [self updateImagePreviews];
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (void)refreshAgentStateAndControls {
    _agentState.selectedSessionID = _selectedSession.sessionID ?: @"";
    _agentState.boundSessionID = _bridge.sessionID ?: @"";
    _agentState.bridgeRunning = _bridge.running;
    BOOL ready = _agentState.commandsEnabled;
    _composerTextView.editable = ready;
    _sendButton.enabled = ready;
    _imageButton.enabled = ready;
    _remoteButton.enabled = NO;
    _modelPicker.enabled = ready;

    NSString *ttyState = _bridge.running
        ? PTL(@"Terminal 已验证", @"Terminal verified")
        : PTL(@"未连接 Terminal", @"Terminal not connected");
    _inspectorConnectionLabel.stringValue = [NSString stringWithFormat:@"%@\n%@",
        ttyState, ready ? PTL(@"当前选中会话可发送", @"Selected conversation can send")
                        : PTL(@"只读，未绑定当前会话", @"Read only; conversation not bound")];
    _composerTargetLabel.stringValue = ready
        ? [NSString stringWithFormat:PTL(@"发送给：%@ · 可粘贴图片 · ↩ 发送，⌘↩ 换行", @"To: %@ · image paste · ↩ send, ⌘↩ newline"),
            _selectedSession.title ?: PTL(@"当前会话", @"Current conversation")]
        : PTL(@"只读 · 请先同步当前选中的 Terminal 会话", @"Read only · sync the selected Terminal conversation first");
    _bottomStatusLabel.stringValue = ready
        ? [NSString stringWithFormat:PTL(@"● 已连接 · %@ · 等待操作 · Terminal 是唯一执行引擎", @"● Connected · %@ · ready · Terminal is the sole execution engine"),
            _selectedSession.title ?: PTL(@"当前会话", @"Current conversation")]
        : PTL(@"○ 只读 · 当前会话未绑定 · Terminal 是唯一执行引擎", @"○ Read only · conversation not bound · Terminal is the sole execution engine");
    [self updateFloatingComposerState];
}

- (void)updateFloatingComposerState {
    if (!_floatingComposerTextView || !_floatingSendButton) return;
    PTSessionInfo *session = [self sessionWithID:_floatingSessionID];
    BOOL ready = _floatingPanel.visible && _bridge.running && !_agentState.sendInFlight &&
        _floatingSessionID.length > 0 && [_bridge.sessionID isEqual:_floatingSessionID];
    _floatingComposerTextView.editable = ready;
    _floatingSendButton.enabled = ready;
    _floatingImageButton.enabled = ready;
    if (ready) {
        _floatingComposerLabel.stringValue = [NSString stringWithFormat:
            PTL(@"发送给：%@ · 可粘贴图片 · ↩ 发送，⌘↩ 换行", @"To: %@ · image paste · ↩ send, ⌘↩ newline"),
            session.title ?: PTL(@"悬浮会话", @"Floating conversation")];
    } else if (_agentState.sendInFlight && [_bridge.sessionID isEqual:_floatingSessionID]) {
        _floatingComposerLabel.stringValue = PTL(@"正在写入 Terminal…", @"Writing to Terminal…");
    } else {
        _floatingComposerLabel.stringValue = PTL(@"未同步此会话 · 请先在主窗口同步后发送", @"Conversation not synced · sync it in the main window before sending");
    }
}

- (void)updateFloatingTitleForSession:(PTSessionInfo *)session {
    if (!_floatingPanel || !session) return;
    NSString *quota = _planUsageAvailable
        ? [NSString stringWithFormat:@"5h %.0f%% · 7d %.0f%%", _fiveHourPercent, _sevenDayPercent]
        : @"额度 —";
    NSString *cost = session.apiCostAvailable
        ? [NSString stringWithFormat:@"API≈%@", PTAPIEquivalentCostDisplay(session.apiEquivalentCostUSD)]
        : @"API≈—";
    _floatingPanel.title = [NSString stringWithFormat:@"%@ · %@ · %@",
        session.title ?: @"悬浮对话", quota, cost];
}

- (void)updateUsageDisplays {
    if (_planUsageAvailable) {
        _quotaLabel.stringValue = [NSString stringWithFormat:@"5h %.0f%% · 7d %.0f%%",
            _fiveHourPercent, _sevenDayPercent];
        _quotaLabel.textColor = MAX(_fiveHourPercent, _sevenDayPercent) >= 80.0
            ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
        NSString *fiveReset = PTResetDescription(_fiveHourResetAt, NSDate.date);
        NSString *sevenReset = PTResetDescription(_sevenDayResetAt, NSDate.date);
        _quotaLabel.toolTip = [NSString stringWithFormat:
            @"5 小时：%.0f%%，%@\n7 天：%.0f%%，%@\n每 60 秒更新",
            _fiveHourPercent, fiveReset, _sevenDayPercent, sevenReset];
        _inspectorQuotaLabel.stringValue = [NSString stringWithFormat:
            @"5 小时 %.0f%% · %@\n7 天 %.0f%% · %@",
            _fiveHourPercent, fiveReset, _sevenDayPercent, sevenReset];
    } else {
        _quotaLabel.stringValue = @"5h — · 7d —";
        _quotaLabel.textColor = NSColor.secondaryLabelColor;
        NSString *reason = _planUsageError.length ? _planUsageError : @"正在读取 Claude 套餐额度";
        _quotaLabel.toolTip = reason;
        _inspectorQuotaLabel.stringValue = [NSString stringWithFormat:@"暂不可用\n%@", reason];
    }

    if (_selectedSession.apiCostAvailable) {
        _inspectorCostLabel.stringValue = [NSString stringWithFormat:@"≈ %@\n按官方 API 单价估算\n非订阅实际扣款",
            PTAPIEquivalentCostDisplay(_selectedSession.apiEquivalentCostUSD)];
    } else {
        _inspectorCostLabel.stringValue = @"暂无可计价 usage\n仅作 API 等价估算";
    }

    if (_floatingPanel.visible && _floatingSessionID.length) {
        [self updateFloatingTitleForSession:[self sessionWithID:_floatingSessionID]];
    }
}

- (void)finishClaudeUsageWithPayload:(NSDictionary *)payload error:(NSString *)errorMessage {
    _usageFetchInFlight = NO;
    NSDictionary *fiveHour = [payload[@"five_hour"] isKindOfClass:NSDictionary.class]
        ? payload[@"five_hour"] : nil;
    NSDictionary *sevenDay = [payload[@"seven_day"] isKindOfClass:NSDictionary.class]
        ? payload[@"seven_day"] : nil;
    NSNumber *fiveValue = [fiveHour[@"utilization"] isKindOfClass:NSNumber.class]
        ? fiveHour[@"utilization"] : nil;
    NSNumber *sevenValue = [sevenDay[@"utilization"] isKindOfClass:NSNumber.class]
        ? sevenDay[@"utilization"] : nil;
    if (fiveValue && sevenValue) {
        _planUsageAvailable = YES;
        _fiveHourPercent = MIN(100.0, MAX(0.0, fiveValue.doubleValue));
        _sevenDayPercent = MIN(100.0, MAX(0.0, sevenValue.doubleValue));
        _fiveHourResetAt = PTDateFromClaudeAPIString(fiveHour[@"resets_at"]);
        _sevenDayResetAt = PTDateFromClaudeAPIString(sevenDay[@"resets_at"]);
        _planUsageFetchedAt = NSDate.date;
        _planUsageError = nil;
    } else if (!_planUsageAvailable) {
        _planUsageError = errorMessage.length ? errorMessage : @"Claude 未返回额度字段";
    } else {
        _planUsageError = errorMessage;
    }
    [self updateUsageDisplays];
}

- (void)refreshClaudeUsage:(id)sender {
    (void)sender;
    if (_usageFetchInFlight) return;
    _usageFetchInFlight = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *keychainError = nil;
        NSData *credentialData = PTClaudeCredentialData(&keychainError);
        NSDictionary *credentials = credentialData
            ? [NSJSONSerialization JSONObjectWithData:credentialData options:0 error:nil] : nil;
        NSDictionary *oauth = [credentials[@"claudeAiOauth"] isKindOfClass:NSDictionary.class]
            ? credentials[@"claudeAiOauth"] : nil;
        NSString *token = [oauth[@"accessToken"] isKindOfClass:NSString.class]
            ? oauth[@"accessToken"] : @"";
        if (token.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishClaudeUsageWithPayload:nil error:keychainError.localizedDescription
                    ?: @"未读取到 Claude Code 登录凭据"];
            });
            return;
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:@"https://api.anthropic.com/api/oauth/usage"]];
        request.HTTPMethod = @"GET";
        request.timeoutInterval = 15.0;
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [request setValue:@"oauth-2025-04-20" forHTTPHeaderField:@"anthropic-beta"];
        [request setValue:@"claude-code/2.1.226" forHTTPHeaderField:@"User-Agent"];
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:
          ^(NSData *data, NSURLResponse *response, NSError *networkError) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class]
                ? (NSHTTPURLResponse *)response : nil;
            NSDictionary *payload = data
                ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *message = nil;
            if (networkError) message = @"额度服务暂时不可达";
            else if (http.statusCode == 401 || http.statusCode == 403) message = @"Claude 凭据需刷新";
            else if (http.statusCode != 200) message = [NSString stringWithFormat:@"额度服务返回 %ld", (long)http.statusCode];
            else if (![payload isKindOfClass:NSDictionary.class]) message = @"额度响应格式异常";
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishClaudeUsageWithPayload:payload error:message];
            });
        }] resume];
    });
}

- (void)reloadGitDirectoryPickerSelecting:(NSString *)selectedPath {
    [_gitDirectoryPicker removeAllItems];
    for (NSString *path in _gitDirectoryPaths ?: @[]) {
        NSString *name = path.lastPathComponent.length ? path.lastPathComponent : path;
        [_gitDirectoryPicker addItemWithTitle:name];
        NSMenuItem *item = _gitDirectoryPicker.lastItem;
        item.representedObject = path;
        item.toolTip = path;
    }
    _gitDirectoryPicker.enabled = _gitDirectoryPaths.count > 0;
    _removeGitDirectoryButton.enabled = _gitDirectoryPaths.count > 0;
    _gitPublishButton.enabled = _gitDirectoryPaths.count > 0 && !_gitActionInFlight;
    if (_gitDirectoryPaths.count == 0) {
        [_gitDirectoryPicker addItemWithTitle:PTL(@"尚未发现目录", @"No directory found")];
        _gitObservedDirectory = nil;
        return;
    }
    NSUInteger selectedIndex = [_gitDirectoryPaths indexOfObject:selectedPath];
    if (selectedIndex == NSNotFound) selectedIndex = 0;
    [_gitDirectoryPicker selectItemAtIndex:selectedIndex];
    _gitObservedDirectory = [_gitDirectoryPaths[selectedIndex] copy];
}

- (void)rememberGitDirectoriesForSession:(PTSessionInfo *)session {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    for (NSString *path in session.accessedDirectories ?: @[]) {
        if ([path isKindOfClass:NSString.class] && [path hasPrefix:@"/"] &&
            ![_gitDirectoriesSuppressedUntilSessionChange containsObject:path]) {
            [paths addObject:path];
        }
    }
    if (session.cwd.length > 0 && [session.cwd hasPrefix:@"/"] &&
        ![_gitDirectoriesSuppressedUntilSessionChange containsObject:session.cwd]) {
        [paths addObject:session.cwd];
    }
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:@"PTGitObservedDirectories"];
    for (id value in stored ?: @[]) {
        if ([value isKindOfClass:NSString.class] && [value hasPrefix:@"/"]) [paths addObject:value];
    }
    NSArray<NSString *> *nextPaths = paths.array;
    NSString *preferred = _gitObservedDirectory;
    if (!_gitDirectoryManuallySelected && !_gitObservedDirectory.length) {
        preferred = session.accessedDirectories.lastObject ?: session.cwd;
    }
    if (![_gitDirectoryPaths isEqualToArray:nextPaths]) {
        _gitDirectoryPaths = [nextPaths mutableCopy];
        [NSUserDefaults.standardUserDefaults setObject:nextPaths forKey:@"PTGitObservedDirectories"];
        [self reloadGitDirectoryPickerSelecting:preferred];
    } else if (!_gitObservedDirectory.length && nextPaths.count > 0) {
        [self reloadGitDirectoryPickerSelecting:preferred];
    }
}

- (void)allowRediscoveryOfGitDirectoriesForNewSession {
    [_gitDirectoriesSuppressedUntilSessionChange removeAllObjects];
}

- (void)resizeInspectorToWidth:(CGFloat)requestedWidth {
    if (_splitView.subviews.count < 3) return;
    CGFloat totalWidth = NSWidth(_splitView.bounds);
    CGFloat sidebarWidth = NSWidth(_splitView.subviews[0].frame);
    CGFloat maximumWidth = MAX(210.0, totalWidth - sidebarWidth - 480.0 - (_splitView.dividerThickness * 2.0));
    CGFloat width = MIN(MIN(720.0, maximumWidth), MAX(210.0, requestedWidth));
    _inspectorWidthConstraint.active = NO;
    [_splitView setPosition:totalWidth - width - _splitView.dividerThickness ofDividerAtIndex:1];
    [_window.contentView layoutSubtreeIfNeeded];
    CGFloat actualWidth = NSWidth(_inspectorView.frame);
    _inspectorWidthConstraint.constant = actualWidth > 0 ? actualWidth : width;
    _inspectorWidthConstraint.active = YES;
}

- (void)gitDirectorySelectionChanged:(id)sender {
    (void)sender;
    NSString *path = [_gitDirectoryPicker.selectedItem.representedObject isKindOfClass:NSString.class]
        ? _gitDirectoryPicker.selectedItem.representedObject : @"";
    if (path.length == 0) return;
    _gitObservedDirectory = [path copy];
    _gitDirectoryManuallySelected = YES;
    _statusLabel.stringValue = PTL(@"已切换 PrettyTerm 的 Git 观察目录；Claude Code 目录未改变", @"PrettyTerm's Git directory changed; Claude Code's directory did not");
    _bottomStatusLabel.stringValue = PTL(@"Git 观察目录已切换 · Claude Code 如需访问，请执行 /add-dir", @"Git observation changed · run /add-dir if Claude Code needs access");
    if (_gitDiffExpanded && !_gitReviewShowsTranscriptEdits) [self refreshGitDiff:nil];
}

- (void)addManualGitDirectory:(id)sender {
    (void)sender;
    NSString *rawPath = [_gitDirectoryInput.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *path = rawPath.stringByExpandingTildeInPath.stringByStandardizingPath;
    BOOL isDirectory = NO;
    BOOL valid = path.length > 0 && [path hasPrefix:@"/"] &&
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory;
    if (!valid) {
        _statusLabel.stringValue = PTL(@"请输入存在的绝对文件夹路径", @"Enter an existing absolute folder path");
        return;
    }
    if (!_gitDirectoryPaths) _gitDirectoryPaths = [NSMutableArray array];
    [_gitDirectoriesSuppressedUntilSessionChange removeObject:path];
    if (![_gitDirectoryPaths containsObject:path]) [_gitDirectoryPaths insertObject:path atIndex:0];
    _gitObservedDirectory = [path copy];
    _gitDirectoryManuallySelected = YES;
    [NSUserDefaults.standardUserDefaults setObject:_gitDirectoryPaths forKey:@"PTGitObservedDirectories"];
    [self reloadGitDirectoryPickerSelecting:path];
    _gitDirectoryInput.stringValue = @"";
    _statusLabel.stringValue = PTL(@"已添加 Git 观察目录；这不会改变 Claude Code 的目录", @"Git observation directory added; Claude Code's directory is unchanged");
    _bottomStatusLabel.stringValue = [NSString stringWithFormat:PTL(@"如需 Claude 访问，请在 Claude Code 执行 /add-dir %@", @"To give Claude access, run /add-dir %@ in Claude Code"), path];
    if (_gitDiffExpanded && !_gitReviewShowsTranscriptEdits) [self refreshGitDiff:nil];
}

- (void)removeSelectedGitDirectory:(id)sender {
    (void)sender;
    NSString *path = [_gitDirectoryPicker.selectedItem.representedObject
        isKindOfClass:NSString.class] ? _gitDirectoryPicker.selectedItem.representedObject : @"";
    NSUInteger removedIndex = [_gitDirectoryPaths indexOfObject:path];
    if (path.length == 0 || removedIndex == NSNotFound) return;

    if (!_gitDirectoriesSuppressedUntilSessionChange) {
        _gitDirectoriesSuppressedUntilSessionChange = [NSMutableSet set];
    }
    [_gitDirectoriesSuppressedUntilSessionChange addObject:path];
    [_gitDirectoryPaths removeObjectAtIndex:removedIndex];
    [NSUserDefaults.standardUserDefaults setObject:_gitDirectoryPaths
        forKey:@"PTGitObservedDirectories"];

    NSString *fallback = @"";
    if (_gitDirectoryPaths.count > 0) {
        NSUInteger fallbackIndex = MIN(removedIndex, _gitDirectoryPaths.count - 1);
        fallback = _gitDirectoryPaths[fallbackIndex];
    }
    _gitObservedDirectory = nil;
    _gitDirectoryManuallySelected = fallback.length > 0;
    [self reloadGitDirectoryPickerSelecting:fallback];

    if (_gitDirectoryPaths.count == 0 && !_gitReviewShowsTranscriptEdits) {
        _gitDiffGeneration++;
        [self replaceGitReviewDocument:[self gitReviewDocumentForSnapshot:@{
            @"error": PTL(@"尚未选择 Git 观察目录。", @"No Git observation directory is selected.")
        }] animated:_gitDiffExpanded];
        _gitDiffRefreshButton.enabled = NO;
    } else if (_gitDiffExpanded && !_gitReviewShowsTranscriptEdits) {
        [self refreshGitDiff:nil];
    }
    _statusLabel.stringValue = [NSString stringWithFormat:
        PTL(@"已从 PrettyTerm 记忆中删除 %@", @"Removed %@ from PrettyTerm memory"), path.lastPathComponent ?: path];
    _bottomStatusLabel.stringValue = PTL(
        @"重新打开相关对话或手动添加即可恢复 · Claude Code 目录未改变",
        @"Reopen the related conversation or add it manually to restore it · Claude Code is unchanged");
}

- (void)buildGitActionPopoverIfNeeded {
    if (_gitActionPopover) return;
    _gitActionPopover = [[NSPopover alloc] init];
    _gitActionPopover.behavior = NSPopoverBehaviorTransient;
    _gitActionPopover.contentSize = NSMakeSize(360, 300);

    NSViewController *controller = [[NSViewController alloc] init];
    PTAppearanceSurfaceView *surface = [[PTAppearanceSurfaceView alloc]
        initWithFrame:NSMakeRect(0, 0, 360, 300)];
    surface.surfaceStyle = PTAppearanceSurfaceStyleCard;
    controller.view = surface;
    _gitActionPopover.contentViewController = controller;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    [surface addSubview:stack];

    _gitActionBranchLabel = [self label:PTL(@"⌘ 读取当前分支…", @"⌘ Reading current branch…") size:13
        weight:NSFontWeightSemibold color:NSColor.labelColor];
    [stack addArrangedSubview:_gitActionBranchLabel];

    _gitCommitMessageField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _gitCommitMessageField.translatesAutoresizingMaskIntoConstraints = NO;
    _gitCommitMessageField.placeholderString = PTL(@"提交信息（必须手动填写）", @"Commit message (manual entry required)");
    _gitCommitMessageField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    _gitCommitMessageField.delegate = self;
    [stack addArrangedSubview:_gitCommitMessageField];

    _gitIncludeUnstagedButton = [NSButton checkboxWithTitle:@""
        target:nil action:nil];
    _gitIncludeUnstagedButton.translatesAutoresizingMaskIntoConstraints = NO;
    _gitIncludeUnstagedButton.state = NSControlStateValueOn;
    _gitIncludeUnstagedButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    _gitIncludeUnstagedButton.contentTintColor = PTWarmAccentColor();
    NSStackView *unstagedRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    unstagedRow.translatesAutoresizingMaskIntoConstraints = NO;
    unstagedRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    unstagedRow.alignment = NSLayoutAttributeCenterY;
    unstagedRow.spacing = 5;
    NSTextField *unstagedLabel = [self label:PTL(@"包含未暂存的更改", @"Include unstaged changes") size:11.5
        weight:NSFontWeightMedium color:NSColor.labelColor];
    [unstagedRow addArrangedSubview:_gitIncludeUnstagedButton];
    [unstagedRow addArrangedSubview:unstagedLabel];
    [stack addArrangedSubview:unstagedRow];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];

    _gitCommitButton = [NSButton buttonWithTitle:PTL(@"提交", @"Commit") target:self action:@selector(commitGitChanges:)];
    _gitCommitAndPushButton = [NSButton buttonWithTitle:PTL(@"提交并推送", @"Commit and Push")
        target:self action:@selector(commitAndPushGitChanges:)];
    _gitPushButton = [NSButton buttonWithTitle:PTL(@"推送", @"Push") target:self action:@selector(pushGitChanges:)];
    for (NSButton *button in @[_gitCommitButton, _gitCommitAndPushButton, _gitPushButton]) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.bezelStyle = NSBezelStyleRounded;
        button.alignment = NSTextAlignmentLeft;
        button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        button.contentTintColor = PTWarmAccentColor();
        [stack addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    _gitCommitButton.toolTip = PTL(@"只提交暂存区；勾选后会先暂存仓库内全部改动", @"Commit staged changes only; when checked, all repository changes are staged first");
    _gitCommitAndPushButton.toolTip = PTL(@"提交成功后再执行 git push", @"Run git push after a successful commit");
    _gitPushButton.toolTip = PTL(@"只推送已有提交，不会自动创建提交", @"Push existing commits only; never creates a commit automatically");

    NSStackView *statusRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    statusRow.translatesAutoresizingMaskIntoConstraints = NO;
    statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusRow.alignment = NSLayoutAttributeCenterY;
    statusRow.spacing = 7;
    _gitActionProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _gitActionProgress.translatesAutoresizingMaskIntoConstraints = NO;
    _gitActionProgress.style = NSProgressIndicatorStyleSpinning;
    _gitActionProgress.controlSize = NSControlSizeSmall;
    _gitActionProgress.displayedWhenStopped = NO;
    _gitActionProgress.hidden = YES;
    _gitActionStatusLabel = [self label:PTL(@"提交信息不会自动生成", @"Commit messages are never generated automatically") size:10
        weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    _gitActionStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [statusRow addArrangedSubview:_gitActionProgress];
    [statusRow addArrangedSubview:_gitActionStatusLabel];
    [stack addArrangedSubview:statusRow];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:surface.topAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-18],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:surface.bottomAnchor constant:-14],
        [_gitCommitMessageField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_gitActionProgress.widthAnchor constraintEqualToConstant:14],
        [_gitActionProgress.heightAnchor constraintEqualToConstant:14],
        [_gitActionStatusLabel.widthAnchor constraintLessThanOrEqualToConstant:300]
    ]];
}

- (void)updateGitActionControls {
    NSString *message = [_gitCommitMessageField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL canCommit = !_gitActionInFlight && _gitObservedDirectory.length > 0 && message.length > 0;
    _gitCommitButton.enabled = canCommit;
    _gitCommitAndPushButton.enabled = canCommit;
    _gitPushButton.enabled = !_gitActionInFlight && _gitObservedDirectory.length > 0;
    _gitCommitMessageField.enabled = !_gitActionInFlight;
    _gitIncludeUnstagedButton.enabled = !_gitActionInFlight;
    _gitPublishButton.enabled = !_gitActionInFlight && _gitObservedDirectory.length > 0;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _gitCommitMessageField) [self updateGitActionControls];
}

- (void)showGitActions:(id)sender {
    if (_gitObservedDirectory.length == 0) {
        _statusLabel.stringValue = PTL(@"请先选择 Git 观察目录", @"Select a Git observation directory first");
        return;
    }
    [self buildGitActionPopoverIfNeeded];
    _gitActionStatusLabel.stringValue = PTL(@"提交信息不会自动生成", @"Commit messages are never generated automatically");
    [self updateGitActionControls];
    [_gitActionPopover showRelativeToRect:[sender bounds]
                                   ofView:sender
                            preferredEdge:NSRectEdgeMaxY];
    [_gitCommitMessageField.window makeFirstResponder:_gitCommitMessageField];

    NSString *directory = [_gitObservedDirectory copy];
    _gitActionBranchLabel.stringValue = PTL(@"⌘ 读取当前分支…", @"⌘ Reading current branch…");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int status = 0;
        NSString *branch = [[PTRunGit(directory, @[@"branch", @"--show-current"], &status)
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![directory isEqual:self->_gitObservedDirectory]) return;
            self->_gitActionBranchLabel.stringValue = status == 0 && branch.length > 0
                ? [NSString stringWithFormat:@"⌘  %@", branch]
                : @"⌘  detached HEAD";
        });
    });
}

- (void)performGitCommit:(BOOL)commit push:(BOOL)push {
    if (_gitActionInFlight || _gitObservedDirectory.length == 0) return;
    NSString *message = [_gitCommitMessageField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (commit && message.length == 0) {
        _gitActionStatusLabel.stringValue = PTL(@"请手动填写提交信息", @"Enter a commit message manually");
        NSBeep();
        return;
    }

    NSString *directory = [_gitObservedDirectory copy];
    BOOL includeUnstaged = _gitIncludeUnstagedButton.state == NSControlStateValueOn;
    _gitActionInFlight = YES;
    _gitActionStatusLabel.stringValue = commit
        ? PTL(@"正在提交…", @"Committing…") : PTL(@"正在推送…", @"Pushing…");
    _gitActionProgress.hidden = NO;
    [_gitActionProgress startAnimation:nil];
    [self updateGitActionControls];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int status = 0;
        NSString *root = [[PTRunGit(directory, @[@"rev-parse", @"--show-toplevel"], &status)
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
        NSMutableArray<NSString *> *outputs = [NSMutableArray array];
        if (status != 0 && root.length) [outputs addObject:root];
        if (status == 0 && commit && includeUnstaged) {
            NSString *output = PTRunGit(root, @[@"add", @"-A", @"--", @"."], &status);
            if (output.length) [outputs addObject:output];
        }
        if (status == 0 && commit) {
            NSString *output = PTRunGit(root, @[@"commit", @"-m", message], &status);
            if (output.length) [outputs addObject:output];
        }
        if (status == 0 && push) {
            NSString *output = PTRunGit(root, @[@"push"], &status);
            if (output.length) [outputs addObject:output];
        }
        NSString *combined = [[outputs componentsJoinedByString:@"\n"]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (combined.length > 360) {
            NSRange tailRange = [combined rangeOfComposedCharacterSequencesForRange:
                NSMakeRange(combined.length - 360, 360)];
            combined = [[combined substringWithRange:tailRange]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
        NSString *success = commit && push
            ? PTL(@"提交并推送完成", @"Commit and push completed")
            : (commit ? PTL(@"提交完成", @"Commit completed") : PTL(@"推送完成", @"Push completed"));
        NSString *result = status == 0 ? success
            : (combined.length ? combined : PTL(@"Git 操作失败", @"Git operation failed"));
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_gitActionInFlight = NO;
            [self->_gitActionProgress stopAnimation:nil];
            self->_gitActionProgress.hidden = YES;
            self->_gitActionStatusLabel.stringValue = result;
            self->_gitActionStatusLabel.toolTip = combined;
            if (status == 0 && commit) self->_gitCommitMessageField.stringValue = @"";
            [self updateGitActionControls];
            self->_statusLabel.stringValue = result;
            self->_bottomStatusLabel.stringValue = result;
            if (self->_gitDiffExpanded && !self->_gitReviewShowsTranscriptEdits) {
                [self refreshGitDiff:nil];
            }
        });
    });
}

- (void)commitGitChanges:(id)sender {
    (void)sender;
    [self performGitCommit:YES push:NO];
}

- (void)commitAndPushGitChanges:(id)sender {
    (void)sender;
    [self performGitCommit:YES push:YES];
}

- (void)pushGitChanges:(id)sender {
    (void)sender;
    [self performGitCommit:NO push:YES];
}

- (void)toggleGitDiff:(id)sender {
    (void)sender;
    if (!_gitDiffExpanded && _gitObservedDirectory.length == 0) {
        _statusLabel.stringValue = PTL(@"请先选择或添加 Git 观察目录", @"Select or add a Git observation directory first");
        return;
    }
    _gitDiffExpanded = !_gitDiffExpanded;
    NSUInteger animationGeneration = ++_gitDiffAnimationGeneration;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    _gitDiffToggleButton.title = _gitDiffExpanded
        ? PTL(@"收起 Git 审阅  ‹", @"Collapse Git Review  ‹")
        : PTL(@"展开 Git 审阅  ›", @"Expand Git Review  ›");
    if (_gitDiffExpanded) {
        _gitReviewShowsTranscriptEdits = NO;
        _transcriptEditReviewEvents = nil;
        _gitDiffScroll.hidden = NO;
        _gitDiffRefreshButton.hidden = NO;
        _gitDiffScroll.alphaValue = reduceMotion ? 1.0 : 0.0;
        _inspectorWidthBeforeGitDiff = MAX(210.0, NSWidth(_inspectorView.frame));
        [self resizeInspectorToWidth:660.0];
        if (!reduceMotion) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.20;
                self->_gitDiffScroll.animator.alphaValue = 1.0;
            } completionHandler:nil];
        }
        [self refreshGitDiff:nil];
    } else {
        _gitReviewShowsTranscriptEdits = NO;
        _transcriptEditReviewEvents = nil;
        _gitDiffGeneration++;
        [_gitDiffProgress stopAnimation:nil];
        _gitDiffProgress.hidden = YES;
        _gitDiffRefreshButton.hidden = YES;
        [self resizeInspectorToWidth:_inspectorWidthBeforeGitDiff > 0 ? _inspectorWidthBeforeGitDiff : 260.0];
        if (reduceMotion) {
            _gitDiffScroll.hidden = YES;
            _gitDiffScroll.alphaValue = 1.0;
        } else {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.14;
                self->_gitDiffScroll.animator.alphaValue = 0.0;
            } completionHandler:^{
                if (animationGeneration != self->_gitDiffAnimationGeneration ||
                    self->_gitDiffExpanded) return;
                self->_gitDiffScroll.hidden = YES;
                self->_gitDiffScroll.alphaValue = 1.0;
            }];
        }
    }
}

- (NSAttributedString *)transcriptEditReviewDocumentForEvents:
    (NSArray<NSDictionary *> *)events {
    __block NSAttributedString *document = nil;
    [_gitDiffTextView.effectiveAppearance performAsCurrentDrawingAppearance:^{
        document = PTTranscriptEditReviewAttributedString(events ?: @[]);
    }];
    return document ?: [[NSAttributedString alloc] initWithString:@""];
}

- (void)showTranscriptEditReviewWithEvents:(NSArray<NSDictionary *> *)events {
    _gitDiffGeneration++;
    [_gitDiffProgress stopAnimation:nil];
    _gitDiffProgress.hidden = YES;
    _gitDiffRefreshButton.hidden = YES;
    _gitReviewShowsTranscriptEdits = YES;
    _transcriptEditReviewEvents = [events copy];
    _gitDiffToggleButton.title = PTL(@"收起本轮审阅  ‹", @"Collapse Turn Review  ‹");

    if (!_gitDiffExpanded) {
        _gitDiffExpanded = YES;
        ++_gitDiffAnimationGeneration;
        BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
        _gitDiffScroll.hidden = NO;
        _gitDiffScroll.alphaValue = reduceMotion ? 1.0 : 0.0;
        _inspectorWidthBeforeGitDiff = MAX(210.0, NSWidth(_inspectorView.frame));
        [self resizeInspectorToWidth:660.0];
        if (!reduceMotion) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.20;
                self->_gitDiffScroll.animator.alphaValue = 1.0;
            } completionHandler:nil];
        }
    }
    [self replaceGitReviewDocument:[self transcriptEditReviewDocumentForEvents:events]
                          animated:YES];
}

- (NSAttributedString *)gitReviewDocumentForSnapshot:
    (NSDictionary<NSString *, NSString *> *)snapshot {
    __block NSAttributedString *document = nil;
    [_gitDiffTextView.effectiveAppearance performAsCurrentDrawingAppearance:^{
        document = PTGitReviewAttributedString(snapshot);
    }];
    return document ?: [[NSAttributedString alloc] initWithString:@""];
}

- (void)replaceGitReviewDocument:(NSAttributedString *)document animated:(BOOL)animated {
    if (!document) return;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (!animated || reduceMotion || _gitDiffScroll.hidden) {
        [_gitDiffTextView.textStorage setAttributedString:document];
        _gitDiffTextView.alphaValue = 1.0;
        [_gitDiffTextView scrollRangeToVisible:NSMakeRange(0, 0)];
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.08;
        self->_gitDiffTextView.animator.alphaValue = 0.22;
    } completionHandler:^{
        [self->_gitDiffTextView.textStorage setAttributedString:document];
        [self->_gitDiffTextView scrollRangeToVisible:NSMakeRange(0, 0)];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.18;
            self->_gitDiffTextView.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }];
}

- (void)refreshGitDiff:(id)sender {
    (void)sender;
    NSString *directory = [_gitObservedDirectory copy];
    if (directory.length == 0) return;
    _gitReviewShowsTranscriptEdits = NO;
    _transcriptEditReviewEvents = nil;
    _gitDiffToggleButton.title = PTL(@"收起 Git 审阅  ‹", @"Collapse Git Review  ‹");
    NSUInteger generation = ++_gitDiffGeneration;
    _gitDiffRefreshButton.enabled = NO;
    _gitDiffProgress.hidden = NO;
    [_gitDiffProgress startAnimation:nil];
    if (_gitDiffTextView.string.length == 0 ||
        [_gitDiffTextView.string containsString:@"选择目录后"]) {
        [self replaceGitReviewDocument:PTGitReviewLoadingAttributedString() animated:NO];
    } else if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _gitDiffTextView.animator.alphaValue = 0.58;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary<NSString *, NSString *> *snapshot =
            PTGitReviewSnapshotForDirectory(directory);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_gitDiffGeneration ||
                ![directory isEqual:self->_gitObservedDirectory]) return;
            [self->_gitDiffProgress stopAnimation:nil];
            self->_gitDiffProgress.hidden = YES;
            self->_gitDiffRefreshButton.enabled = YES;
            [self replaceGitReviewDocument:[self gitReviewDocumentForSnapshot:snapshot]
                                  animated:YES];
        });
    });
}

- (void)updateInspectorForSession:(PTSessionInfo *)session {
    if (!session) return;
    [self rememberGitDirectoriesForSession:session];
    _inspectorContextLabel.stringValue = session.contextUsed > 0
        ? [NSString stringWithFormat:@"%@ / %@ tokens",
            PTCompactTokenCount(session.contextUsed), PTCompactTokenCount(session.contextWindow)]
        : @"暂无 usage 数据";
    [self updateUsageDisplays];

    NSArray<NSDictionary *> *changedFiles = session.changedFiles ?: @[];
    if (![_renderedChangedFiles isEqualToArray:changedFiles]) {
        _renderedChangedFiles = [changedFiles copy];
        if (changedFiles.count == 0) {
            for (NSView *view in _changedFilesStack.arrangedSubviews.copy) {
                [_changedFilesStack removeArrangedSubview:view];
                [view removeFromSuperview];
            }
            _changedFileButtonsByPath = @{};
            NSTextField *empty = [self label:PTL(@"本轮没有 Edit / Write 改动", @"No Edit / Write changes in this turn") size:10.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
            [_changedFilesStack addArrangedSubview:empty];
        } else {
            // 路径相同的按钮永不因 added/removed 数字变化而拆除；只更新其内容。
            // 这样 transcript 轮询恰好撞上 mouseDown/mouseUp 时，action 仍属于同一对象。
            for (NSView *view in _changedFilesStack.arrangedSubviews.copy) {
                if (![view isKindOfClass:PTFirstMouseButton.class]) {
                    [_changedFilesStack removeArrangedSubview:view];
                    [view removeFromSuperview];
                }
            }
            NSMutableDictionary<NSString *, PTFirstMouseButton *> *nextButtons =
                [NSMutableDictionary dictionary];
            NSUInteger fileIndex = 0;
            for (NSDictionary *file in changedFiles) {
                NSString *path = [file[@"filePath"] isKindOfClass:NSString.class]
                    ? file[@"filePath"] : @"";
                NSString *identity = path.length > 0 ? path : [NSString stringWithFormat:@"missing-path-%lu",
                    (unsigned long)fileIndex];
                PTFirstMouseButton *button = _changedFileButtonsByPath[identity];
                if (!button) {
                    button = [[PTFirstMouseButton alloc] initWithFrame:NSZeroRect];
                    button.target = self;
                    button.action = @selector(revealChangedFile:);
                    button.buttonType = NSButtonTypeMomentaryPushIn;
                    button.translatesAutoresizingMaskIntoConstraints = NO;
                    button.bezelStyle = NSBezelStyleRecessed;
                    button.alignment = NSTextAlignmentLeft;
                    button.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
                    [_changedFilesStack addArrangedSubview:button];
                    [button.widthAnchor constraintEqualToAnchor:_changedFilesStack.widthAnchor].active = YES;
                }
                NSString *title = [NSString stringWithFormat:@"%@    +%@  −%@  ↗",
                    file[@"displayName"] ?: @"文件", file[@"added"] ?: @0, file[@"removed"] ?: @0];
                button.title = title;
                button.toolTip = [NSString stringWithFormat:@"在 Finder 中显示\n%@", path];
                button.identifier = path;
                nextButtons[identity] = button;
                fileIndex++;
            }
            for (NSString *identity in _changedFileButtonsByPath) {
                if (nextButtons[identity]) continue;
                PTFirstMouseButton *button = _changedFileButtonsByPath[identity];
                [_changedFilesStack removeArrangedSubview:button];
                [button removeFromSuperview];
            }
            _changedFileButtonsByPath = nextButtons;
        }
    }

    // 任务也按值更新，避免每次 transcript 修订都重建整个检查器视图树。
    NSArray<NSDictionary *> *tasks = session.tasks ?: @[];
    if (![_renderedTasks isEqualToArray:tasks]) {
        _renderedTasks = [tasks copy];
        for (NSView *view in _tasksStack.arrangedSubviews.copy) {
            [_tasksStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }
        if (tasks.count == 0) {
            NSTextField *empty = [self label:PTL(@"当前会话没有任务", @"No tasks in this conversation") size:10.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
            [_tasksStack addArrangedSubview:empty];
        } else {
            for (NSDictionary *task in tasks) {
                NSString *status = [task[@"status"] isKindOfClass:NSString.class] ? task[@"status"] : @"pending";
                NSString *statusEmoji = @"⚪️";
                NSColor *statusColor = NSColor.secondaryLabelColor;
                if ([status isEqual:@"in_progress"]) {
                    statusEmoji = @"🔵";
                    statusColor = PTColor(0.0, 0.48, 0.99);
                } else if ([status isEqual:@"completed"]) {
                    statusEmoji = @"✅";
                    statusColor = PTColor(0.20, 0.78, 0.35);
                }
                NSString *taskID = [task[@"id"] isKindOfClass:NSString.class] ? task[@"id"] : @"?";
                NSString *subject = [task[@"subject"] isKindOfClass:NSString.class] ? task[@"subject"] : @"未命名任务";
                NSString *title = [NSString stringWithFormat:@"%@ #%@ %@", statusEmoji, taskID, subject];
                NSTextField *label = [self label:title size:10.5 weight:NSFontWeightMedium color:statusColor];
                label.lineBreakMode = NSLineBreakByTruncatingTail;
                [_tasksStack addArrangedSubview:label];
                [label.widthAnchor constraintEqualToAnchor:_tasksStack.widthAnchor].active = YES;
            }
        }
    }
}

- (void)toggleInspector:(id)sender {
    _inspectorView.hidden = !_inspectorView.hidden;
    _inspectorToggleButton.title = _inspectorView.hidden
        ? PTL(@"显示", @"Show") : PTL(@"检查器", @"Inspect");
}

- (NSArray<NSDictionary *> *)transcriptEditEventsForSession:(PTSessionInfo *)session
                                                   turnIndex:(NSUInteger)turnIndex {
    NSMutableArray<NSDictionary *> *edits = [NSMutableArray array];
    NSInteger currentTurn = -1;
    for (NSDictionary *event in session.assistantMessages ?: @[]) {
        BOOL isUser = [event[@"role"] isEqual:@"user"];
        if (isUser) {
            currentTurn++;
            continue;
        }
        if (currentTurn < 0) currentTurn = 0;
        if ((NSUInteger)currentTurn == turnIndex && [event[@"kind"] isEqual:@"diff"]) {
            [edits addObject:event];
        }
    }
    return edits;
}

- (void)openTranscriptEditReviewForSessionID:(NSString *)sessionID
                                    turnIndex:(NSUInteger)turnIndex {
    if (sessionID.length == 0) return;
    if (![_selectedSession.sessionID isEqual:sessionID]) {
        NSInteger matchingRow = NSNotFound;
        for (NSInteger index = 0; index < (NSInteger)_sessions.count; index++) {
            if ([_sessions[index].sessionID isEqual:sessionID]) {
                matchingRow = index;
                break;
            }
        }
        if (matchingRow == NSNotFound) return;
        [_sessionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:matchingRow]
                     byExtendingSelection:NO];
        _selectedSession = _sessions[matchingRow];
        [self showSelectedSession];
    }

    NSArray<NSDictionary *> *events = [self transcriptEditEventsForSession:_selectedSession
                                                                  turnIndex:turnIndex];
    if (events.count == 0) {
        _statusLabel.stringValue = PTL(@"这个回合没有可审阅的 Edit / Write 记录", @"This turn has no recorded Edit / Write changes to review");
        return;
    }

    _inspectorView.hidden = NO;
    _inspectorToggleButton.title = PTL(@"检查器", @"Inspect");
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self showTranscriptEditReviewWithEvents:events];
    _statusLabel.stringValue = PTL(@"正在显示本轮已记录的本地修改 · 未执行 git diff", @"Showing recorded local changes for this turn · git diff was not run");
}

- (void)revealChangedFile:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    BOOL directory = NO;
    BOOL exists = path.length > 0 &&
        [path hasPrefix:@"/"] &&
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory];
    if (!exists || directory) {
        _statusLabel.stringValue = PTL(@"文件已移动或不存在，无法在 Finder 中显示", @"The file moved or no longer exists, so Finder cannot reveal it");
        _bottomStatusLabel.stringValue = [NSString stringWithFormat:PTL(@"⚠ Finder 定位失败 · %@", @"⚠ Finder reveal failed · %@"), path.lastPathComponent ?: PTL(@"未知文件", @"Unknown file")];
        return;
    }
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
    _statusLabel.stringValue = [NSString stringWithFormat:PTL(@"已在 Finder 中显示 %@", @"Revealed %@ in Finder"), path.lastPathComponent];
}

- (void)updateContextAndModelForSession:(PTSessionInfo *)session {
    if (!session) return;
    NSUInteger window = session.contextWindow;
    NSUInteger used = session.contextUsed;
    if (used > 0 && window > 0) {
        double ratio = MIN(1.0, (double)used / (double)window);
        _contextBar.doubleValue = ratio;
        _contextLabel.stringValue = [NSString stringWithFormat:@"ctx %.0f%% · %@/%@",
            ratio * 100.0, PTCompactTokenCount(used), PTCompactTokenCount(window)];
        _contextBar.toolTip = [NSString stringWithFormat:@"最近一次调用占用 %lu / %lu tokens",
            (unsigned long)used, (unsigned long)window];
    } else {
        _contextBar.doubleValue = 0;
        _contextLabel.stringValue = @"ctx —";
        _contextBar.toolTip = @"该会话尚无 usage 数据";
    }

    NSInteger selectedIndex = 0;
    for (NSInteger index = 1; index < _modelPicker.numberOfItems; index++) {
        if ([[_modelPicker itemAtIndex:index].representedObject isEqual:session.model]) {
            selectedIndex = index;
            break;
        }
    }
    [_modelPicker selectItemAtIndex:selectedIndex];
    _modelPicker.itemArray.firstObject.title = session.model.length
        ? [NSString stringWithFormat:PTL(@"当前 · %@", @"Current · %@"), session.model]
        : PTL(@"当前模型", @"Current model");
}

- (void)connectStoreAndBridge {
    _store = [[PTSessionStore alloc] init];
    _bridge = [[PTClaudeBridge alloc] init];
    __weak typeof(self) weakSelf = self;
    _store.sessionsChanged = ^(NSArray<PTSessionInfo *> *sessions) {
        [weakSelf applySessions:sessions];
    };
    _store.globalModelChanged = ^(NSString *model) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        if (self->_selectedSession && self->_bridge.running &&
            [self->_bridge.sessionID isEqual:self->_selectedSession.sessionID]) {
            self->_selectedSession.model = model;
            [self updateContextAndModelForSession:self->_selectedSession];
            self->_statusLabel.stringValue = [NSString stringWithFormat:PTL(@"检测到模型切换：%@", @"Model switch detected: %@"), model];
        }
    };
    _bridge.statusChanged = ^(NSString *status) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        self->_statusLabel.stringValue = status;
        self->_connecting = NO;
        self->_agentState.sendInFlight = NO;
        [self refreshAgentStateAndControls];
        [self updateConnectButtonTitle];
    };
    _bridge.outputObserved = ^(NSString *chunk) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        if ([chunk containsString:@"Remote Control"] && [chunk containsString:@"http"]) {
            self->_statusLabel.stringValue = PTL(@"官方 Remote Control 已启用", @"Official Remote Control is enabled");
        }
    };
    [_store startWatchingGlobalSettings];
}

- (void)applySessions:(NSArray<PTSessionInfo *> *)sessions {
    NSMutableArray<NSString *> *signatureParts = [NSMutableArray arrayWithCapacity:sessions.count];
    for (PTSessionInfo *session in sessions) {
        [signatureParts addObject:[NSString stringWithFormat:@"%@|%.6f|%lu|%@",
            session.sessionID,
            session.modifiedAt.timeIntervalSince1970,
            (unsigned long)session.assistantMessages.count,
            session.title]];
    }
    NSString *signature = [signatureParts componentsJoinedByString:@"\n"];
    BOOL manualRefresh = _manualRefreshSessionID.length > 0;
    if ([_sessionListSignature isEqual:signature] && !manualRefresh) return;
    _sessionListSignature = signature;

    NSString *selectedID = _selectedSession.sessionID;
    _sessions = sessions;
    [_sessionTable reloadData];

    NSInteger selectedRow = NSNotFound;
    if (selectedID.length) {
        for (NSInteger index = 0; index < (NSInteger)sessions.count; index++) {
            if ([sessions[index].sessionID isEqual:selectedID]) {
                selectedRow = index;
                break;
            }
        }
    }
    if (selectedRow == NSNotFound && sessions.count > 0) selectedRow = 0;
    if (selectedRow != NSNotFound) {
        [_sessionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
        _selectedSession = sessions[selectedRow];
        if (manualRefresh && [_manualRefreshSessionID isEqual:_selectedSession.sessionID]) {
            _renderedSessionID = nil;
            _renderedModifiedAt = nil;
            _renderedMessageCount = 0;
        }
        [self showSelectedSession];
    }
    if (manualRefresh && [_manualRefreshSessionID isEqual:_floatingSessionID]) {
        _floatingRenderedSessionID = nil;
        _floatingRenderedModifiedAt = nil;
        _floatingRenderedMessageCount = 0;
    }
    [self refreshFloatingConversation];
    [self updateFloatingControls];
    _manualRefreshSessionID = nil;
    if (!_bridge.running) {
        _statusLabel.stringValue = [NSString stringWithFormat:PTL(@"已发现 %lu 个本地会话", @"Found %lu local conversations"), (unsigned long)sessions.count];
    }
}

- (void)showSelectedSession {
    if (!_selectedSession) return;
    [self watchSelectedSessionTranscript];
    _conversationTitle.stringValue = _selectedSession.title ?: PTL(@"未命名会话", @"Untitled conversation");
    NSString *folder = _selectedSession.cwd.lastPathComponent.length ? _selectedSession.cwd.lastPathComponent : _selectedSession.cwd;
    NSString *model = _selectedSession.model.length ? _selectedSession.model : @"Claude";
    _conversationDetail.stringValue = [NSString stringWithFormat:PTL(@"%@ · %@ · %lu 条消息", @"%@ · %@ · %lu messages"),
        folder.length ? folder : PTL(@"未知目录", @"Unknown directory"), model,
        (unsigned long)_selectedSession.assistantMessages.count];
    _connectButton.enabled = YES;
    [self updateContextAndModelForSession:_selectedSession];
    [self updateInspectorForSession:_selectedSession];
    [self refreshAgentStateAndControls];
    [self renderSession:_selectedSession];
    [self updateFloatingControls];
}

- (void)watchSelectedSessionTranscript {
    NSString *path = _selectedSession.filePath ?: @"";
    if ([_watchedTranscriptPath isEqual:path]) return;
    [_transcriptWatcher stopWatching];
    _watchedTranscriptPath = [path copy];
    if (path.length == 0) return;

    __weak typeof(self) weakSelf = self;
    [_transcriptWatcher watchFileAtPath:path onChange:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            PTAppDelegate *self = weakSelf;
            if (!self || ![self->_watchedTranscriptPath isEqual:path]) return;
            [self->_store refresh];
        });
    }];
}

// 被 applySessions（每 1.5 秒一次）和 tableViewSelectionDidChange 双双调用到。
// JSONL 只追加新消息时走 DOM 增量追加，保留老师展开的 details、选区和滚动位置；
// 切换会话、消息数回退或同数量内容修订时才用完整快照校正状态。
- (void)renderSession:(PTSessionInfo *)session {
    if (!_webReady || !session) return;
    if (_renderInFlight) {
        if (!_pendingRenderSession ||
            ![_pendingRenderSession.sessionID isEqual:session.sessionID] ||
            [_pendingRenderSession.modifiedAt compare:session.modifiedAt] != NSOrderedDescending) {
            _pendingRenderSession = session;
        }
        return;
    }
    NSUInteger messageCount = session.assistantMessages.count;
    if (!PTSessionRenderNeedsUpdate(
        _renderedSessionID,
        _renderedModifiedAt,
        _renderedMessageCount,
        session.sessionID,
        session.modifiedAt,
        messageCount
    )) return;

    NSDictionary *payload = @{
        @"sessionId": session.sessionID ?: @"",
        @"title": session.title ?: @"未命名会话",
        @"cwd": session.cwd ?: @"",
        @"model": session.model ?: @"Claude",
        @"interfaceLanguage": PTInterfaceLanguageCode(),
        @"messages": session.assistantMessages ?: @[]
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!jsonData) return;
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (!json) return;
    BOOL canAppend = [_renderedSessionID isEqual:session.sessionID] &&
        _renderedModifiedAt != nil && _renderedMessageCount < messageCount;
    NSString *script = nil;
    if (canAppend) {
        NSArray *incoming = [session.assistantMessages subarrayWithRange:
            NSMakeRange(_renderedMessageCount, messageCount - _renderedMessageCount)];
        NSData *incomingData = [NSJSONSerialization dataWithJSONObject:incoming options:0 error:nil];
        NSString *incomingJSON = incomingData
            ? [[NSString alloc] initWithData:incomingData encoding:NSUTF8StringEncoding] : nil;
        if (incomingJSON) {
            script = [NSString stringWithFormat:
                @"window.appendClaudeMessages(%@, %@); null;", json, incomingJSON];
        }
    }
    if (!script) script = [NSString stringWithFormat:@"window.setClaudeSession(%@); null;", json];

    _renderInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [_conversationView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        self->_renderInFlight = NO;
        if (error) {
            self->_renderedSessionID = nil;
            self->_renderedMessageCount = 0;
            self->_renderedModifiedAt = nil;
            self->_statusLabel.stringValue = PTL(@"显示更新失败，正在重新同步完整会话…", @"Display update failed; resyncing the full conversation…");
        } else {
            self->_renderedSessionID = session.sessionID;
            self->_renderedMessageCount = messageCount;
            self->_renderedModifiedAt = session.modifiedAt;
            self->_renderRetrying = NO;
        }

        self->_pendingRenderSession = nil;
        PTSessionInfo *latest = self->_selectedSession;
        if (latest) {
            [self renderSession:latest];
        } else if (error && !self->_renderRetrying) {
            self->_renderRetrying = YES;
            [self renderSession:session];
        }
    }];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return _sessions.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    PTSessionCellView *cell = [tableView makeViewWithIdentifier:@"PTSessionCell" owner:self];
    if (!cell) {
        cell = [[PTSessionCellView alloc] initWithFrame:NSMakeRect(0, 0, 260, 62)];
        cell.identifier = @"PTSessionCell";
    }
    [cell configure:_sessions[row]];
    return cell;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    PTSessionRowView *rowView = [tableView makeViewWithIdentifier:@"PTSessionRow" owner:self];
    if (!rowView) {
        rowView = [[PTSessionRowView alloc] initWithFrame:NSZeroRect];
        rowView.identifier = @"PTSessionRow";
    }
    return rowView;
}

// 右键菜单只对 clickedRow 生效，不改选中项——老师可能只想看看某个会话的文件在哪，
// 不希望右键顺手把正在同步的会话切走。行号会被 1.5 秒一次的 applySessions 打乱，
// 所以路径在菜单弹出时就固化进 representedObject，回调时不再按行号回查。
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _sessionTable.menu) return;
    [menu removeAllItems];
    NSInteger row = _sessionTable.clickedRow;
    if (row < 0 || row >= (NSInteger)_sessions.count) return;

    PTSessionInfo *session = _sessions[row];
    NSString *path = session.filePath ?: @"";
    BOOL exists = path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:path];

    NSMenuItem *reveal = [menu addItemWithTitle:PTL(@"在 Finder 中显示", @"Reveal in Finder")
                                         action:@selector(revealSessionTranscript:)
                                  keyEquivalent:@""];
    reveal.target = self;
    reveal.representedObject = path;
    reveal.enabled = exists;
    reveal.toolTip = exists ? path : PTL(@"transcript 文件已不存在", @"Transcript file no longer exists");

    NSMenuItem *copyPath = [menu addItemWithTitle:PTL(@"拷贝 transcript 路径", @"Copy transcript path")
                                           action:@selector(copySessionTranscriptPath:)
                                    keyEquivalent:@""];
    copyPath.target = self;
    copyPath.representedObject = path;
    copyPath.enabled = path.length > 0;
}

- (void)revealSessionTranscript:(NSMenuItem *)sender {
    NSString *path = [sender.representedObject isKindOfClass:NSString.class]
        ? sender.representedObject : nil;
    if (path.length == 0) return;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        _statusLabel.stringValue = PTL(@"transcript 文件已不存在", @"Transcript file no longer exists");
        return;
    }
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}

- (void)copySessionTranscriptPath:(NSMenuItem *)sender {
    NSString *path = [sender.representedObject isKindOfClass:NSString.class]
        ? sender.representedObject : nil;
    if (path.length == 0) return;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:path forType:NSPasteboardTypeString];
    _statusLabel.stringValue = PTL(@"已拷贝 transcript 路径", @"Transcript path copied");
}

// 三个地方（bridge 状态变化 / 切换选中会话 / 点击接入按钮）都会想改按钮文案，
// 各写各的会互相打脸（比如点了"正在同步…"之后 bridge 的回调又把它覆盖成别的状态）。
// 统一到这一个方法里、按同一套优先级算，其它地方只管调用它。
- (void)updateConnectButtonTitle {
    if (_connecting) {
        _connectButton.title = PTL(@"正在同步…", @"Syncing…");
        return;
    }
    BOOL sameConnection = _bridge.running && [_bridge.sessionID isEqual:_selectedSession.sessionID];
    _connectButton.title = sameConnection
        ? PTL(@"已同步", @"Synced") : PTL(@"同步 Terminal", @"Sync");
    [self refreshAgentStateAndControls];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = _sessionTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_sessions.count) return;
    BOOL changed = ![_selectedSession.sessionID isEqual:_sessions[row].sessionID];
    if (changed) [self allowRediscoveryOfGitDirectoriesForNewSession];
    _selectedSession = _sessions[row];
    [self showSelectedSession];
    [self updateConnectButtonTitle];
    if (changed && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _conversationView.alphaValue = 0.62;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.18;
            self->_conversationView.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSString *languageScript = [NSString stringWithFormat:
        @"window.setPrettyTermLanguage && window.setPrettyTermLanguage('%@'); null;",
        PTInterfaceLanguageCode()];
    [webView evaluateJavaScript:languageScript completionHandler:nil];
    if (webView == _floatingConversationView) {
        _floatingWebReady = YES;
        [self refreshFloatingConversation];
        return;
    }
    _webReady = YES;
    if (_selectedSession) [self renderSession:_selectedSession];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *body = message.body;
    if ([message.name isEqualToString:@"openTranscriptEditReview"]) {
        NSString *sessionID = [body[@"sessionId"] isKindOfClass:NSString.class]
            ? body[@"sessionId"] : @"";
        NSNumber *turnIndexValue = [body[@"turnIndex"] isKindOfClass:NSNumber.class]
            ? body[@"turnIndex"] : nil;
        NSString *expectedSessionID = message.webView == _conversationView
            ? _selectedSession.sessionID
            : (message.webView == _floatingConversationView ? _floatingSessionID : nil);
        if (sessionID.length > 0 && turnIndexValue && [sessionID isEqual:expectedSessionID]) {
            [self openTranscriptEditReviewForSessionID:sessionID
                                             turnIndex:turnIndexValue.unsignedIntegerValue];
        }
        return;
    }
    if (![message.name isEqualToString:@"quoteSelection"]) return;
    NSString *text = [body[@"text"] isKindOfClass:NSString.class] ? body[@"text"] : nil;
    NSString *sessionID = [body[@"sessionId"] isKindOfClass:NSString.class] ? body[@"sessionId"] : nil;
    NSString *quote = PTMarkdownQuote(text);
    PTComposerTextView *composer = nil;
    NSTextField *status = nil;
    NSString *expectedSessionID = nil;

    if (message.webView == _conversationView) {
        composer = _composerTextView;
        status = _statusLabel;
        expectedSessionID = _selectedSession.sessionID;
    } else if (message.webView == _floatingConversationView) {
        composer = _floatingComposerTextView;
        status = _floatingComposerLabel;
        expectedSessionID = _floatingSessionID;
    } else {
        return;
    }

    BOOL correctlyBound = quote.length > 0 && sessionID.length > 0 &&
        [sessionID isEqual:expectedSessionID] && _bridge.running &&
        [_bridge.sessionID isEqual:sessionID] && composer.editable;
    if (!correctlyBound) {
        status.stringValue = text.length > 20000
            ? @"引用内容超过 20,000 字，已拒绝"
            : @"当前对话未同步，无法插入引用";
        return;
    }

    [composer.window makeFirstResponder:composer];
    [composer insertText:quote replacementRange:composer.selectedRange];
    status.stringValue = @"已引用 Claude 选中内容";
}

- (void)refreshSessions:(id)sender {
    if (sender == _refreshButton && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _refreshButton.alphaValue = 0.35;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.24;
            self->_refreshButton.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }
    [_store refresh];
    if (sender == _refreshButton) [self refreshClaudeUsage:sender];
}

- (void)connectSelectedSession:(id)sender {
    if (!_selectedSession) return;
    NSString *requestedSessionID = [_selectedSession.sessionID copy];
    NSString *requestedPath = [_selectedSession.filePath copy];
    _connecting = YES;
    _agentState.sendInFlight = NO;
    [self updateConnectButtonTitle];
    [_bridge connectToSession:_selectedSession];
    __weak typeof(self) weakSelf = self;
    [_store refreshForcingPath:_selectedSession.filePath completion:^(PTSessionInfo *session) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        if (!session || ![session.sessionID isEqual:requestedSessionID]) {
            self->_statusLabel.stringValue = @"JSONL 重新读取失败，请确认会话文件仍然存在";
            return;
        }
        NSMutableArray<PTSessionInfo *> *updated = [self->_sessions mutableCopy] ?: [NSMutableArray array];
        NSUInteger index = [updated indexOfObjectPassingTest:
            ^BOOL(PTSessionInfo *candidate, NSUInteger itemIndex, BOOL *stop) {
                (void)itemIndex;
                (void)stop;
                return [candidate.sessionID isEqual:requestedSessionID] ||
                    [candidate.filePath isEqual:requestedPath];
            }];
        if (index == NSNotFound) [updated addObject:session];
        else updated[index] = session;
        self->_manualRefreshSessionID = requestedSessionID;
        [self applySessions:updated];
        self->_statusLabel.stringValue = [NSString stringWithFormat:@"已从 JSONL 完整同步 · %lu 条消息",
            (unsigned long)session.assistantMessages.count];
    }];
    [_window makeFirstResponder:_composerTextView];
}

- (BOOL)sendOutgoingMessage:(NSString *)message
                     images:(NSArray<NSImage *> *)images
               forSessionID:(NSString *)sessionID
                    success:(dispatch_block_t)success
           failureResponder:(NSResponder *)failureResponder {
    NSString *outgoingMessage = PTMessageForClaudeAttachments(message, images.count);
    if (outgoingMessage.length == 0) return NO;
    BOOL correctBinding = _bridge.running && sessionID.length > 0 &&
        [_bridge.sessionID isEqual:sessionID];
    if (!correctBinding || _agentState.sendInFlight) {
        if ([sessionID isEqual:_floatingSessionID]) {
            _floatingComposerLabel.stringValue = @"未同步此会话 · 已阻止发送以免串线";
        } else {
            _statusLabel.stringValue = @"请先同步当前选中的 Terminal 会话";
        }
        return NO;
    }

    _agentState.sendInFlight = YES;
    [self refreshAgentStateAndControls];
    BOOL sent = [_bridge sendMessage:outgoingMessage withImages:images ?: @[]];
    if (sent) {
        if (success) success();
    } else if (failureResponder) {
        NSWindow *targetWindow = failureResponder == _floatingComposerTextView ? _floatingPanel : _window;
        [targetWindow makeFirstResponder:failureResponder];
    }
    _agentState.sendInFlight = NO;
    [self refreshAgentStateAndControls];
    return sent;
}

- (void)sendMessage:(id)sender {
    (void)sender;
    NSString *message = _composerTextView.string;
    NSArray<NSImage *> *images = [self pendingImagesForClaude];
    // 只有 Terminal 真正接受后才清空。之前桥接失败时输入框仍被无条件清空，
    // 从老师视角看就是“消息发不出去还凭空消失”，也丢掉了重试机会。
    [self sendOutgoingMessage:message images:images forSessionID:_selectedSession.sessionID success:^{
        [_composerTextView clearAfterSuccessfulSubmissionMatchingText:message];
        // 回车触发发送时，输入法可能在 keyDown: 返回后才结束当前事务；下一轮只在
        // 内容仍等于已发送快照时补做一次，因此不会误删随后键入的新内容。
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_composerTextView clearAfterSuccessfulSubmissionMatchingText:message];
        });
        [self clearPendingImagesAfterSuccessfulSend];
    } failureResponder:_composerTextView];
}

- (void)sendFloatingMessage:(id)sender {
    (void)sender;
    NSString *message = _floatingComposerTextView.string;
    NSArray<NSImage *> *images = [self floatingPendingImagesForClaude];
    [self sendOutgoingMessage:message images:images forSessionID:_floatingSessionID success:^{
        [_floatingComposerTextView clearAfterSuccessfulSubmissionMatchingText:message];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_floatingComposerTextView clearAfterSuccessfulSubmissionMatchingText:message];
        });
        [self clearFloatingPendingImagesAfterSuccessfulSend];
    } failureResponder:_floatingComposerTextView];
}

- (void)enableRemoteControl:(id)sender {
    (void)sender;
    _statusLabel.stringValue = @"官方 Remote Control 已禁用";
}

- (void)changeModel:(id)sender {
    NSString *modelID = _modelPicker.selectedItem.representedObject;
    if (modelID.length == 0) return;
    [self refreshAgentStateAndControls];
    if (!_agentState.commandsEnabled) {
        _statusLabel.stringValue = @"请先同步当前 Terminal 会话";
        [self updateContextAndModelForSession:_selectedSession];
        return;
    }
    if ([_bridge sendMessage:[NSString stringWithFormat:@"/model %@", modelID]]) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"已在 Terminal 请求切换到 %@", modelID];
    } else {
        [self updateContextAndModelForSession:_selectedSession];
    }
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        PTAppDelegate *delegate = [[PTAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
