#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 按 Claude Platform 公布的标准 API 单价计算一条 Messages API usage 的等价成本。
/// 这只是价值估算，不代表 Claude 订阅账户实际扣款。
FOUNDATION_EXPORT double PTAPIEquivalentCostForUsage(NSString *model,
                                                     NSDictionary *usage,
                                                     NSDate *pricingDate,
                                                     BOOL * _Nullable supported);

FOUNDATION_EXPORT NSString *PTAPIEquivalentCostDisplay(double costUSD);
FOUNDATION_EXPORT NSDate * _Nullable PTDateFromClaudeAPIString(NSString *value);
FOUNDATION_EXPORT NSString *PTCountdownDescription(NSDate * _Nullable targetDate,
                                                   NSDate *now);

/// Parses the zero-turn JSON result produced by `claude -p /usage`.
/// PrettyTerm delegates authentication and token refresh to the installed Claude Code binary.
FOUNDATION_EXPORT NSDictionary * _Nullable PTClaudePlanUsageFromCommandOutput(
    NSString *output,
    NSDate *now
);

NS_ASSUME_NONNULL_END
