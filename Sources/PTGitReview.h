#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// 将 Git 原始状态与 unified diff 渲染为适合原生检查器的审阅文档。
FOUNDATION_EXPORT NSAttributedString *PTGitReviewAttributedString(
    NSDictionary<NSString *, NSString *> *snapshot
);

// 直接渲染 Claude transcript 中本回合已记录的 Edit / Write 片段。
// 此入口不读取工作树，也不会执行 git diff。
FOUNDATION_EXPORT NSAttributedString *PTTranscriptEditReviewAttributedString(
    NSArray<NSDictionary *> *editEvents
);

FOUNDATION_EXPORT NSAttributedString *PTGitReviewLoadingAttributedString(void);

NS_ASSUME_NONNULL_END
