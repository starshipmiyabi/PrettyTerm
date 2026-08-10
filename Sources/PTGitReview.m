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

static NSColor *PTGitReviewDynamicColor(
    CGFloat lightRed, CGFloat lightGreen, CGFloat lightBlue,
    CGFloat darkRed, CGFloat darkGreen, CGFloat darkBlue
) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]];
        BOOL dark = [match isEqual:NSAppearanceNameDarkAqua];
        return [NSColor colorWithSRGBRed:(dark ? darkRed : lightRed)
                                   green:(dark ? darkGreen : lightGreen)
                                    blue:(dark ? darkBlue : lightBlue)
                                   alpha:1.0];
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
    if ([code isEqual:@"??"]) return PTL(@"未跟踪", @"Untracked");
    if ([code containsString:@"A"]) return PTL(@"新增", @"Added");
    if ([code containsString:@"D"]) return PTL(@"删除", @"Deleted");
    if ([code containsString:@"R"]) return PTL(@"重命名", @"Renamed");
    if ([code containsString:@"U"]) return PTL(@"冲突", @"Conflict");
    return PTL(@"已修改", @"Modified");
}

static NSArray<NSString *> *PTTranscriptReviewLines(NSString *value) {
    NSString *normalized = [[PTGitReviewString(value)
        stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    return normalized.length > 0 ? [normalized componentsSeparatedByString:@"\n"] : @[];
}

static NSArray<NSDictionary *> *PTTranscriptReviewDiffRows(
    NSString *oldText,
    NSString *newText
) {
    NSArray<NSString *> *before = PTTranscriptReviewLines(oldText);
    NSArray<NSString *> *after = PTTranscriptReviewLines(newText);
    NSUInteger beforeCount = before.count;
    NSUInteger afterCount = after.count;
    BOOL large = beforeCount > 0 && afterCount > 120000 / beforeCount;
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    if (beforeCount == 0 || afterCount == 0 || large) {
        NSUInteger oldLine = 1;
        NSUInteger newLine = 1;
        for (NSString *line in before) {
            [rows addObject:@{@"type": @"remove", @"text": line, @"old": @(oldLine++)}];
        }
        for (NSString *line in after) {
            [rows addObject:@{@"type": @"add", @"text": line, @"new": @(newLine++)}];
        }
        return rows;
    }

    NSUInteger columns = afterCount + 1;
    NSUInteger *table = calloc((beforeCount + 1) * columns, sizeof(NSUInteger));
    if (!table) {
        for (NSUInteger index = 0; index < beforeCount; index++) {
            [rows addObject:@{@"type": @"remove", @"text": before[index], @"old": @(index + 1)}];
        }
        for (NSUInteger index = 0; index < afterCount; index++) {
            [rows addObject:@{@"type": @"add", @"text": after[index], @"new": @(index + 1)}];
        }
        return rows;
    }
    for (NSInteger i = (NSInteger)beforeCount - 1; i >= 0; i--) {
        for (NSInteger j = (NSInteger)afterCount - 1; j >= 0; j--) {
            NSUInteger index = (NSUInteger)i * columns + (NSUInteger)j;
            if ([before[(NSUInteger)i] isEqual:after[(NSUInteger)j]]) {
                table[index] = table[((NSUInteger)i + 1) * columns + (NSUInteger)j + 1] + 1;
            } else {
                table[index] = MAX(
                    table[((NSUInteger)i + 1) * columns + (NSUInteger)j],
                    table[(NSUInteger)i * columns + (NSUInteger)j + 1]
                );
            }
        }
    }

    NSUInteger i = 0;
    NSUInteger j = 0;
    while (i < beforeCount || j < afterCount) {
        if (i < beforeCount && j < afterCount && [before[i] isEqual:after[j]]) {
            [rows addObject:@{
                @"type": @"context", @"text": before[i], @"old": @(i + 1), @"new": @(j + 1)
            }];
            i++;
            j++;
        } else if (i < beforeCount &&
                   (j >= afterCount || table[(i + 1) * columns + j] >= table[i * columns + j + 1])) {
            [rows addObject:@{@"type": @"remove", @"text": before[i], @"old": @(i + 1)}];
            i++;
        } else {
            [rows addObject:@{@"type": @"add", @"text": after[j], @"new": @(j + 1)}];
            j++;
        }
    }
    free(table);
    return rows;
}

NSAttributedString *PTTranscriptEditReviewAttributedString(
    NSArray<NSDictionary *> *editEvents
) {
    NSFont *bodyFont = [NSFont monospacedSystemFontOfSize:10.8 weight:NSFontWeightRegular];
    NSFont *headerFont = [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold];
    NSFont *titleFont = [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold];
    NSColor *textColor = NSColor.labelColor;
    NSColor *mutedColor = NSColor.secondaryLabelColor;
    NSColor *addedColor = PTGitReviewDynamicColor(0.14, 0.43, 0.22, 0.49, 0.79, 0.55);
    NSColor *removedColor = PTGitReviewDynamicColor(0.67, 0.24, 0.17, 0.96, 0.48, 0.35);
    NSColor *accentColor = PTGitReviewDynamicColor(0.64, 0.28, 0.09, 0.91, 0.54, 0.29);
    NSColor *addedBackground = [addedColor colorWithAlphaComponent:0.12];
    NSColor *removedBackground = [removedColor colorWithAlphaComponent:0.11];
    NSColor *headerBackground = PTGitReviewDynamicColor(0.95, 0.89, 0.79, 0.24, 0.16, 0.10);
    NSColor *foldBackground = PTGitReviewDynamicColor(0.98, 0.94, 0.87, 0.16, 0.11, 0.08);

    NSMutableOrderedSet<NSString *> *pathOrder = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *eventsByPath =
        [NSMutableDictionary dictionary];
    NSUInteger totalAdded = 0;
    NSUInteger totalRemoved = 0;
    for (NSDictionary *event in editEvents ?: @[]) {
        if (![event[@"kind"] isEqual:@"diff"]) continue;
        NSString *path = PTGitReviewString(event[@"filePath"]);
        if (path.length == 0) path = PTL(@"未命名文件", @"Untitled file");
        [pathOrder addObject:path];
        if (!eventsByPath[path]) eventsByPath[path] = [NSMutableArray array];
        [eventsByPath[path] addObject:event];
        for (NSDictionary *row in PTTranscriptReviewDiffRows(event[@"oldText"], event[@"newText"])) {
            if ([row[@"type"] isEqual:@"add"]) totalAdded++;
            else if ([row[@"type"] isEqual:@"remove"]) totalRemoved++;
        }
    }

    NSMutableAttributedString *output = [[NSMutableAttributedString alloc] init];
    PTGitReviewAppend(output,
        [NSString stringWithFormat:PTL(@"本轮本地修改    +%lu  −%lu\n", @"Local Changes This Turn    +%lu  −%lu\n"),
            (unsigned long)totalAdded, (unsigned long)totalRemoved],
        PTGitReviewAttributes(titleFont, textColor, nil));
    PTGitReviewAppend(output,
        [NSString stringWithFormat:PTL(@"来自对话中已记录的 Edit / Write · %lu 个文件 · 未执行 git diff\n\n", @"Recorded Edit / Write events · %lu files · git diff was not run\n\n"),
            (unsigned long)pathOrder.count],
        PTGitReviewAttributes([NSFont systemFontOfSize:10 weight:NSFontWeightRegular],
            accentColor, nil));
    if (pathOrder.count == 0) {
        PTGitReviewAppend(output, PTL(@"这个回合没有可显示的本地修改。\n", @"This turn has no local changes to display.\n"),
            PTGitReviewAttributes(headerFont, mutedColor, headerBackground));
        return output;
    }

    for (NSString *path in pathOrder) {
        NSArray<NSDictionary *> *events = eventsByPath[path];
        NSUInteger fileAdded = 0;
        NSUInteger fileRemoved = 0;
        for (NSDictionary *event in events) {
            for (NSDictionary *row in PTTranscriptReviewDiffRows(event[@"oldText"], event[@"newText"])) {
                if ([row[@"type"] isEqual:@"add"]) fileAdded++;
                else if ([row[@"type"] isEqual:@"remove"]) fileRemoved++;
            }
        }
        PTGitReviewAppend(output,
            [NSString stringWithFormat:@"▾  %@    +%lu  −%lu\n", path,
                (unsigned long)fileAdded, (unsigned long)fileRemoved],
            PTGitReviewAttributes(headerFont, textColor, headerBackground));

        NSUInteger editIndex = 0;
        for (NSDictionary *event in events) {
            editIndex++;
            if (events.count > 1) {
                NSString *toolName = PTGitReviewString(event[@"toolName"]);
                PTGitReviewAppend(output,
                    [NSString stringWithFormat:PTL(@"      变更 %lu · %@\n", @"      Change %lu · %@\n"),
                        (unsigned long)editIndex, toolName.length ? toolName : @"Edit"],
                    PTGitReviewAttributes(bodyFont, mutedColor, foldBackground));
            }
            NSArray<NSDictionary *> *rows = PTTranscriptReviewDiffRows(event[@"oldText"], event[@"newText"]);
            NSUInteger limit = MIN((NSUInteger)5000, rows.count);
            for (NSUInteger rowIndex = 0; rowIndex < limit; rowIndex++) {
                NSDictionary *row = rows[rowIndex];
                NSString *type = row[@"type"];
                NSString *oldField = row[@"old"]
                    ? [NSString stringWithFormat:@"%5lu", (unsigned long)[row[@"old"] unsignedIntegerValue]]
                    : @"     ";
                NSString *newField = row[@"new"]
                    ? [NSString stringWithFormat:@"%5lu", (unsigned long)[row[@"new"] unsignedIntegerValue]]
                    : @"     ";
                NSString *marker = @" ";
                NSColor *background = nil;
                NSColor *markerColor = mutedColor;
                if ([type isEqual:@"add"]) {
                    marker = @"+";
                    background = addedBackground;
                    markerColor = addedColor;
                } else if ([type isEqual:@"remove"]) {
                    marker = @"−";
                    background = removedBackground;
                    markerColor = removedColor;
                }
                NSString *rendered = [NSString stringWithFormat:@"%@ %@  %@ %@\n",
                    oldField, newField, marker, PTGitReviewString(row[@"text"])];
                NSRange appended = PTGitReviewAppend(output, rendered,
                    PTGitReviewAttributes(bodyFont, textColor, background));
                [output addAttribute:NSForegroundColorAttributeName value:mutedColor
                    range:NSMakeRange(appended.location, MIN((NSUInteger)11, appended.length))];
                if (appended.length > 13) {
                    [output addAttribute:NSForegroundColorAttributeName value:markerColor
                        range:NSMakeRange(appended.location + 13, 1)];
                }
            }
            if (rows.count > limit) {
                PTGitReviewAppend(output,
                    [NSString stringWithFormat:PTL(@"      ⋯  片段过大，剩余 %lu 行未显示\n", @"      ⋯  Segment too large; %lu remaining lines hidden\n"),
                        (unsigned long)(rows.count - limit)],
                    PTGitReviewAttributes(bodyFont, mutedColor, foldBackground));
            }
        }
        [output appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    return output;
}

NSAttributedString *PTGitReviewLoadingAttributedString(void) {
    NSDictionary *attributes = PTGitReviewAttributes(
        [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSColor.secondaryLabelColor, nil);
    return [[NSAttributedString alloc] initWithString:PTL(@"正在整理 Git 改动…\n", @"Preparing Git changes…\n")
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
    NSColor *addedColor = PTGitReviewDynamicColor(0.14, 0.43, 0.22, 0.49, 0.79, 0.55);
    NSColor *removedColor = PTGitReviewDynamicColor(0.67, 0.24, 0.17, 0.96, 0.48, 0.35);
    NSColor *addedBackground = [addedColor colorWithAlphaComponent:0.12];
    NSColor *removedBackground = [removedColor colorWithAlphaComponent:0.11];
    NSColor *headerBackground = PTGitReviewDynamicColor(0.95, 0.89, 0.79, 0.24, 0.16, 0.10);
    NSColor *foldBackground = PTGitReviewDynamicColor(0.98, 0.94, 0.87, 0.16, 0.11, 0.08);
    NSColor *accentColor = PTGitReviewDynamicColor(0.64, 0.28, 0.09, 0.91, 0.54, 0.29);

    NSMutableAttributedString *output = [[NSMutableAttributedString alloc] init];
    if (error.length > 0) {
        PTGitReviewAppend(output, PTL(@"Git 审阅不可用\n", @"Git Review Unavailable\n"),
            PTGitReviewAttributes(titleFont, accentColor, nil));
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
        [NSString stringWithFormat:PTL(@"分支  %@    +%lu  −%lu\n", @"Branch  %@    +%lu  −%lu\n"), branchFlow,
            (unsigned long)added, (unsigned long)removed],
        PTGitReviewAttributes(titleFont, textColor, nil));
    NSString *repoName = root.lastPathComponent.length ? root.lastPathComponent : root;
    NSUInteger fileCount = MAX(files.count, statusLines.count);
    PTGitReviewAppend(output,
        [NSString stringWithFormat:PTL(@"%@ · %lu 个变更 · 观察 %@\n\n", @"%@ · %lu changes · observing %@\n\n"),
            repoName.length ? repoName : PTL(@"Git 仓库", @"Git repository"), (unsigned long)fileCount,
            directory.length ? directory : root],
        PTGitReviewAttributes([NSFont systemFontOfSize:10 weight:NSFontWeightRegular],
            mutedColor, nil));

    if (files.count == 0 && statusLines.count == 0) {
        PTGitReviewAppend(output, PTL(@"✓ 工作树干净，没有需要审阅的改动。\n", @"✓ Working tree is clean; there are no changes to review.\n"),
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
            PTGitReviewAppend(output, PTL(@"      二进制文件已更改，无法显示逐行内容。\n\n", @"      Binary file changed; line-by-line content is unavailable.\n\n"),
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
                            [NSString stringWithFormat:PTL(@"      ⋯  %ld 行未修改\n", @"      ⋯  %ld unmodified lines\n"), (long)unchanged],
                            PTGitReviewAttributes(bodyFont, mutedColor, foldBackground));
                    }
                    oldLine = nextOld;
                    newLine = nextNew;
                    hasHunk = YES;
                }
                continue;
            }
            if ([line hasPrefix:@"\\ No newline"]) {
                PTGitReviewAppend(output, PTL(@"             ↳ 文件末尾没有换行符\n", @"             ↳ No newline at end of file\n"),
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
            [label isEqual:PTL(@"未跟踪", @"Untracked")]
                ? PTL(@"      未跟踪文件尚未进入逐行 diff。\n\n", @"      Untracked file is not yet part of the line diff.\n\n")
                : PTL(@"      当前状态没有可显示的逐行内容。\n\n", @"      This status has no line-level content to display.\n\n"),
            PTGitReviewAttributes(bodyFont, mutedColor, nil));
    }
    return output;
}
