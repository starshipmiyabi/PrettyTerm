#import <AppKit/AppKit.h>
#import "PTFilePreview.h"

static void PTAssert(BOOL condition, NSString *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(1);
}

static NSURL *PTWriteText(NSURL *directory, NSString *name, NSString *text) {
    NSURL *url = [directory URLByAppendingPathComponent:name];
    PTAssert([text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil],
        [NSString stringWithFormat:@"fixture %@ must be written", name]);
    return url;
}

int main(void) {
    @autoreleasepool {
        NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:
                @"PrettyTerm file preview %@", NSUUID.UUID.UUIDString]] isDirectory:YES];
        PTAssert([NSFileManager.defaultManager createDirectoryAtURL:root
            withIntermediateDirectories:YES attributes:nil error:nil],
            @"temporary preview directory must be created");

        NSURL *markdown = PTWriteText(root, @"Guide.md",
            @"# Heading\n\n- first\n- second\n\n$$x^2$$\n");
        NSURL *source = PTWriteText(root, @"Review.m",
            @"NSInteger answer = 42;\nreturn answer;\n");
        NSURL *plain = PTWriteText(root, @"Notes.txt", @"alpha\nbeta\ngamma\n");
        NSURL *extensionless = PTWriteText(root, @"Makefile", @"all:\n\tprintf ok\n");
        NSURL *typescript = PTWriteText(root, @"main.ts", @"const value: number = 1;\n");
        NSURL *toml = PTWriteText(root, @"pyproject.toml", @"[project]\nname = \"pt\"\n");
        NSURL *notebook = PTWriteText(root, @"analysis.ipynb", @"{\"cells\": []}\n");
        NSURL *image = [root URLByAppendingPathComponent:@"photo.png"];
        NSBitmapImageRep *pixels = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:2 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        PTAssert([[pixels representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToURL:image atomically:YES], @"PNG fixture must be written");
        NSURL *tiff = [root URLByAppendingPathComponent:@"scan.tiff"];
        PTAssert([pixels.TIFFRepresentation writeToURL:tiff atomically:YES],
            @"TIFF fixture must be written");
        NSURL *unsupported = [root URLByAppendingPathComponent:@"Slides.pdf"];
        NSData *pdfBytes = [@"%PDF-1.7\n" dataUsingEncoding:NSUTF8StringEncoding];
        PTAssert([pdfBytes writeToURL:unsupported atomically:YES], @"PDF fixture must be written");
        NSURL *nested = [root URLByAppendingPathComponent:@"Sources" isDirectory:YES];
        PTAssert([NSFileManager.defaultManager createDirectoryAtURL:nested
            withIntermediateDirectories:NO attributes:nil error:nil],
            @"nested directory must be created");

        PTAssert([PTFilePreviewKindForURL(markdown) isEqual:@"markdown"],
            @"Markdown must use the rendered preview kind");
        PTAssert([PTFilePreviewKindForURL(source) isEqual:@"source"] &&
                 [PTFilePreviewKindForURL(plain) isEqual:@"source"] &&
                 [PTFilePreviewKindForURL(extensionless) isEqual:@"source"],
            @"source, txt, and decodable extensionless text must use the source preview kind");
        PTAssert([PTFilePreviewKindForURL(unsupported) isEqual:@"unsupported"],
            @"PDF must remain outside the text preview feature");
        PTAssert([PTFilePreviewKindForURL(typescript) isEqual:@"source"] &&
                 [PTFilePreviewKindForURL(toml) isEqual:@"source"],
            @"code files that UTType misclassifies must still use the source preview kind");
        PTAssert([PTFilePreviewKindForURL(notebook) isEqual:@"notebook"],
            @"Jupyter notebooks must use the notebook preview kind");
        PTAssert([PTFilePreviewKindForURL(image) isEqual:@"image"] &&
                 [PTFilePreviewKindForURL(tiff) isEqual:@"image"],
            @"images must use the image preview kind");

        NSError *imageError = nil;
        NSDictionary *imagePayload = PTFilePreviewPayloadForURL(image, &imageError);
        PTAssert(imageError == nil && [imagePayload[@"kind"] isEqual:@"image"] &&
                 [imagePayload[@"dataURL"] hasPrefix:@"data:image/png;base64,"] &&
                 imagePayload[@"text"] == nil,
            @"web images must be embedded as data URLs with their own MIME type");
        NSDictionary *tiffPayload = PTFilePreviewPayloadForURL(tiff, nil);
        PTAssert([tiffPayload[@"dataURL"] hasPrefix:@"data:image/png;base64,"],
            @"non-web image formats must be converted to PNG");

        NSError *payloadError = nil;
        NSDictionary *payload = PTFilePreviewPayloadForURL(markdown, &payloadError);
        PTAssert(payloadError == nil && [payload[@"kind"] isEqual:@"markdown"],
            @"Markdown payload must be produced without changing its kind");
        PTAssert([payload[@"path"] isEqual:markdown.path] &&
                 [payload[@"title"] isEqual:@"Guide.md"] &&
                 [payload[@"text"] isEqual:@"# Heading\n\n- first\n- second\n\n$$x^2$$\n"],
            @"preview payload must preserve the exact path, title, and complete text");

        NSError *treeError = nil;
        NSArray<NSDictionary *> *children = PTFileTreeChildren(root, &treeError);
        PTAssert(treeError == nil, @"previewable directory children must load");
        NSArray *names = [children valueForKey:@"name"];
        PTAssert([names isEqual:@[@"Sources", @"analysis.ipynb", @"Guide.md", @"main.ts",
                                  @"Makefile", @"Notes.txt", @"photo.png", @"pyproject.toml",
                                  @"Review.m", @"scan.tiff"]],
            @"tree must sort directories first and include only previewable files");
        PTAssert(![names containsObject:@"Slides.pdf"],
            @"unsupported files must not enter the preview tree");
        PTAssert([children.firstObject[@"directory"] boolValue] &&
                 [[[children.firstObject[@"url"] URLByResolvingSymlinksInPath] path]
                    isEqual:nested.URLByResolvingSymlinksInPath.path],
            @"directory rows must retain their exact URL and directory identity");

        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        NSLog(@"PTFilePreviewTests passed");
    }
    return 0;
}
