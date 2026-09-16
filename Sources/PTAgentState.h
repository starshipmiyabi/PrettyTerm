#import <Foundation/Foundation.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

@interface PTAgentState : NSObject
@property(nonatomic, copy) NSString *selectedSessionID;
@property(nonatomic, copy) NSString *boundSessionID;
@property(nonatomic) BOOL bridgeRunning;
@property(nonatomic) BOOL sendInFlight;
@property(nonatomic, readonly) BOOL commandsEnabled;
@end

@interface PTRefreshGate : NSObject
- (BOOL)beginRefresh;
- (BOOL)finishRefreshNeedsAnotherPass;
@end

@interface PTTranscriptWatcher : NSObject
- (BOOL)watchFileAtPath:(NSString *)path
               onChange:(dispatch_block_t)onChange;
- (void)stopWatching;
@end

FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *PTDiffStats(
    NSString *oldText,
    NSString *newText
);

FOUNDATION_EXPORT NSArray<NSDictionary *> *PTAggregateChangedFiles(
    NSArray<NSDictionary *> *events
);

FOUNDATION_EXPORT NSDictionary * _Nullable PTEventFromAssistantBlock(
    NSDictionary *block,
    NSString *messageKey,
    NSString *timestamp,
    NSString *model
);

FOUNDATION_EXPORT NSDictionary * _Nullable PTEventFromToolResultBlock(
    NSDictionary *block,
    NSString *messageKey,
    NSString *timestamp
);

// AskUserQuestion 的 toolUseResult.answers（question -> answer 文本字典）拼成多行展示文本。
FOUNDATION_EXPORT NSString *PTFormattedQuestionAnswers(NSDictionary *answers);

FOUNDATION_EXPORT BOOL PTIsSupportedImagePath(NSString *path);

FOUNDATION_EXPORT NSString *PTMessageForClaudeAttachments(
    NSString *message,
    NSUInteger imageCount
);

FOUNDATION_EXPORT NSString *PTMessageByAppendingClaudeAttachMarkers(
    NSString *message,
    NSArray<NSString *> *filePaths
);

// 原生粘贴前统一行尾并剥离可改变 TTY 状态的控制字符；粘贴动作和唯一一次
// Return 由 Bridge 分阶段投递。
FOUNDATION_EXPORT NSString *PTNormalizedTerminalPasteText(NSString *message);
FOUNDATION_EXPORT NSString *PTTerminalSubmissionPayload(NSString *message);
FOUNDATION_EXPORT NSInteger PTLatestTerminalPasteMarker(NSString *contents);

typedef NS_ENUM(NSInteger, PTTerminalAutomationAction) {
    PTTerminalAutomationActionWriteText,
    PTTerminalAutomationActionSubmitReturn,
    PTTerminalAutomationActionPasteImage,
    PTTerminalAutomationActionInterruptEscape,
};

// 构造带 TTY、PID 与精确 Claude 进程名校验的 Terminal AppleScript。
FOUNDATION_EXPORT NSString *PTTerminalAutomationScript(
    NSString *tty,
    pid_t claudePID,
    NSString *message,
    PTTerminalAutomationAction action
);

typedef NS_ENUM(NSInteger, PTComposerKeyAction) {
    PTComposerKeyActionDefer,
    PTComposerKeyActionSubmit,
    PTComposerKeyActionInsertNewline,
};

FOUNDATION_EXPORT PTComposerKeyAction PTComposerActionForKey(
    unsigned short keyCode,
    BOOL commandDown,
    BOOL shiftDown,
    BOOL hasMarkedText
);

typedef NS_ENUM(NSInteger, PTFloatingConversationAction) {
    PTFloatingConversationActionNone,
    PTFloatingConversationActionOpen,
    PTFloatingConversationActionClose,
};

FOUNDATION_EXPORT PTFloatingConversationAction PTFloatingConversationActionForState(
    BOOL visible,
    NSString *pinnedSessionID,
    NSString *selectedSessionID
);

FOUNDATION_EXPORT BOOL PTSessionRenderNeedsUpdate(
    NSString * _Nullable renderedSessionID,
    NSDate * _Nullable renderedModifiedAt,
    NSUInteger renderedMessageCount,
    NSString * _Nullable sessionID,
    NSDate * _Nullable modifiedAt,
    NSUInteger messageCount
);

NS_ASSUME_NONNULL_END
