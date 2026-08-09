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
        NSLog(@"PTUsageMetricsTests passed");
    }
    return 0;
}
