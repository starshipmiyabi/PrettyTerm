#import "PTGitReview.h"

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
    if (bPath.location == NSNotFound) return @"未命名文件";
    return PTGitReviewCleanPath([line substringFromIndex:NSMaxRange(bPath)]);
}

static NSArray<NSMutableDictionary *> *PTGitReviewParseFiles(NSString *diff) {
    NSMutableArray<NSMutableDictionary *> *files = [NSMutableArray array];
    NSMutableDictionary *current = nil;
    for (NSString *line in PTGitReviewLines(diff)) {
        if ([line hasPrefix:@"diff --git "]) {
            current = [@{
                @"path": PTGitReviewPathFromHeader(line),
                @"lines": [NSMutableArray array],
                @"added": @0,
                @"removed": @0,
                @"binary": @NO
            } mutableCopy];
            [files addObject:current];
            continue;
        }
        if (!current) continue;
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
            [current[@"lines"] addObject:line];
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

static NSParagraphStyle *PTGitReviewParagraphStyle(void) {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 1.5;
    style.minimumLineHeight = 18.0;
    style.maximumLineHeight = 18.0;
    return style;
}

static NSColor *PTGitReviewDynamicGray(CGFloat lightWhite, CGFloat darkWhite) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]];
        CGFloat white = [match isEqual:NSAppearanceNameDarkAqua] ? darkWhite : lightWhite;
        return [NSColor colorWithWhite:white alpha:1.0];
    }];
}

static NSDictionary *PTGitReviewAttributes(NSFont *font, NSColor *color, NSColor *background) {
    NSMutableDictionary *attributes = [@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: PTGitReviewParagraphStyle()
    } mutableCopy];
    if (background) attributes[NSBackgroundColorAttributeName] = background;
    return attributes;
}

static NSRange PTGitReviewAppend(NSMutableAttributedString *output, NSString *text,
                                 NSDictionary *attributes) {
    NSUInteger location = output.length;
    [output appendAttributedString:[[NSAttributedString alloc] initWithString:text
        attributes:attributes]];
    return NSMakeRange(location, text.length);
}

static BOOL PTGitReviewReadHunk(NSString *line, NSInteger *oldStart, NSInteger *newStart) {
    static NSRegularExpression *expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
            @"^@@ -([0-9]+)(?:,[0-9]+)? \\+([0-9]+)(?:,[0-9]+)? @@"
            options:0 error:nil];
    });
    NSTextCheckingResult *match = [expression firstMatchInString:line options:0
        range:NSMakeRange(0, line.length)];
    if (!match || match.numberOfRanges < 3) return NO;
    *oldStart = [[line substringWithRange:[match rangeAtIndex:1]] integerValue];
    *newStart = [[line substringWithRange:[match rangeAtIndex:2]] integerValue];
    return YES;
}

static NSString *PTGitReviewStatusLabel(NSString *code) {
    if ([code isEqual:@"??"]) return @"未跟踪";
    if ([code containsString:@"A"]) return @"新增";
    if ([code containsString:@"D"]) return @"删除";
    if ([code containsString:@"R"]) return @"重命名";
    if ([code containsString:@"U"]) return @"冲突";
    return @"已修改";
}

NSAttributedString *PTGitReviewLoadingAttributedString(void) {
    NSDictionary *attributes = PTGitReviewAttributes(
        [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSColor.secondaryLabelColor, nil);
    return [[NSAttributedString alloc] initWithString:@"正在整理 Git 改动…\n"
        attributes:attributes];
}

NSAttributedString *PTGitReviewAttributedString(NSDictionary<NSString *, NSString *> *snapshot) {
    NSString *error = PTGitReviewString(snapshot[@"error"]);
    NSString *root = PTGitReviewString(snapshot[@"root"]);
    NSString *directory = PTGitReviewString(snapshot[@"directory"]);
    NSString *branch = PTGitReviewString(snapshot[@"branch"]);
    NSString *upstream = PTGitReviewString(snapshot[@"upstream"]);
    NSString *status = PTGitReviewString(snapshot[@"status"]);
    NSString *diff = PTGitReviewString(snapshot[@"diff"]);

    NSFont *bodyFont = [NSFont monospacedSystemFontOfSize:10.8 weight:NSFontWeightRegular];
    NSFont *headerFont = [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold];
    NSFont *titleFont = [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold];
    NSColor *textColor = NSColor.labelColor;
    NSColor *mutedColor = NSColor.secondaryLabelColor;
    NSColor *addedColor = NSColor.systemGreenColor;
    NSColor *removedColor = NSColor.systemRedColor;
    NSColor *addedBackground = [NSColor.systemGreenColor colorWithAlphaComponent:0.11];
    NSColor *removedBackground = [NSColor.systemRedColor colorWithAlphaComponent:0.10];
    NSColor *headerBackground = PTGitReviewDynamicGray(0.93, 0.18);
    NSColor *foldBackground = PTGitReviewDynamicGray(0.96, 0.12);

    NSMutableAttributedString *output = [[NSMutableAttributedString alloc] init];
    if (error.length > 0) {
        PTGitReviewAppend(output, @"Git 审阅不可用\n",
            PTGitReviewAttributes(titleFont, NSColor.systemOrangeColor, nil));
        PTGitReviewAppend(output, [error stringByAppendingString:@"\n"],
            PTGitReviewAttributes(bodyFont, textColor, nil));
        return output;
    }

    NSArray<NSMutableDictionary *> *files = PTGitReviewParseFiles(diff);
    NSArray<NSString *> *statusLines = PTGitReviewLines(status);
    NSUInteger added = 0;
    NSUInteger removed = 0;
    for (NSDictionary *file in files) {
        added += [file[@"added"] unsignedIntegerValue];
        removed += [file[@"removed"] unsignedIntegerValue];
    }
    NSString *branchFlow = branch.length > 0 ? branch : @"HEAD";
    if (upstream.length > 0) branchFlow = [NSString stringWithFormat:@"%@  →  %@", branchFlow, upstream];
    PTGitReviewAppend(output,
        [NSString stringWithFormat:@"分支  %@    +%lu  −%lu\n", branchFlow,
            (unsigned long)added, (unsigned long)removed],
        PTGitReviewAttributes(titleFont, textColor, nil));
    NSString *repoName = root.lastPathComponent.length ? root.lastPathComponent : root;
    NSUInteger fileCount = MAX(files.count, statusLines.count);
    PTGitReviewAppend(output,
        [NSString stringWithFormat:@"%@ · %lu 个变更 · 观察 %@\n\n",
            repoName.length ? repoName : @"Git 仓库", (unsigned long)fileCount,
            directory.length ? directory : root],
        PTGitReviewAttributes([NSFont systemFontOfSize:10 weight:NSFontWeightRegular],
            mutedColor, nil));

    if (files.count == 0 && statusLines.count == 0) {
        PTGitReviewAppend(output, @"✓ 工作树干净，没有需要审阅的改动。\n",
            PTGitReviewAttributes(headerFont, addedColor, headerBackground));
        return output;
    }

    NSMutableSet<NSString *> *renderedPaths = [NSMutableSet set];
    for (NSDictionary *file in files) {
        NSString *path = PTGitReviewString(file[@"path"]);
        if (path.length) [renderedPaths addObject:path];
        PTGitReviewAppend(output,
            [NSString stringWithFormat:@"▾  %@    +%@  −%@\n", path,
                file[@"added"] ?: @0, file[@"removed"] ?: @0],
            PTGitReviewAttributes(headerFont, textColor, headerBackground));
        if ([file[@"binary"] boolValue]) {
            PTGitReviewAppend(output, @"      二进制文件已更改，无法显示逐行内容。\n\n",
                PTGitReviewAttributes(bodyFont, mutedColor, nil));
            continue;
        }

        NSInteger oldLine = 0;
        NSInteger newLine = 0;
        BOOL hasHunk = NO;
        for (NSString *line in file[@"lines"] ?: @[]) {
            if ([line hasPrefix:@"@@"]) {
                NSInteger nextOld = 0;
                NSInteger nextNew = 0;
                if (PTGitReviewReadHunk(line, &nextOld, &nextNew)) {
                    NSInteger unchanged = hasHunk ? nextOld - oldLine : nextOld - 1;
                    if (unchanged > 0) {
                        PTGitReviewAppend(output,
                            [NSString stringWithFormat:@"      ⋯  %ld 行未修改\n", (long)unchanged],
                            PTGitReviewAttributes(bodyFont, mutedColor, foldBackground));
                    }
                    oldLine = nextOld;
                    newLine = nextNew;
                    hasHunk = YES;
                }
                continue;
            }
            if ([line hasPrefix:@"\\ No newline"]) {
                PTGitReviewAppend(output, @"             ↳ 文件末尾没有换行符\n",
                    PTGitReviewAttributes(bodyFont, mutedColor, nil));
                continue;
            }
            if (!hasHunk || line.length == 0) continue;

            unichar kind = [line characterAtIndex:0];
            NSString *content = [line substringFromIndex:1];
            NSString *oldField = @"     ";
            NSString *newField = @"     ";
            NSString *marker = @" ";
            NSColor *background = nil;
            NSColor *markerColor = mutedColor;
            if (kind == '+') {
                newField = [NSString stringWithFormat:@"%5ld", (long)newLine++];
                marker = @"+";
                markerColor = addedColor;
                background = addedBackground;
            } else if (kind == '-') {
                oldField = [NSString stringWithFormat:@"%5ld", (long)oldLine++];
                marker = @"−";
                markerColor = removedColor;
                background = removedBackground;
            } else {
                oldField = [NSString stringWithFormat:@"%5ld", (long)oldLine++];
                newField = [NSString stringWithFormat:@"%5ld", (long)newLine++];
            }
            NSString *rendered = [NSString stringWithFormat:@"%@ %@  %@ %@\n",
                oldField, newField, marker, content];
            NSRange appended = PTGitReviewAppend(output, rendered,
                PTGitReviewAttributes(bodyFont, textColor, background));
            [output addAttribute:NSForegroundColorAttributeName value:mutedColor
                range:NSMakeRange(appended.location, MIN((NSUInteger)11, appended.length))];
            if (appended.length > 13) {
                [output addAttribute:NSForegroundColorAttributeName value:markerColor
                    range:NSMakeRange(appended.location + 13, 1)];
            }
        }
        [output appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }

    for (NSString *line in statusLines) {
        NSDictionary *entry = PTGitReviewStatusEntry(line);
        NSString *path = PTGitReviewString(entry[@"path"]);
        if (path.length == 0 || [renderedPaths containsObject:path]) continue;
        NSString *label = PTGitReviewStatusLabel(PTGitReviewString(entry[@"code"]));
        PTGitReviewAppend(output, [NSString stringWithFormat:@"▸  %@    %@\n", path, label],
            PTGitReviewAttributes(headerFont, textColor, headerBackground));
        PTGitReviewAppend(output,
            [label isEqual:@"未跟踪"]
                ? @"      未跟踪文件尚未进入逐行 diff。\n\n"
                : @"      当前状态没有可显示的逐行内容。\n\n",
            PTGitReviewAttributes(bodyFont, mutedColor, nil));
    }
    return output;
}
