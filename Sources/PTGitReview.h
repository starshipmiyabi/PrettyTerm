#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 导出结构化的逐文件状态与 unified patch 字符串，供前端 Diff 组件直接渲染。
FOUNDATION_EXPORT NSArray<NSDictionary *> *PTGitReviewStructuredFiles(
    NSDictionary<NSString *, NSString *> *snapshot
);

NS_ASSUME_NONNULL_END
