#import "PTUsageMetrics.h"
#import "PTLocalization.h"
#import <math.h>

typedef struct {
    double input;
    double cacheWrite5m;
    double cacheWrite1h;
    double cacheRead;
    double output;
} PTModelPricing;

static BOOL PTPricingForModel(NSString *model, NSDate *date, PTModelPricing *pricing) {
    NSString *lower = model.lowercaseString ?: @"";
    PTModelPricing value = {0};
    if ([lower containsString:@"fable-5"] || [lower containsString:@"mythos-5"]) {
        value = (PTModelPricing){10.0, 12.5, 20.0, 1.0, 50.0};
    } else if ([lower containsString:@"opus-5"] ||
               [lower containsString:@"opus-4-8"] ||
               [lower containsString:@"opus-4-7"] ||
               [lower containsString:@"opus-4-6"] ||
               [lower containsString:@"opus-4-5"]) {
        value = (PTModelPricing){5.0, 6.25, 10.0, 0.5, 25.0};
    } else if ([lower containsString:@"sonnet-5"]) {
        NSDateComponents *components = [[NSDateComponents alloc] init];
        components.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        components.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        components.year = 2026;
        components.month = 9;
        components.day = 1;
        NSDate *standardPricingStarts = components.date;
        BOOL introductory = standardPricingStarts && [date compare:standardPricingStarts] == NSOrderedAscending;
        value = introductory
            ? (PTModelPricing){2.0, 2.5, 4.0, 0.2, 10.0}
            : (PTModelPricing){3.0, 3.75, 6.0, 0.3, 15.0};
    } else if ([lower containsString:@"sonnet-4-6"] ||
               [lower containsString:@"sonnet-4-5"] ||
               [lower containsString:@"sonnet-4-"]) {
        value = (PTModelPricing){3.0, 3.75, 6.0, 0.3, 15.0};
    } else if ([lower containsString:@"haiku-4-5"]) {
        value = (PTModelPricing){1.0, 1.25, 2.0, 0.1, 5.0};
    } else {
        return NO;
    }
    if (pricing) *pricing = value;
    return YES;
}

double PTAPIEquivalentCostForUsage(NSString *model,
                                   NSDictionary *usage,
                                   NSDate *pricingDate,
                                   BOOL *supported) {
    PTModelPricing pricing = {0};
    BOOL known = [usage isKindOfClass:NSDictionary.class] &&
        PTPricingForModel(model, pricingDate ?: NSDate.date, &pricing);
    if (supported) *supported = known;
    if (!known) return 0;

    double input = [usage[@"input_tokens"] doubleValue];
    double output = [usage[@"output_tokens"] doubleValue];
    double cacheRead = [usage[@"cache_read_input_tokens"] doubleValue];
    double cacheWriteTotal = [usage[@"cache_creation_input_tokens"] doubleValue];
    NSDictionary *cacheCreation = [usage[@"cache_creation"] isKindOfClass:NSDictionary.class]
        ? usage[@"cache_creation"] : nil;
    double cacheWrite5m = [cacheCreation[@"ephemeral_5m_input_tokens"] doubleValue];
    double cacheWrite1h = [cacheCreation[@"ephemeral_1h_input_tokens"] doubleValue];
    double classifiedCache = cacheWrite5m + cacheWrite1h;
    if (classifiedCache < cacheWriteTotal) cacheWrite5m += cacheWriteTotal - classifiedCache;

    // 所有单价均为 USD / 1M tokens。
    return (input * pricing.input +
            cacheWrite5m * pricing.cacheWrite5m +
            cacheWrite1h * pricing.cacheWrite1h +
            cacheRead * pricing.cacheRead +
            output * pricing.output) / 1000000.0;
}

NSString *PTAPIEquivalentCostDisplay(double costUSD) {
    if (costUSD >= 10.0) return [NSString stringWithFormat:@"$%.2f", costUSD];
    if (costUSD >= 1.0) return [NSString stringWithFormat:@"$%.3f", costUSD];
    if (costUSD >= 0.01) return [NSString stringWithFormat:@"$%.4f", costUSD];
    return [NSString stringWithFormat:@"$%.5f", costUSD];
}

NSDate *PTDateFromClaudeAPIString(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return nil;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
        NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:value];
    if (date) return date;
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter dateFromString:value];
}

NSString *PTResetDescription(NSDate *resetDate, NSDate *now) {
    if (!resetDate) return PTL(@"重置时间未知", @"Reset time unknown");
    NSTimeInterval remaining = [resetDate timeIntervalSinceDate:now ?: NSDate.date];
    if (remaining <= 0) return PTL(@"即将重置", @"Resetting soon");
    NSUInteger minutes = (NSUInteger)ceil(remaining / 60.0);
    if (minutes < 60) return [NSString stringWithFormat:PTL(@"%lu 分钟后重置", @"Resets in %lu min"), (unsigned long)minutes];
    NSUInteger hours = minutes / 60;
    NSUInteger restMinutes = minutes % 60;
    if (hours < 24) {
        return restMinutes > 0
            ? [NSString stringWithFormat:PTL(@"%lu 小时 %lu 分后重置", @"Resets in %lu h %lu min"), (unsigned long)hours, (unsigned long)restMinutes]
            : [NSString stringWithFormat:PTL(@"%lu 小时后重置", @"Resets in %lu h"), (unsigned long)hours];
    }
    NSUInteger days = hours / 24;
    NSUInteger restHours = hours % 24;
    return restHours > 0
        ? [NSString stringWithFormat:PTL(@"%lu 天 %lu 小时后重置", @"Resets in %lu d %lu h"), (unsigned long)days, (unsigned long)restHours]
        : [NSString stringWithFormat:PTL(@"%lu 天后重置", @"Resets in %lu d"), (unsigned long)days];
}
