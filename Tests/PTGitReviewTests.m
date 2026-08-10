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
        NSAttributedString *review = PTGitReviewAttributedString(snapshot);
        NSString *text = review.string;
        PTAssert([text containsString:@"main  →  origin/main"],
            @"review header must show the branch relationship");
        PTAssert([text containsString:@"Sources/Review.m    +2  −1"],
            @"file header must summarize additions and deletions");
        PTAssert([text containsString:@"9 行未修改"],
            @"the review must collapse unchanged lines before a hunk");
        PTAssert([text containsString:@"Notes.txt    未跟踪"],
            @"status-only untracked files must remain visible");
        PTAssert(![text containsString:@"diff --git"] &&
                 ![text containsString:@"index 1111111"] &&
                 ![text containsString:@"@@ -10,3"],
            @"raw terminal-oriented Git protocol lines must not reach the review UI");

        NSRange addedRange = [text rangeOfString:@"+ new value"];
        NSRange removedRange = [text rangeOfString:@"− old value"];
        PTAssert(addedRange.location != NSNotFound && removedRange.location != NSNotFound,
            @"review must expose explicit addition and deletion markers");
        PTAssert([review attribute:NSBackgroundColorAttributeName atIndex:addedRange.location
            effectiveRange:nil] != nil,
            @"added lines must have a review background");
        PTAssert([review attribute:NSBackgroundColorAttributeName atIndex:removedRange.location
            effectiveRange:nil] != nil,
            @"removed lines must have a review background");

        NSAttributedString *clean = PTGitReviewAttributedString(@{
            @"root": @"/tmp/PrettyTerm",
            @"directory": @"/tmp/PrettyTerm",
            @"branch": @"main",
            @"status": @"",
            @"diff": @""
        });
        PTAssert([clean.string containsString:@"工作树干净"],
            @"a clean repository must receive a friendly native empty state");

        NSAttributedString *failure = PTGitReviewAttributedString(@{
            @"error": @"这里不是 Git 仓库。"
        });
        PTAssert([failure.string containsString:@"Git 审阅不可用"] &&
                 [failure.string containsString:@"这里不是 Git 仓库"],
            @"Git failures must render as a review error state");
        NSLog(@"PTGitReviewTests passed");
    }
    return 0;
}
