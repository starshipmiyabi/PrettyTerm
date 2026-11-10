#import <AppKit/AppKit.h>
#import "PTGitReview.h"

static void PTAssert(BOOL condition, NSString *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        [NSUserDefaults.standardUserDefaults setObject:@"zh-Hans" forKey:@"PTInterfaceLanguage"];
        NSDictionary *snapshot = @{
            @"root": @"/tmp/PrettyTerm",
            @"directory": @"/tmp/PrettyTerm",
            @"branch": @"main",
            @"upstream": @"origin/main",
            @"status": @" M Sources/Review.m\n?? Notes.txt\n",
            @"diff":
                @"diff --git a/Sources/Review.m b/Sources/Review.m\n"
                 "index 1111111..2222222 100644\n"
                 "--- a/Sources/Review.m\n"
                 "+++ b/Sources/Review.m\n"
                 "@@ -10,3 +10,4 @@\n"
                 " context\n"
                 "-old value\n"
                 "+new value\n"
                 "+extra value\n"
                 " tail\n"
        };
        NSArray<NSDictionary *> *files = PTGitReviewStructuredFiles(snapshot);
        PTAssert(files.count == 2, @"modified and untracked files must both be present");
        NSDictionary *modified = files.firstObject;
        PTAssert([modified[@"path"] isEqual:@"Sources/Review.m"] &&
            [modified[@"added"] integerValue] == 2 && [modified[@"removed"] integerValue] == 1,
            @"the structured row must preserve the modified path and diff counts");
        PTAssert([modified[@"patch"] containsString:@"-old value\n+new value"],
            @"the web renderer must receive the original unified patch");
        NSDictionary *untracked = files.lastObject;
        PTAssert([untracked[@"path"] isEqual:@"Notes.txt"] && [untracked[@"statusCode"] isEqual:@"??"],
            @"a status-only file must retain its untracked status");
        PTAssert(PTGitReviewStructuredFiles(@{}).count == 0 &&
            PTGitReviewStructuredFiles(@{@"error": @"not a repository", @"diff": snapshot[@"diff"]}).count == 0,
            @"clean and failed queries must have no structured file rows");
        NSLog(@"PTGitReviewTests passed");
    }
    return 0;
}
