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
        PTAssert([PTResetDescription(reset, date) containsString:@"小时"],
            @"Chinese reset description must remain available");
        [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:@"PTInterfaceLanguage"];
        PTAssert([PTResetDescription(reset, date) containsString:@"Resets in"],
            @"English reset description must be available");
        [NSUserDefaults.standardUserDefaults setObject:@"zh-Hans" forKey:@"PTInterfaceLanguage"];
        NSDictionary *usageEnvelope = @{
            @"is_error": @NO,
            @"num_turns": @0,
            @"total_cost_usd": @0,
            @"result": @"You are currently using your subscription\n\nCurrent session: 23% used · resets Aug 11 at 12:49pm (Asia/Shanghai)\nCurrent week (all models): 12% used · resets Aug 16 at 12:59am (Asia/Shanghai)"
        };
        NSData *usageJSON = [NSJSONSerialization dataWithJSONObject:usageEnvelope options:0 error:nil];
        NSString *usageOutput = [[NSString alloc] initWithData:usageJSON encoding:NSUTF8StringEncoding];
        NSDateComponents *usageNowParts = [[NSDateComponents alloc] init];
        usageNowParts.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        usageNowParts.timeZone = NSTimeZone.localTimeZone;
        usageNowParts.year = 2026;
        usageNowParts.month = 8;
        usageNowParts.day = 11;
        usageNowParts.hour = 10;
        NSDictionary *planUsage = PTClaudePlanUsageFromCommandOutput(usageOutput, usageNowParts.date);
        PTAssertNear([planUsage[@"five_hour"][@"utilization"] doubleValue], 23.0,
            @"Claude Code /usage session percentage should parse");
        PTAssertNear([planUsage[@"seven_day"][@"utilization"] doubleValue], 12.0,
            @"Claude Code /usage weekly percentage should parse");
        PTAssert(PTDateFromClaudeAPIString(planUsage[@"five_hour"][@"resets_at"]) != nil,
            @"Claude Code /usage reset time should parse into the existing display model");
        PTAssert(PTClaudePlanUsageFromCommandOutput(@"{}", usageNowParts.date) == nil,
            @"malformed Claude Code /usage output must not invent quota values");
        NSLog(@"PTUsageMetricsTests passed");
    }
    return 0;
}
