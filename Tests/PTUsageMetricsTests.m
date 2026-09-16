#import <Foundation/Foundation.h>
#import <math.h>
#import "PTUsageMetrics.h"

static void PTAssert(BOOL condition, NSString *message) {
    if (condition) return;
    NSLog(@"FAIL: %@", message);
    exit(1);
}

static void PTAssertNear(double actual, double expected, NSString *message) {
    PTAssert(fabs(actual - expected) < 0.000001,
        [NSString stringWithFormat:@"%@ (actual %.6f expected %.6f)", message, actual, expected]);
}

int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setObject:@"zh-Hans" forKey:@"PTInterfaceLanguage"];
        NSDateComponents *components = [[NSDateComponents alloc] init];
        components.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        components.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        components.year = 2026;
        components.month = 8;
        components.day = 9;
        NSDate *date = components.date;
        NSDictionary *usage = @{
            @"input_tokens": @1000000,
            @"output_tokens": @1000000,
            @"cache_read_input_tokens": @1000000,
            @"cache_creation_input_tokens": @2000000,
            @"cache_creation": @{
                @"ephemeral_5m_input_tokens": @1000000,
                @"ephemeral_1h_input_tokens": @1000000
            }
        };
        BOOL supported = NO;
        PTAssertNear(PTAPIEquivalentCostForUsage(@"claude-sonnet-5", usage, date, &supported),
                     18.7, @"Sonnet 5 introductory pricing should include both cache tiers");
        PTAssert(supported, @"Sonnet 5 should be supported");
        PTAssertNear(PTAPIEquivalentCostForUsage(@"claude-opus-5", usage, date, &supported),
                     46.75, @"Opus 5 pricing should be correct");
        PTAssertNear(PTAPIEquivalentCostForUsage(@"claude-fable-5", usage, date, &supported),
                     93.5, @"Fable 5 pricing should be correct");
        PTAssertNear(PTAPIEquivalentCostForUsage(@"unknown", usage, date, &supported),
                     0, @"Unknown models must not invent a cost");
        PTAssert(!supported, @"Unknown model must be marked unsupported");
        PTAssert([PTDateFromClaudeAPIString(@"2026-08-09T04:59:59.763485+00:00") isKindOfClass:NSDate.class],
                 @"Claude fractional reset timestamps should parse");
        NSDate *reset = [date dateByAddingTimeInterval:90 * 60];
        NSString *zhCountdown = PTCountdownDescription(reset, date);
        PTAssert([zhCountdown isEqualToString:@"1 小时 30 分"],
            @"Chinese quota time must be a countdown only");
        PTAssert(![zhCountdown containsString:@"重置"],
            @"Chinese quota countdown must not expose reset wording");
        [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:@"PTInterfaceLanguage"];
        NSString *enCountdown = PTCountdownDescription(reset, date);
        PTAssert([enCountdown isEqualToString:@"1 h 30 min"],
            @"English quota time must be a countdown only");
        PTAssert(![enCountdown.lowercaseString containsString:@"reset"],
            @"English quota countdown must not expose reset wording");
        [NSUserDefaults.standardUserDefaults setObject:@"zh-Hans" forKey:@"PTInterfaceLanguage"];
        NSDictionary *statusLineSnapshot = @{
            @"session_id": @"usage-session",
            @"rate_limits": @{
                @"five_hour": @{ @"used_percentage": @23.5, @"resets_at": @1786423740 },
                @"seven_day": @{ @"used_percentage": @12.0, @"resets_at": @1786813140 }
            }
        };
        NSDictionary *planUsage = PTClaudePlanUsageFromStatusLineSnapshot(
            statusLineSnapshot, @"usage-session");
        PTAssertNear([planUsage[@"five_hour"][@"utilization"] doubleValue], 23.5,
            @"Claude response status line five-hour percentage should parse");
        PTAssertNear([planUsage[@"seven_day"][@"utilization"] doubleValue], 12.0,
            @"Claude response status line seven-day percentage should parse");
        PTAssert(PTDateFromClaudeAPIString(planUsage[@"five_hour"][@"resets_at"]) != nil,
            @"Claude response epoch reset time should enter the existing display model");
        PTAssert(PTClaudePlanUsageFromStatusLineSnapshot(statusLineSnapshot, @"another-session") == nil,
            @"a response snapshot from another conversation must never update the selected one");
        NSDictionary *partialSnapshot = @{
            @"session_id": @"usage-session",
            @"rate_limits": @{
                @"five_hour": @{ @"used_percentage": @23.5, @"resets_at": @1786423740 }
            }
        };
        PTAssert(PTClaudePlanUsageFromStatusLineSnapshot(partialSnapshot, @"usage-session") == nil,
            @"a partial response must not invent the missing weekly percentage");
        PTAssert(PTClaudePlanUsageFromStatusLineSnapshot(@{}, @"usage-session") == nil,
            @"malformed status line data must not invent quota values");
        NSLog(@"PTUsageMetricsTests passed");
    }
    return 0;
}
