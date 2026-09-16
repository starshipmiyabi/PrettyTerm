#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <math.h>

static void PTAssert(BOOL condition, NSString *message) {
    if (condition) return;
    NSLog(@"FAIL: %@", message);
    exit(1);
}

static void PTPumpUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

@interface PTViewportNavigationDelegate : NSObject <WKNavigationDelegate>
@property(nonatomic) BOOL ready;
@property(nonatomic, strong) NSError *error;
@end

@implementation PTViewportNavigationDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    self.ready = YES;
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    self.error = error;
}
@end

static id PTEvaluate(WKWebView *webView, NSString *script) {
    __block BOOL finished = NO;
    __block id result = nil;
    __block NSError *failure = nil;
    [webView evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
        result = value;
        failure = error;
        finished = YES;
    }];
    PTPumpUntil(^BOOL { return finished; }, 5.0);
    PTAssert(finished, @"JavaScript evaluation timed out");
    PTAssert(failure == nil, [NSString stringWithFormat:@"JavaScript failed: %@", failure]);
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        PTAssert(argc == 2 || argc == 3, @"expected project directory and optional resource directory");
        NSString *project = [NSString stringWithUTF8String:argv[1]];
        NSURL *htmlURL = [NSURL fileURLWithPath:
            argc == 3 ? [[NSString stringWithUTF8String:argv[2]] stringByAppendingPathComponent:@"index.html"]
                      : [project stringByAppendingPathComponent:@"Resources/index.html"]];
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
        WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 720, 520)
                                                configuration:configuration];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 720, 520)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.title = @"PrettyTerm renderer regression";
        [window.contentView addSubview:webView];
        [window orderFront:nil];
        PTViewportNavigationDelegate *delegate = [[PTViewportNavigationDelegate alloc] init];
        webView.navigationDelegate = delegate;
        [webView loadFileURL:htmlURL allowingReadAccessToURL:[htmlURL URLByDeletingLastPathComponent]];
        PTPumpUntil(^BOOL { return delegate.ready || delegate.error != nil; }, 8.0);
        PTAssert(delegate.ready && delegate.error == nil, @"conversation fixture must load");

        if (NSProcessInfo.processInfo.environment[@"PT_MEMORY_BENCHMARK"]) {
            NSString *fixture = [NSString stringWithContentsOfFile:
                [project stringByAppendingPathComponent:@"Tests/renderer_memory_benchmark.js"]
                encoding:NSUTF8StringEncoding error:nil];
            PTAssert(fixture.length > 0, @"memory benchmark must load");
            PTEvaluate(webView, [fixture stringByAppendingString:@"\nnull;"]);
            __block id result = nil;
            PTPumpUntil(^BOOL {
                result = PTEvaluate(webView, @"window.__ptBenchmarkResult || null");
                return [result isKindOfClass:NSDictionary.class];
            }, 45.0);
            PTAssert([result isKindOfClass:NSDictionary.class], @"memory benchmark must finish rendering");
            NSLog(@"MEMORY_BENCHMARK_READY %@", result);
            PTPumpUntil(^BOOL { return NO; }, 10.0);
            return 0;
        }

        NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
        for (NSUInteger index = 0; index < 48; index++) {
            [messages addObject:@{
                @"role": @"user",
                @"messageKey": [NSString stringWithFormat:@"user-%lu", (unsigned long)index],
                @"text": [NSString stringWithFormat:@"Question %lu", (unsigned long)index]
            }];
            NSMutableString *body = [NSMutableString string];
            for (NSUInteger line = 0; line < 8; line++) {
                [body appendFormat:@"ANCHOR-%02lu-%02lu A deliberately long paragraph forces width-dependent wrapping while keeping every token uniquely identifiable for the viewport regression test.\n",
                    (unsigned long)index, (unsigned long)line];
            }
            [messages addObject:@{
                @"role": @"assistant",
                @"messageKey": [NSString stringWithFormat:@"assistant-%lu", (unsigned long)index],
                @"text": body
            }];
        }
        NSDictionary *session = @{
            @"sessionId": @"viewport-anchor-test",
            @"interfaceLanguage": @"en",
            @"messages": messages
        };
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:session options:0 error:nil];
        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        PTEvaluate(webView, [NSString stringWithFormat:@"window.setClaudeSession(%@).then(() => window.__initialRenderDone = true); true;", json]);
        PTPumpUntil(^BOOL { return [PTEvaluate(webView, @"Boolean(window.__initialRenderDone)") boolValue]; }, 8.0);
        PTEvaluate(webView, @"window.scrollTo(0, document.body.scrollHeight * 0.46); true;");
        NSDate *captureSettle = [NSDate dateWithTimeIntervalSinceNow:0.12];
        while (captureSettle.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        NSDictionary *before = PTEvaluate(webView,
            @"window.__ptViewportAnchor = PrettyTermRenderer.captureViewportAnchor();"
             @"({followBottom: !!window.__ptViewportAnchor.followBottom, top: window.__ptViewportAnchor.top, scrollY: window.scrollY});");
        PTAssert(![before[@"followBottom"] boolValue] && [before[@"scrollY"] doubleValue] > 500.0,
            @"fixture must capture a historical character anchor away from the bottom");

        webView.frame = NSMakeRect(0, 0, 430, 520);
        [webView layoutSubtreeIfNeeded];
        PTEvaluate(webView, @"window.dispatchEvent(new Event('resize')); true;");
        // Offscreen WKWebView throttles requestAnimationFrame. Exercise the same
        // restore routine synchronously after proving the resize hook is installed.
        PTEvaluate(webView, @"PrettyTermRenderer.restoreViewportAnchor(); true;");
        PTPumpUntil(^BOOL {
            NSNumber *restoring = PTEvaluate(webView,
                @"Boolean(PrettyTermRenderer.restoreViewportAnchor && window.__ptViewportAnchor);");
            return restoring.boolValue;
        }, 0.25);
        NSDate *settle = [NSDate dateWithTimeIntervalSinceNow:0.35];
        while (settle.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        NSDictionary *after = PTEvaluate(webView,
            @"(() => {"
             @"const a = window.__ptViewportAnchor;"
             @"const r = document.createRange();"
             @"const n = a.node;"
             @"if (!n || !n.isConnected || n.nodeType !== 3 || !n.length) return {drift: 9999, scrollY: window.scrollY};"
             @"const o = Math.max(0, Math.min(Number(a.offset) || 0, n.length - 1));"
             @"r.setStart(n, o); r.setEnd(n, Math.min(n.length, o + 1));"
             @"return {drift: r.getBoundingClientRect().top - a.top, scrollY: window.scrollY, text:n.textContent, top:a.top, current:r.getBoundingClientRect().top};"
             @"})()");
        double drift = [after[@"drift"] doubleValue];
        if (fabs(drift) >= 4.0) NSLog(@"Anchor diagnostic: %@ -> %@", before, after);
        PTAssert(fabs(drift) < 4.0,
            [NSString stringWithFormat:@"resizing must preserve the same reading character (drift %.2f, scroll %.2f -> %.2f)",
                drift, [before[@"scrollY"] doubleValue], [after[@"scrollY"] doubleValue]]);
        NSString *memoryFixture = [NSString stringWithContentsOfFile:
            [project stringByAppendingPathComponent:@"Tests/renderer_memory_fixture.js"]
            encoding:NSUTF8StringEncoding error:nil];
        PTAssert(memoryFixture.length > 0, @"renderer memory fixture must load");
        PTEvaluate(webView, [memoryFixture stringByAppendingString:@"\nnull;"]);
        __block NSDictionary *memoryResult = nil;
        PTPumpUntil(^BOOL {
            memoryResult = PTEvaluate(webView, @"window.__ptMemoryResult || null;");
            return [memoryResult isKindOfClass:NSDictionary.class];
        }, 15.0);
        PTAssert([memoryResult isKindOfClass:NSDictionary.class], @"renderer memory fixture timed out");
        PTAssert([memoryResult[@"ok"] boolValue],
            [NSString stringWithFormat:@"renderer memory regression: %@", memoryResult]);
        NSLog(@"Renderer memory: %@", memoryResult);
        NSLog(@"PTViewportAnchorTests passed");
    }
    return 0;
}
