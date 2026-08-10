#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// 将 Git 原始状态与 unified diff 渲染为适合原生检查器的审阅文档。
FOUNDATION_EXPORT NSAttributedString *PTGitReviewAttributedString(
    NSDictionary<NSString *, NSString *> *snapshot
);

FOUNDATION_EXPORT NSAttributedString *PTGitReviewLoadingAttributedString(void);

NS_ASSUME_NONNULL_END
