#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <libproc.h>
#import "PTFrontendBridge.h"

// Diagnostic process identity only; production code uses public WebKit APIs.
@interface WKWebView (PTRenderingTestProcess)
- (pid_t)_webProcessIdentifier;
@end

@interface PTRenderingProbe : NSObject <PTFrontendBridgeDelegate, WKScriptMessageHandler>
@property(nonatomic, weak) WKWebView *webView;
@property(nonatomic, strong) NSMutableArray *openedFiles;
@property(nonatomic, copy) NSString *outputDirectory;
@end

@implementation PTRenderingProbe
- (void)frontendBridge:(PTFrontendBridge *)bridge didReceiveAction:(NSString *)action payload:(NSDictionary *)payload {
    (void)bridge;
    if ([action isEqual:@"openTranscriptFile"]) [_openedFiles addObject:payload];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)controller;
    NSMutableDictionary *metrics = [message.body mutableCopy];
    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage(_webView._webProcessIdentifier, RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0) {
        metrics[@"footprintMiB"] = @((double)usage.ri_phys_footprint / 1048576.0);
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:metrics options:0 error:nil];
    printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    fflush(stdout);
    if ([metrics[@"scene"] isEqual:@"git-review-9600-lines"]) {
        [_webView takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
            if (error || !image) return;
            NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [png writeToFile:[self.outputDirectory stringByAppendingPathComponent:@"review-rendering.png"] atomically:YES];
        }];
    }
}
@end

static void PTWait(NSTimeInterval timeout, BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *project = [NSString stringWithUTF8String:argv[1]];
        NSString *resources = [NSString stringWithUTF8String:argv[2]];
        BOOL optimized = argc > 3 && strcmp(argv[3], "--assert") == 0;
        PTRenderingProbe *probe = [PTRenderingProbe new];
        probe.openedFiles = [NSMutableArray array];
        probe.outputDirectory = [project stringByAppendingPathComponent:@".build"];
        PTFrontendBridge *bridge = [[PTFrontendBridge alloc] initWithSurface:@"main" delegate:probe];
        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        [bridge configureWebViewConfiguration:config initialAppearance:@"dark" initialLanguage:@"en"];
        [config.userContentController addScriptMessageHandler:probe name:@"ptPerformance"];
        NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1440, 900)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
        host.releasedWhenClosed = NO;
        WKWebView *web = [[WKWebView alloc] initWithFrame:host.contentView.bounds configuration:config];
        probe.webView = web;
        [host.contentView addSubview:web];
        [host orderBack:nil];
        [bridge attachWebView:web];
        NSError *loadError = nil;
        if (![bridge loadBundledFrontendFromResourceURL:[NSURL fileURLWithPath:resources] error:&loadError]) {
            NSLog(@"%@", loadError); return 1;
        }
        PTWait(15, ^BOOL{ return bridge.frontendReady; });
        if (!bridge.frontendReady) { NSLog(@"Frontend did not load"); return 1; }
        NSString *script = [NSString stringWithContentsOfFile:[project stringByAppendingPathComponent:@"Tests/frontend_rendering_scenarios.js"]
                                                    encoding:NSUTF8StringEncoding error:nil];
        __block BOOL done = NO;
        __block BOOL passed = NO;
        [web callAsyncJavaScript:script arguments:@{@"assertOptimized": @(optimized)} inFrame:nil
                 inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result, NSError *error) {
            passed = error == nil && [result boolValue];
            if (error) NSLog(@"Rendering scenarios failed: %@", error);
            done = YES;
        }];
        PTWait(120, ^BOOL{ return done; });
        if (optimized) {
            passed &= probe.openedFiles.count == 2;
            passed &= [probe.openedFiles.firstObject[@"filePath"] isEqual:@"/tmp/prettyterm-review/src/file-0.ts"];
            passed &= [probe.openedFiles.lastObject[@"filePath"] isEqual:@"/tmp/prettyterm-review/turn-file.ts"];
            for (NSDictionary *payload in probe.openedFiles) {
                passed &= [payload[@"sessionId"] isEqual:@"perf-session"] && [payload[@"tabId"] isEqual:@"perf-tab"];
            }
        }
        [bridge detach];
        [config.userContentController removeScriptMessageHandlerForName:@"ptPerformance"];
        [host close];
        return done && passed ? 0 : 1;
    }
}
