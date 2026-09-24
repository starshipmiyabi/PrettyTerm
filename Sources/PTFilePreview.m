#import "PTFilePreview.h"

#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "PTLocalization.h"

static NSString * const PTFilePreviewErrorDomain = @"com.yuuka.prettyterm.file-preview";
static const unsigned long long PTFilePreviewImageByteLimit = 30ull * 1024 * 1024;

static BOOL PTFilePreviewURLIsDirectory(NSURL *url) {
    NSNumber *directory = nil;
    [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
    return directory.boolValue;
}

// Text formats that UTType misclassifies (e.g. .ts as MPEG transport stream) or does not know.
static NSSet<NSString *> *PTFilePreviewTextExtensions(void) {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = [NSSet setWithArray:[@"ts tsx jsx mjs cjs mts cts jsonl ndjson jsonc json5 toml ini cfg conf env properties editorconfig gitignore gitattributes dockerignore npmignore dockerfile fish cu cuh go rs kt kts scala sc lua jl dart vue svelte scss sass less sql graphql gql proto tex bib cls sty plist gradle cmake lock rst srt ass vtt tf hcl nix zig prisma rb r pl pm php ex exs erl hs ml clj el groovy bat ps1 cs fs vb asm s ld mk v sv vhd log csv tsv yaml yml xml" componentsSeparatedByString:@" "]];
    });
    return extensions;
}

static NSSet<NSString *> *PTFilePreviewWebImageExtensions(void) {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"gif", @"webp",
            @"svg", @"bmp", @"ico"]];
    });
    return extensions;
}

static NSError *PTFilePreviewError(NSURL *url, NSInteger code, NSString *description) {
    return [NSError errorWithDomain:PTFilePreviewErrorDomain code:code userInfo:@{
        NSFilePathErrorKey: url.path ?: @"",
        NSLocalizedDescriptionKey: description
    }];
}

static NSString *PTFilePreviewImageDataURL(NSURL *url, NSError **error) {
    NSNumber *size = nil;
    [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (size.unsignedLongLongValue > PTFilePreviewImageByteLimit) {
        if (error) *error = PTFilePreviewError(url, 2,
            PTL(@"图片超过 30 MB，不提供预览", @"Images over 30 MB are not previewed"));
        return nil;
    }

    NSString *extension = url.pathExtension.lowercaseString;
    NSData *data = nil;
    NSString *mimeType = nil;
    if ([PTFilePreviewWebImageExtensions() containsObject:extension]) {
        data = [NSData dataWithContentsOfURL:url options:0 error:error];
        mimeType = [UTType typeWithFilenameExtension:extension].preferredMIMEType;
    } else {
        // WebKit cannot display formats like HEIC or TIFF everywhere; convert the first frame.
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
        if (image) {
            NSMutableData *png = [NSMutableData data];
            CGImageDestinationRef destination = CGImageDestinationCreateWithData(
                (__bridge CFMutableDataRef)png, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
            if (destination) {
                CGImageDestinationAddImage(destination, image, NULL);
                if (CGImageDestinationFinalize(destination)) data = png;
                CFRelease(destination);
            }
            CGImageRelease(image);
        }
        if (source) CFRelease(source);
        mimeType = @"image/png";
    }
    if (data.length == 0 || mimeType.length == 0) {
        if (error && !*error) *error = PTFilePreviewError(url, 3,
            PTL(@"无法解码这张图片", @"This image could not be decoded"));
        return nil;
    }
    return [NSString stringWithFormat:@"data:%@;base64,%@", mimeType,
        [data base64EncodedStringWithOptions:0]];
}

NSString *PTFilePreviewKindForURL(NSURL *url) {
    if (!url.isFileURL || PTFilePreviewURLIsDirectory(url)) return @"unsupported";

    NSString *extension = url.pathExtension.lowercaseString;
    if ([extension isEqual:@"md"] || [extension isEqual:@"markdown"] ||
        [extension isEqual:@"mdown"] || [extension isEqual:@"mkd"]) {
        return @"markdown";
    }
    if ([extension isEqual:@"ipynb"]) return @"notebook";

    if (extension.length > 0) {
        if ([PTFilePreviewTextExtensions() containsObject:extension]) return @"source";
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if ([type conformsToType:UTTypeImage]) return @"image";
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

    if ([kind isEqual:@"image"]) {
        NSString *dataURL = PTFilePreviewImageDataURL(url, error);
        if (!dataURL) return nil;
        return @{
            @"kind": kind,
            @"path": url.path ?: @"",
            @"title": url.lastPathComponent ?: @"",
            @"dataURL": dataURL
        };
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
