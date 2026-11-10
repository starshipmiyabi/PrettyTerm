#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "PTFrontendBridge.h"

static void PTAssert(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "Assertion failed: %s\n", message.UTF8String);
        exit(1);
    }
}

@interface PTBridgeDelegateProbe : NSObject <PTFrontendBridgeDelegate>
@property(nonatomic, copy, nullable) NSString *lastRequestedLanguage;
@property(nonatomic, copy, nullable) NSString *lastAction;
@property(nonatomic, copy, nullable) NSDictionary *lastPayload;
@property(nonatomic) NSInteger loadCount;
@end

@implementation PTBridgeDelegateProbe
- (void)frontendBridge:(PTFrontendBridge *)bridge didRequestLanguage:(NSString *)languageCode {
    (void)bridge;
    _lastRequestedLanguage = [languageCode copy];
}

- (void)frontendBridge:(PTFrontendBridge *)bridge didReceiveAction:(NSString *)action payload:(NSDictionary *)payload {
    (void)bridge;
    _lastAction = [action copy];
    _lastPayload = [payload copy];
}

- (void)frontendBridgeDidFinishLoad:(PTFrontendBridge *)bridge {
    (void)bridge;
    _loadCount += 1;
}
@end

static void PTRunRunLoopUntil(NSTimeInterval timeoutSeconds, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];
    while (!condition()) {
        if ([deadline timeIntervalSinceNow] <= 0) break;
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *projectDir = argc > 1
            ? [NSString stringWithUTF8String:argv[1]]
            : NSFileManager.defaultManager.currentDirectoryPath;
        NSURL *buildResourceParentURL = [[NSURL fileURLWithPath:projectDir]
            URLByAppendingPathComponent:@"dist/PrettyTerm Beta.app/Contents/Resources" isDirectory:YES];

        PTAssert([PTFrontendBridgeAppearanceString([NSAppearance appearanceNamed:NSAppearanceNameAqua]) isEqualToString:@"light"],
                 @"Aqua must map to light");
        PTAssert([PTFrontendBridgeAppearanceString([NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]) isEqualToString:@"dark"],
                 @"DarkAqua must map to dark");
        PTAssert([PTFrontendBridgeNormalizeLanguage(@"en-US") isEqualToString:@"en"],
                 @"en-US must normalize to en");
        PTAssert([PTFrontendBridgeNormalizeLanguage(@"zh-Hans") isEqualToString:@"zh-Hans"],
                 @"zh-Hans must normalize to zh-Hans");

        PTBridgeDelegateProbe *delegate = [[PTBridgeDelegateProbe alloc] init];
        PTFrontendBridge *mainBridge = [[PTFrontendBridge alloc] initWithSurface:@"main" delegate:delegate];
        PTFrontendBridge *floatingBridge = [[PTFrontendBridge alloc] initWithSurface:@"floating" delegate:delegate];

        WKWebViewConfiguration *mainConfig = [[WKWebViewConfiguration alloc] init];
        WKWebViewConfiguration *floatConfig = [[WKWebViewConfiguration alloc] init];
        [mainBridge configureWebViewConfiguration:mainConfig initialAppearance:@"light" initialLanguage:@"zh-Hans"];
        [floatingBridge configureWebViewConfiguration:floatConfig initialAppearance:@"light" initialLanguage:@"zh-Hans"];

        NSWindow *hostWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(40, 40, 1200, 760)
                                                           styleMask:NSWindowStyleMaskTitled
                                                             backing:NSBackingStoreBuffered
                                                               defer:NO];
        hostWindow.releasedWhenClosed = NO;
        WKWebView *mainWebView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 1200, 760) configuration:mainConfig];
        WKWebView *floatWebView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 440, 540) configuration:floatConfig];
        [hostWindow.contentView addSubview:mainWebView];

        NSWindow *floatWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(900, 80, 440, 540)
                                                            styleMask:NSWindowStyleMaskTitled
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO];
        floatWindow.releasedWhenClosed = NO;
        [floatWindow.contentView addSubview:floatWebView];
        // Streaming is batched on animation frames; both test surfaces must be visible to WebKit.
        NSRunningApplication *previousApplication = NSWorkspace.sharedWorkspace.frontmostApplication;
        [hostWindow makeKeyAndOrderFront:nil];
        [floatWindow orderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];

        [mainBridge attachWebView:mainWebView];
        [floatingBridge attachWebView:floatWebView];

        NSError *loadError = nil;
        PTAssert([mainBridge loadBundledFrontendFromResourceURL:buildResourceParentURL error:&loadError],
                 @"Main bundled frontend must load");
        PTAssert([floatingBridge loadBundledFrontendFromResourceURL:buildResourceParentURL error:&loadError],
                 @"Floating bundled frontend must load");

        PTRunRunLoopUntil(10.0, ^BOOL{
            return mainBridge.frontendReady && floatingBridge.frontendReady;
        });
        PTAssert(mainBridge.frontendReady && floatingBridge.frontendReady, @"Both main and floating WKWebViews must finish navigation");
        PTAssert(delegate.loadCount == 2, @"Both bridges must notify delegate on load");

        [mainBridge pushThemeAppearance:@"dark" language:@"en"];
        [floatingBridge pushThemeAppearance:@"dark" language:@"en"];

        NSDictionary *sampleTranscript = @{
            @"sessionId": @"bridge-test-1",
            @"title": @"Bridge Test",
            @"cwd": projectDir,
            @"model": @"claude-sonnet-5-5",
            @"interfaceLanguage": @"en",
            @"awaitingReply": @YES,
            @"messages": @[
                @{ @"role": @"user", @"messageKey": @"u1", @"text": @"Hello Claude" },
                @{ @"role": @"assistant", @"messageKey": @"a1", @"text": @"Persisted answer $a^2+b^2=c^2$\n\n| A | B |\n| --- | --- |\n| 1 | 2 |" }
            ]
        };
        NSDictionary *sampleStream = @{
            @"active": @YES,
            @"sessionId": @"bridge-test-1",
            @"revision": @1,
            @"messages": @[
                @{ @"role": @"assistant", @"streamID": @"s1", @"streaming": @YES, @"text": @"Live streaming delta" }
            ]
        };
        [mainBridge deliverClaudeSession:sampleTranscript completion:nil];
        [mainBridge deliverClaudeStream:sampleStream];
        [floatingBridge deliverClaudeSession:sampleTranscript completion:nil];
        [floatingBridge deliverClaudeStream:sampleStream];

        __block NSDictionary *mainState = nil;
        __block NSDictionary *floatState = nil;
        __block BOOL replyDone = NO;

        NSString *mainProbeJS =
            @"return (async () => {"
            @"  await document.fonts.ready;"
            @"  const wait = (ms) => new Promise(r => setTimeout(r, ms));"
            @"  for (let i = 0; i < 100 && !(document.querySelector('table') && document.querySelector('[data-pt-chat-list]')?.textContent.includes('Live streaming delta')); i++) await wait(30);"
            @"  const reply = await window.webkit.messageHandlers.prettyTermUI.postMessage({ action: 'setLanguage', language: 'en' });"
            @"  const shell = document.querySelector('[data-pt-main-shell]');"
            @"  const chatList = document.querySelector('[data-pt-chat-list]');"
            @"  const sidebar = document.querySelector('[data-pt-sidebar]');"
            @"  const tabbar = document.querySelector('[data-pt-tabbar]');"
            @"  const composer = document.querySelector('[data-pt-composer-card]');"
            @"  const controlBar = document.querySelector('[data-pt-control-bar]');"
            @"  const working = document.querySelector('[data-pt-working-sidebar]');"
            @"  const chatText = chatList ? chatList.textContent : '';"
            @"  return {"
            @"    surface: shell ? shell.getAttribute('data-pt-surface') : null,"
            @"    theme: document.documentElement.getAttribute('data-theme'),"
            @"    lang: document.documentElement.getAttribute('data-pt-language'),"
            @"    hasSidebar: !!sidebar,"
            @"    hasMath: !!chatList?.querySelector('.katex'),"
            @"    hasTable: !!chatList?.querySelector('table'),"
            @"    hasTabBar: !!tabbar,"
            @"    hasComposer: !!composer,"
            @"    hasControlBar: !!controlBar,"
            @"    hasWorking: !!working,"
            @"    hasPersisted: chatText.includes('Persisted answer'),"
            @"    hasStream: chatText.includes('Live streaming delta'),"
            @"    replyOk: !!(reply && reply.ok)"
            @"  };"
            @"})();";

        NSString *floatProbeJS =
            @"return (async () => {"
            @"  await document.fonts.ready;"
            @"  const wait = (ms) => new Promise(r => setTimeout(r, ms));"
            @"  for (let i = 0; i < 100 && !(document.querySelector('[data-pt-chat-list]')?.textContent.includes('Persisted answer') && document.querySelector('[data-pt-chat-list]')?.textContent.includes('Live streaming delta')); i++) await wait(30);"
            @"  const reply = await window.webkit.messageHandlers.prettyTermUI.postMessage({ action: 'setLanguage', language: 'en' });"
            @"  const root = document.querySelector('[data-pt-floating-root]');"
            @"  const chatList = document.querySelector('[data-pt-chat-list]');"
            @"  const composer = document.querySelector('[data-pt-composer-card]');"
            @"  const chatText = chatList ? chatList.textContent : '';"
            @"  return {"
            @"    surface: root ? root.getAttribute('data-pt-surface') : null,"
            @"    theme: document.documentElement.getAttribute('data-theme'),"
            @"    lang: document.documentElement.getAttribute('data-pt-language'),"
            @"    hasComposer: !!composer,"
            @"    hasPersisted: chatText.includes('Persisted answer'),"
            @"    hasStream: chatText.includes('Live streaming delta'),"
            @"    replyOk: !!(reply && reply.ok)"
            @"  };"
            @"})();";

        [mainWebView callAsyncJavaScript:mainProbeJS arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id res, NSError *err) {
            PTAssert(err == nil && [res isKindOfClass:NSDictionary.class], @"Main probe JS must succeed");
            mainState = res;
            [floatWebView callAsyncJavaScript:floatProbeJS arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id fres, NSError *ferr) {
                PTAssert(ferr == nil && [fres isKindOfClass:NSDictionary.class], @"Floating probe JS must succeed");
                floatState = fres;
                replyDone = YES;
            }];
        }];

        PTRunRunLoopUntil(8.0, ^BOOL{ return replyDone; });
        PTAssert(replyDone, @"JS probes must finish");
        PTAssert([mainState[@"surface"] isEqual:@"main"], @"Main surface mismatch");
        PTAssert([floatState[@"surface"] isEqual:@"floating"], @"Floating surface mismatch");
        PTAssert([mainState[@"theme"] isEqual:@"dark"] && [floatState[@"theme"] isEqual:@"dark"],
                 @"Dark theme snapshot must reach both surfaces");
        PTAssert([mainState[@"lang"] isEqual:@"en"] && [floatState[@"lang"] isEqual:@"en"],
                 @"Language snapshot must reach both surfaces");
        PTAssert([mainState[@"hasSidebar"] boolValue] && [mainState[@"hasTabBar"] boolValue] &&
                 [mainState[@"hasComposer"] boolValue] && [mainState[@"hasControlBar"] boolValue] &&
                 [mainState[@"hasWorking"] boolValue],
                 @"Full main LobeHub desktop shell sections must render");
        PTAssert([mainState[@"hasMath"] boolValue] && [mainState[@"hasTable"] boolValue],
                 @"the packaged rich-content chunk must render math and tables");
        PTAssert([floatState[@"hasComposer"] boolValue], @"Floating composer must render");
        if (![mainState[@"hasPersisted"] boolValue] || ![mainState[@"hasStream"] boolValue]) NSLog(@"Main state: %@", mainState);
        PTAssert([mainState[@"hasPersisted"] boolValue] && [mainState[@"hasStream"] boolValue],
                 @"Main surface must render persisted messages and live stream simultaneously");
        PTAssert([floatState[@"hasPersisted"] boolValue] && [floatState[@"hasStream"] boolValue],
                 @"Floating surface must render persisted messages and live stream simultaneously");
        PTAssert([mainState[@"replyOk"] boolValue] && [floatState[@"replyOk"] boolValue],
                 @"WKScriptMessageHandlerWithReply prettyTermUI must respond");
        PTAssert([delegate.lastRequestedLanguage isEqual:@"en"], @"Delegate must observe language request");

        [mainBridge detach];
        [floatingBridge detach];
        [hostWindow close];
        [floatWindow close];
        [previousApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];

        NSLog(@"PTFrontendBridgeTests passed");
    }
    return 0;
}
