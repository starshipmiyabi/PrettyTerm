#import "PTFilePreview.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const PTFilePreviewErrorDomain = @"com.yuuka.prettyterm.file-preview";

static BOOL PTFilePreviewURLIsDirectory(NSURL *url) {
    NSNumber *directory = nil;
    [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
    return directory.boolValue;
}

NSString *PTFilePreviewKindForURL(NSURL *url) {
    if (!url.isFileURL || PTFilePreviewURLIsDirectory(url)) return @"unsupported";

    NSString *extension = url.pathExtension.lowercaseString;
    if ([extension isEqual:@"md"] || [extension isEqual:@"markdown"] ||
        [extension isEqual:@"mdown"] || [extension isEqual:@"mkd"]) {
        return @"markdown";
    }

    if (extension.length > 0) {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if ([type conformsToType:UTTypeText] ||
            [type conformsToType:UTTypeSourceCode] ||
            [type conformsToType:UTTypePlainText]) {
            return @"source";
        }
        return @"unsupported";
    }

    NSStringEncoding encoding = NSUTF8StringEncoding;
    NSString *text = [NSString stringWithContentsOfURL:url usedEncoding:&encoding error:nil];
    return text ? @"source" : @"unsupported";
}

NSDictionary<NSString *, NSString *> *PTFilePreviewPayloadForURL(
    NSURL *url,
    NSError **error
) {
    NSString *kind = PTFilePreviewKindForURL(url);
    if ([kind isEqual:@"unsupported"]) {
        if (error) {
            *error = [NSError errorWithDomain:PTFilePreviewErrorDomain code:1
                userInfo:@{NSFilePathErrorKey: url.path ?: @""}];
        }
        return nil;
    }

    NSStringEncoding encoding = NSUTF8StringEncoding;
    NSString *text = [NSString stringWithContentsOfURL:url usedEncoding:&encoding error:error];
    if (!text) return nil;
    return @{
        @"kind": kind,
        @"path": url.path ?: @"",
        @"title": url.lastPathComponent ?: @"",
        @"text": text
    };
}

NSArray<NSDictionary<NSString *, id> *> *PTFileTreeChildren(
    NSURL *directoryURL,
    NSError **error
) {
    NSArray<NSURL *> *contents = [NSFileManager.defaultManager
        contentsOfDirectoryAtURL:directoryURL
        includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey]
        options:0 error:error];
    if (!contents) return nil;

    NSMutableArray<NSDictionary<NSString *, id> *> *children = [NSMutableArray array];
    for (NSURL *url in contents) {
        NSNumber *directory = nil;
        NSNumber *regular = nil;
        [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        if (!directory.boolValue &&
            (!regular.boolValue || [[PTFilePreviewKindForURL(url) lowercaseString]
                isEqual:@"unsupported"])) {
            continue;
        }
        [children addObject:@{
            @"url": url,
            @"name": url.lastPathComponent ?: url.path,
            @"directory": @(directory.boolValue)
        }];
    }

    [children sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        BOOL leftDirectory = [left[@"directory"] boolValue];
        BOOL rightDirectory = [right[@"directory"] boolValue];
        if (leftDirectory != rightDirectory) {
            return leftDirectory ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"name"] localizedStandardCompare:right[@"name"]];
    }];
    return children;
}
