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

        NSArray<NSDictionary *> *transcriptEdits = @[
            @{
                @"kind": @"diff",
                @"toolName": @"Edit",
                @"filePath": @"/tmp/Sources/LocalReview.m",
                @"oldText": @"old line\nkept",
                @"newText": @"new line\nkept"
            },
            @{
                @"kind": @"diff",
                @"toolName": @"Write",
                @"filePath": @"/tmp/Notes.txt",
                @"oldText": @"",
                @"newText": @"created locally"
            }
        ];
        NSAttributedString *localReview =
            PTTranscriptEditReviewAttributedString(transcriptEdits);
        NSString *localText = localReview.string;
        PTAssert([localText containsString:@"本轮本地修改"] &&
                 [localText containsString:@"未执行 git diff"],
            @"transcript review must identify its local source and Git-free boundary");
        PTAssert([localText containsString:@"LocalReview.m"] &&
                 [localText containsString:@"Notes.txt"] &&
                 [localText containsString:@"old line"] &&
                 [localText containsString:@"new line"] &&
                 [localText containsString:@"created locally"],
            @"transcript review must render the exact recorded Edit and Write content");
        PTAssert(![localText containsString:@"Git 审阅不可用"] &&
                 ![localText containsString:@"这里不是 Git 仓库"],
            @"transcript review must never inherit Git repository errors");
        NSRange localAdded = [localText rangeOfString:@"+ new line"];
        NSRange localRemoved = [localText rangeOfString:@"− old line"];
        PTAssert(localAdded.location != NSNotFound && localRemoved.location != NSNotFound,
            @"transcript review must expose recorded additions and removals");
        PTAssert([localReview attribute:NSBackgroundColorAttributeName atIndex:localAdded.location
            effectiveRange:nil] != nil &&
                 [localReview attribute:NSBackgroundColorAttributeName atIndex:localRemoved.location
            effectiveRange:nil] != nil,
            @"transcript additions and removals must keep review highlighting");

        NSMutableArray<NSString *> *largeLines = [NSMutableArray array];
        for (NSUInteger index = 0; index < 6001; index++) {
            [largeLines addObject:[NSString stringWithFormat:@"full row %lu", (unsigned long)index]];
        }
        NSString *largeReviewText = PTTranscriptEditReviewAttributedString(@[@{
            @"kind": @"diff",
            @"toolName": @"Write",
            @"filePath": @"/tmp/Large.txt",
            @"oldText": @"",
            @"newText": [largeLines componentsJoinedByString:@"\n"]
        }]).string;
        PTAssert([largeReviewText containsString:@"full row 6000"],
            @"transcript review must display rows beyond the former 5,000-row boundary");

        [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:@"PTInterfaceLanguage"];
        NSString *englishLocal = PTTranscriptEditReviewAttributedString(transcriptEdits).string;
        NSString *englishGit = PTGitReviewAttributedString(@{
            @"root": @"/tmp/PrettyTerm",
            @"directory": @"/tmp/PrettyTerm",
            @"branch": @"main",
            @"status": @"",
            @"diff": @""
        }).string;
        PTAssert([englishLocal containsString:@"Local Changes This Turn"] &&
                 [englishLocal containsString:@"git diff was not run"],
            @"English mode must localize transcript review without changing recorded content");
        PTAssert([englishGit containsString:@"Working tree is clean"],
            @"English mode must localize native Git review states");
        [NSUserDefaults.standardUserDefaults setObject:@"zh-Hans" forKey:@"PTInterfaceLanguage"];
        NSLog(@"PTGitReviewTests passed");
    }
    return 0;
}
