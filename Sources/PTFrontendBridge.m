#import "PTFrontendBridge.h"

static NSString * const PTFrontendMessageHandlerName = @"prettyTermUI";

@implementation PTBridgeDropWebView

- (void)awakeFromNib {
    [super awakeFromNib];
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
}

- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration {
    self = [super initWithFrame:frame configuration:configuration];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSArray<NSURL *> *)droppedFileURLsForDraggingInfo:(id<NSDraggingInfo>)sender {
    return [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}] ?: @[];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if (_fileDropHandler && [self droppedFileURLsForDraggingInfo:sender].count > 0) {
        return NSDragOperationCopy;
    }
    return [super draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [self droppedFileURLsForDraggingInfo:sender];
    if (_fileDropHandler && urls.count > 0 && _fileDropHandler(urls)) {
        return YES;
    }
    return [super performDragOperation:sender];
}

@end

NSString *PTFrontendBridgeAppearanceString(NSAppearance * _Nullable appearance) {
    NSAppearance *resolved = appearance ?: NSApp.effectiveAppearance;
    if (!resolved) return @"light";
    NSAppearanceName match = [resolved bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua
    ]];
    return [match isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light";
}

NSString *PTFrontendBridgeNormalizeLanguage(NSString * _Nullable languageCode) {
    if ([languageCode isKindOfClass:NSString.class] &&
        [languageCode.lowercaseString hasPrefix:@"en"]) {
        return @"en";
    }
    return @"zh-Hans";
}

@interface PTWeakReplyHandlerProxy : NSObject <WKScriptMessageHandlerWithReply>
@property(nonatomic, weak) id<WKScriptMessageHandlerWithReply> target;
- (instancetype)initWithTarget:(id<WKScriptMessageHandlerWithReply>)target;
@end

@implementation PTWeakReplyHandlerProxy
- (instancetype)initWithTarget:(id<WKScriptMessageHandlerWithReply>)target {
    self = [super init];
    if (self) _target = target;
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler {
    id<WKScriptMessageHandlerWithReply> strongTarget = _target;
    if (!strongTarget) {
        replyHandler(@{ @"ok": @NO, @"error": @"bridge deallocated" }, nil);
        return;
    }
    [strongTarget userContentController:userContentController
                didReceiveScriptMessage:message
                           replyHandler:replyHandler];
}
@end

@interface PTFrontendBridge ()
@property(nonatomic, copy, readwrite) NSString *surface;
@property(nonatomic, copy, readwrite) NSString *appearance;
@property(nonatomic, copy, readwrite) NSString *language;
@property(nonatomic, weak, readwrite, nullable) WKWebView *webView;
@property(nonatomic, readwrite, getter=isFrontendReady) BOOL frontendReady;
@property(nonatomic, readwrite) NSUInteger frontendGeneration;
@property(nonatomic, strong, nullable) PTWeakReplyHandlerProxy *replyProxy;
@property(nonatomic) BOOL handlerInstalled;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *pendingStateByMethod;
@property(nonatomic, strong) NSMutableOrderedSet<NSString *> *pendingMethodOrder;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *deliveredState;
@property(nonatomic, copy, nullable) NSDictionary *latestWindowState;
@end

@implementation PTFrontendBridge

+ (NSString *)bundleVersionLabel {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSString *shortVer = [info[@"CFBundleShortVersionString"] isKindOfClass:NSString.class]
        ? info[@"CFBundleShortVersionString"] : @"1.0.0";
    NSString *buildVer = [info[@"CFBundleVersion"] isKindOfClass:NSString.class]
        ? info[@"CFBundleVersion"] : @"0";
    return [NSString stringWithFormat:@"%@ (%@)", shortVer, buildVer];
}

+ (NSString *)jsonStringForObject:(id)object {
    if (!object) return @"null";
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return @"null";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"null";
}

- (instancetype)initWithSurface:(NSString *)surface
                       delegate:(nullable id<PTFrontendBridgeDelegate>)delegate {
    self = [super init];
    if (self) {
        _surface = [surface isEqualToString:@"floating"] ? @"floating" : @"main";
        _appearance = PTFrontendBridgeAppearanceString(nil);
        _language = @"zh-Hans";
        _delegate = delegate;
        _pendingStateByMethod = [NSMutableDictionary dictionary];
        _pendingMethodOrder = [NSMutableOrderedSet orderedSet];
        _deliveredState = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    _replyProxy.target = nil;
    _handlerInstalled = NO;
}

- (NSDictionary<NSString *, id> *)currentWindowStateSnapshot {
    NSMutableDictionary *snapshot = [_latestWindowState mutableCopy] ?: [NSMutableDictionary dictionary];
    snapshot[@"surface"] = _surface ?: @"main";
    snapshot[@"appearance"] = _appearance ?: @"light";
    snapshot[@"language"] = _language ?: @"zh-Hans";
    snapshot[@"version"] = [PTFrontendBridge bundleVersionLabel];
    return snapshot;
}

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration
                    initialAppearance:(nullable NSString *)appearance
                      initialLanguage:(nullable NSString *)language {
    if (appearance.length > 0) {
        _appearance = [appearance.lowercaseString containsString:@"dark"] ? @"dark" : @"light";
    }
    if (language.length > 0) {
        _language = PTFrontendBridgeNormalizeLanguage(language);
    }

    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    _replyProxy = [[PTWeakReplyHandlerProxy alloc] initWithTarget:self];
    [configuration.userContentController removeScriptMessageHandlerForName:PTFrontendMessageHandlerName
                                                              contentWorld:WKContentWorld.pageWorld];
    [configuration.userContentController addScriptMessageHandlerWithReply:_replyProxy
                                                             contentWorld:WKContentWorld.pageWorld
                                                                     name:PTFrontendMessageHandlerName];
    _handlerInstalled = YES;

    NSString *snapshotJSON = [PTFrontendBridge jsonStringForObject:[self currentWindowStateSnapshot]];
    NSString *bootScriptSource = [NSString stringWithFormat:
        @"window.__PRETTYTERM_INITIAL_STATE__ = %@;", snapshotJSON];
    WKUserScript *bootScript = [[WKUserScript alloc] initWithSource:bootScriptSource
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:YES];
    [configuration.userContentController addUserScript:bootScript];
}

- (void)attachWebView:(WKWebView *)webView {
    _webView = webView;
    _webView.navigationDelegate = self;
    _frontendReady = NO;
}

- (void)detach {
    WKWebView *webView = _webView;
    if (webView && _handlerInstalled) {
        [webView.configuration.userContentController removeScriptMessageHandlerForName:PTFrontendMessageHandlerName
                                                                          contentWorld:WKContentWorld.pageWorld];
    }
    if (webView.navigationDelegate == self) {
        webView.navigationDelegate = nil;
    }
    _handlerInstalled = NO;
    _frontendReady = NO;
    _webView = nil;
}

- (BOOL)loadBundledFrontendFromResourceURL:(nullable NSURL *)resourceURL
                                     error:(NSError * _Nullable * _Nullable)error {
    NSURL *baseResourceURL = resourceURL ?: NSBundle.mainBundle.resourceURL;
    NSURL *frontendDirURL = [baseResourceURL URLByAppendingPathComponent:@"frontend" isDirectory:YES];
    NSURL *indexURL = [frontendDirURL URLByAppendingPathComponent:@"index.html" isDirectory:NO];
    if (!indexURL || ![NSFileManager.defaultManager fileExistsAtPath:indexURL.path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"PTFrontendBridge"
                                         code:404
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithFormat:
                                             @"Missing bundled frontend at %@", indexURL.path ?: @"(null)"]
                                     }];
        }
        return NO;
    }
    _frontendReady = NO;
    [_webView loadFileURL:indexURL allowingReadAccessToURL:frontendDirURL];
    return YES;
}

- (void)pushThemeAppearance:(NSString *)appearance language:(nullable NSString *)language {
    _appearance = [appearance.lowercaseString containsString:@"dark"] ? @"dark" : @"light";
    if (language.length > 0) {
        _language = PTFrontendBridgeNormalizeLanguage(language);
    }
    [self flushWindowStateToWebView];
}

- (void)pushLanguage:(NSString *)language {
    _language = PTFrontendBridgeNormalizeLanguage(language);
    [self flushWindowStateToWebView];
}

- (void)pushWindowState:(NSDictionary *)windowState {
    _latestWindowState = [windowState copy];
    if ([windowState[@"appearance"] isKindOfClass:NSString.class]) _appearance = windowState[@"appearance"];
    if ([windowState[@"language"] isKindOfClass:NSString.class]) _language = PTFrontendBridgeNormalizeLanguage(windowState[@"language"]);
    [self flushWindowStateToWebView];
}

- (void)flushWindowStateToWebView {
    NSMutableDictionary *window = [[self currentWindowStateSnapshot] mutableCopy];
    NSDictionary *usage = window[@"usage"];
    NSDictionary *settings = window[@"claudeSettings"];
    NSString *status = window[@"statusBanner"];
    [window removeObjectsForKeys:@[@"usage", @"claudeSettings", @"statusBanner"]];
    [self pushStateMethod:@"setPrettyTermWindowState" payload:window];
    if (usage) [self pushStateMethod:@"setPrettyTermUsage" payload:usage];
    if (settings) [self pushStateMethod:@"setPrettyTermClaudeSettings" payload:settings];
    if (status) [self pushStateMethod:@"setPrettyTermStatus" payload:status];
}

- (void)pushStateMethod:(NSString *)jsFunctionName payload:(id)payload {
    if (jsFunctionName.length == 0 || !payload) return;
    if (!_frontendReady || !_webView) {
        _pendingStateByMethod[jsFunctionName] = payload;
        [_pendingMethodOrder addObject:jsFunctionName];
        return;
    }
    BOOL transient = [jsFunctionName isEqual:@"setPrettyTermFilePreview"] ||
        [jsFunctionName isEqual:@"setPrettyTermFileTree"] ||
        [jsFunctionName isEqual:@"setPrettyTermTerminalOutput"];
    if (!transient) {
        if ([_deliveredState[jsFunctionName] isEqual:payload]) return;
        _deliveredState[jsFunctionName] = payload;
    }
    [_webView callAsyncJavaScript:@"if (typeof window[fn] === 'function') { return window[fn](arg); }"
                        arguments:@{@"fn": jsFunctionName, @"arg": payload}
                          inFrame:nil
                   inContentWorld:WKContentWorld.pageWorld
                completionHandler:nil];
}

- (void)deliverClaudeSession:(NSDictionary *)metadata
                  completion:(nullable void (^)(BOOL ok, NSError * _Nullable error))completion {
    if (!_frontendReady || !_webView) {
        if (completion) completion(NO, nil);
        return;
    }
    [_webView callAsyncJavaScript:@"if (window.setClaudeSession) { await window.setClaudeSession(metadata); return 1; } return 0;"
                        arguments:@{@"metadata": metadata ?: @{}}
                          inFrame:nil
                   inContentWorld:WKContentWorld.pageWorld
                completionHandler:^(id result, NSError *error) {
        BOOL ok = !error && [result isKindOfClass:NSNumber.class] && [(NSNumber *)result boolValue];
        if (completion) completion(ok, error);
    }];
}

- (void)deliverClaudeAppend:(NSDictionary *)metadata
                   messages:(NSArray<NSDictionary *> *)messages
                 completion:(nullable void (^)(BOOL ok, NSError * _Nullable error))completion {
    if (!_frontendReady || !_webView) {
        if (completion) completion(NO, nil);
        return;
    }
    [_webView callAsyncJavaScript:
        @"if (!window.__ptSessionMatches || !window.__ptSessionMatches(metadata)) return 0;"
        @"if (window.appendClaudeMessages) await window.appendClaudeMessages(metadata, messages);"
        @"return 1;"
                        arguments:@{@"metadata": metadata ?: @{}, @"messages": messages ?: @[]}
                          inFrame:nil
                   inContentWorld:WKContentWorld.pageWorld
                completionHandler:^(id result, NSError *error) {
        BOOL ok = !error && [result isKindOfClass:NSNumber.class] && [(NSNumber *)result boolValue];
        if (completion) completion(ok, error);
    }];
}

- (void)deliverClaudePatch:(NSDictionary *)metadata
                   updates:(NSArray<NSDictionary *> *)updates
                  messages:(NSArray<NSDictionary *> *)messages
                completion:(nullable void (^)(BOOL ok, NSError * _Nullable error))completion {
    if (!_frontendReady || !_webView) {
        if (completion) completion(NO, nil);
        return;
    }
    [_webView callAsyncJavaScript:
        @"if (!window.__ptSessionMatches || !window.__ptSessionMatches(metadata)) return 0;"
        @"if (window.updateClaudeMessages) await window.updateClaudeMessages(metadata, updates);"
        @"if (messages && messages.length && window.appendClaudeMessages) await window.appendClaudeMessages(metadata, messages);"
        @"return 1;"
                        arguments:@{@"metadata": metadata ?: @{}, @"updates": updates ?: @[], @"messages": messages ?: @[]}
                          inFrame:nil
                   inContentWorld:WKContentWorld.pageWorld
                completionHandler:^(id result, NSError *error) {
        BOOL ok = !error && [result isKindOfClass:NSNumber.class] && [(NSNumber *)result boolValue];
        if (completion) completion(ok, error);
    }];
}

- (void)deliverClaudeWaiting:(BOOL)waiting {
    if (!_frontendReady || !_webView) return;
    [_webView callAsyncJavaScript:@"if (window.setClaudeWaiting) window.setClaudeWaiting(waiting);"
                        arguments:@{@"waiting": @(waiting)}
                          inFrame:nil
                   inContentWorld:WKContentWorld.pageWorld
                completionHandler:nil];
}

- (void)deliverClaudeStream:(NSDictionary *)snapshot {
    if (!_frontendReady || !_webView) return;
    [_webView callAsyncJavaScript:@"if (window.setClaudeStream) window.setClaudeStream(snapshot);"
                        arguments:@{@"snapshot": snapshot ?: @{}}
                          inFrame:nil
                   inContentWorld:WKContentWorld.pageWorld
                completionHandler:nil];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    _frontendReady = NO;
    _frontendGeneration++;
    [_deliveredState removeAllObjects];
}

#pragma mark - WKScriptMessageHandlerWithReply

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
                 replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler {
    (void)userContentController;
    NSDictionary *body = [message.body isKindOfClass:NSDictionary.class] ? message.body : @{};
    NSString *action = [body[@"action"] isKindOfClass:NSString.class] ? body[@"action"] : @"";
    id<PTFrontendBridgeDelegate> delegate = _delegate;

    if ([action isEqualToString:@"frontendReady"]) {
        if (!_frontendReady) {
            _frontendReady = YES;
            NSArray<NSString *> *order = _pendingMethodOrder.array.copy;
            NSDictionary *pending = [_pendingStateByMethod copy];
            [_pendingMethodOrder removeAllObjects];
            [_pendingStateByMethod removeAllObjects];
            if ([delegate respondsToSelector:@selector(frontendBridgeDidFinishLoad:)]) {
                [delegate frontendBridgeDidFinishLoad:self];
            }
            [self flushWindowStateToWebView];
            for (NSString *method in order) {
                if (!_deliveredState[method]) [self pushStateMethod:method payload:pending[method]];
            }
        }
        replyHandler(@{ @"ok": @YES, @"data": @{} }, nil);
        return;
    }

    if ([action isEqualToString:@"ping"]) {
        replyHandler(@{
            @"ok": @YES,
            @"action": @"ping",
            @"data": [self currentWindowStateSnapshot]
        }, nil);
        if ([delegate respondsToSelector:@selector(frontendBridge:didReceiveAction:payload:)]) {
            [delegate frontendBridge:self didReceiveAction:action payload:body];
        }
        return;
    }

    if ([action isEqualToString:@"getWindowState"]) {
        replyHandler(@{
            @"ok": @YES,
            @"data": [self currentWindowStateSnapshot]
        }, nil);
        return;
    }

    if ([action isEqualToString:@"setLanguage"]) {
        NSString *requested = [body[@"language"] isKindOfClass:NSString.class]
            ? PTFrontendBridgeNormalizeLanguage(body[@"language"])
            : _language;
        _language = requested;
        [self flushWindowStateToWebView];
        if ([delegate respondsToSelector:@selector(frontendBridge:didRequestLanguage:)]) {
            [delegate frontendBridge:self didRequestLanguage:requested];
        }
        replyHandler(@{
            @"ok": @YES,
            @"action": @"setLanguage",
            @"data": @{ @"language": requested, @"surface": _surface }
        }, nil);
        return;
    }

    if ([action isEqualToString:@"syncTheme"]) {
        NSString *currentAppearance = _appearance ?: @"light";
        [self flushWindowStateToWebView];
        if ([delegate respondsToSelector:@selector(frontendBridge:didReceiveAction:payload:)]) {
            [delegate frontendBridge:self didReceiveAction:action payload:body];
        }
        replyHandler(@{
            @"ok": @YES,
            @"action": @"syncTheme",
            @"data": @{ @"appearance": currentAppearance, @"surface": _surface }
        }, nil);
        return;
    }

    if ([delegate respondsToSelector:@selector(frontendBridge:didInvokeAction:payload:reply:)]) {
        [delegate frontendBridge:self didInvokeAction:action payload:body reply:^(NSDictionary * _Nullable data, NSString * _Nullable error) {
            if (error.length > 0) {
                replyHandler(@{ @"ok": @NO, @"action": action, @"error": error }, nil);
            } else {
                replyHandler(@{ @"ok": @YES, @"action": action, @"data": data ?: @{} }, nil);
            }
        }];
        return;
    }

    if ([delegate respondsToSelector:@selector(frontendBridge:didReceiveAction:payload:)]) {
        [delegate frontendBridge:self didReceiveAction:action payload:body];
        replyHandler(@{ @"ok": @YES, @"action": action }, nil);
        return;
    }

    replyHandler(@{
        @"ok": @NO,
        @"error": [NSString stringWithFormat:@"Unknown action: %@", action]
    }, nil);
}

@end
