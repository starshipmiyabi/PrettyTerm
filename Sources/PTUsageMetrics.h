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

/// Parses the official `rate_limits` object delivered to Claude Code's status line
/// after an API response. The snapshot must belong to `expectedSessionID` and
/// contain both the five-hour and seven-day windows.
FOUNDATION_EXPORT NSDictionary * _Nullable PTClaudePlanUsageFromStatusLineSnapshot(
    NSDictionary *snapshot,
    NSString *expectedSessionID
);

NS_ASSUME_NONNULL_END
