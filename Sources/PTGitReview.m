#import "PTGitReview.h"
#import "PTLocalization.h"

static NSString *PTGitReviewString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray<NSString *> *PTGitReviewLines(NSString *text) {
    if (text.length == 0) return @[];
    NSMutableArray<NSString *> *lines = [[text componentsSeparatedByCharactersInSet:
        NSCharacterSet.newlineCharacterSet] mutableCopy];
    while ([lines.lastObject isEqual:@""]) [lines removeLastObject];
    return lines;
}

static NSString *PTGitReviewCleanPath(NSString *path) {
    NSString *value = [path stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && value.length >= 2) {
        value = [value substringWithRange:NSMakeRange(1, value.length - 2)];
    }
    return value;
}

static NSString *PTGitReviewPathFromHeader(NSString *line) {
    NSRange bPath = [line rangeOfString:@" b/" options:NSBackwardsSearch];
    if (bPath.location == NSNotFound) return PTL(@"未命名文件", @"Untitled file");
    return PTGitReviewCleanPath([line substringFromIndex:NSMaxRange(bPath)]);
}

static NSArray<NSMutableDictionary *> *PTGitReviewParseFiles(NSString *diff) {
    NSMutableArray<NSMutableDictionary *> *files = [NSMutableArray array];
    NSMutableDictionary *current = nil;
    for (NSString *line in PTGitReviewLines(diff)) {
        if ([line hasPrefix:@"diff --git "]) {
            current = [@{
                @"path": PTGitReviewPathFromHeader(line),
                @"rawLines": [NSMutableArray arrayWithObject:line],
                @"added": @0,
                @"removed": @0,
                @"binary": @NO
            } mutableCopy];
            [files addObject:current];
            continue;
        }
        if (!current) continue;
        [current[@"rawLines"] addObject:line];
        if ([line hasPrefix:@"+++ b/"]) {
            current[@"path"] = PTGitReviewCleanPath([line substringFromIndex:6]);
            continue;
        }
        if ([line hasPrefix:@"Binary files "] || [line hasPrefix:@"GIT binary patch"]) {
            current[@"binary"] = @YES;
            continue;
        }
        if ([line hasPrefix:@"@@"] || [line hasPrefix:@"+"] || [line hasPrefix:@"-"] ||
            [line hasPrefix:@" "] || [line hasPrefix:@"\\ No newline"]) {
            if ([line hasPrefix:@"+"] && ![line hasPrefix:@"+++"]) {
                current[@"added"] = @([current[@"added"] unsignedIntegerValue] + 1);
            } else if ([line hasPrefix:@"-"] && ![line hasPrefix:@"---"]) {
                current[@"removed"] = @([current[@"removed"] unsignedIntegerValue] + 1);
            }
        }
    }
    return files;
}

static NSDictionary<NSString *, NSString *> *PTGitReviewStatusEntry(NSString *line) {
    if (line.length < 3) return @{};
    NSString *code = [line substringToIndex:2];
    NSString *path = [[line substringFromIndex:3]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSRange arrow = [path rangeOfString:@" -> " options:NSBackwardsSearch];
    if (arrow.location != NSNotFound) path = [path substringFromIndex:NSMaxRange(arrow)];
    return @{ @"code": code, @"path": PTGitReviewCleanPath(path) };
}

static NSString *PTGitReviewStatusLabel(NSString *code) {
    if ([code isEqual:@"??"]) return PTL(@"未跟踪", @"Untracked");
    if ([code containsString:@"A"]) return PTL(@"新增", @"Added");
    if ([code containsString:@"D"]) return PTL(@"删除", @"Deleted");
    if ([code containsString:@"R"]) return PTL(@"重命名", @"Renamed");
    if ([code containsString:@"U"]) return PTL(@"冲突", @"Conflict");
    return PTL(@"已修改", @"Modified");
}

NSArray<NSDictionary *> *PTGitReviewStructuredFiles(NSDictionary<NSString *, NSString *> *snapshot) {
    NSString *error = PTGitReviewString(snapshot[@"error"]);
    if (error.length > 0) return @[];
    NSString *status = PTGitReviewString(snapshot[@"status"]);
    NSString *diff = PTGitReviewString(snapshot[@"diff"]);

    NSMutableDictionary<NSString *, NSString *> *statusByPath = [NSMutableDictionary dictionary];
    for (NSString *line in PTGitReviewLines(status)) {
        NSDictionary *entry = PTGitReviewStatusEntry(line);
        NSString *path = PTGitReviewString(entry[@"path"]);
        if (path.length > 0) statusByPath[path] = PTGitReviewString(entry[@"code"]);
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
    for (NSDictionary *file in PTGitReviewParseFiles(diff)) {
        NSString *path = PTGitReviewString(file[@"path"]);
        if (path.length > 0) [seenPaths addObject:path];
        NSString *code = statusByPath[path] ?: @"M";
        NSString *patch = [(NSArray<NSString *> *)file[@"rawLines"] componentsJoinedByString:@"\n"] ?: @"";
        [result addObject:@{
            @"path": path,
            @"statusCode": code,
            @"statusLabel": PTGitReviewStatusLabel(code),
            @"added": file[@"added"] ?: @0,
            @"removed": file[@"removed"] ?: @0,
            @"binary": file[@"binary"] ?: @NO,
            @"patch": patch
        }];
    }

    for (NSString *line in PTGitReviewLines(status)) {
        NSDictionary *entry = PTGitReviewStatusEntry(line);
        NSString *path = PTGitReviewString(entry[@"path"]);
        if (path.length == 0 || [seenPaths containsObject:path]) continue;
        NSString *code = PTGitReviewString(entry[@"code"]);
        [result addObject:@{
            @"path": path,
            @"statusCode": code,
            @"statusLabel": PTGitReviewStatusLabel(code),
            @"added": @0,
            @"removed": @0,
            @"binary": @NO,
            @"patch": @""
        }];
    }
    return result;
}
