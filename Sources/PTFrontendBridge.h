#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PTFrontendBridge;

typedef void (^PTFrontendActionReply)(NSDictionary * _Nullable data, NSString * _Nullable error);

@interface PTBridgeDropWebView : WKWebView
@property(nonatomic, copy, nullable) BOOL (^fileDropHandler)(NSArray<NSURL *> *urls);
@end

@protocol PTFrontendBridgeDelegate <NSObject>
@optional
- (void)frontendBridge:(PTFrontendBridge *)bridge didRequestLanguage:(NSString *)languageCode;
- (void)frontendBridge:(PTFrontendBridge *)bridge didReceiveAction:(NSString *)action payload:(NSDictionary *)payload;
- (void)frontendBridge:(PTFrontendBridge *)bridge
       didInvokeAction:(NSString *)action
               payload:(NSDictionary *)payload
                 reply:(PTFrontendActionReply)reply;
- (void)frontendBridgeDidFinishLoad:(PTFrontendBridge *)bridge;
@end

FOUNDATION_EXPORT NSString *PTFrontendBridgeAppearanceString(NSAppearance * _Nullable appearance);
FOUNDATION_EXPORT NSString *PTFrontendBridgeNormalizeLanguage(NSString * _Nullable languageCode);

@interface PTFrontendBridge : NSObject <WKScriptMessageHandlerWithReply, WKNavigationDelegate>

@property(nonatomic, copy, readonly) NSString *surface;
@property(nonatomic, copy, readonly) NSString *appearance;
@property(nonatomic, copy, readonly) NSString *language;
@property(nonatomic, weak, readonly, nullable) WKWebView *webView;
@property(nonatomic, readonly, getter=isFrontendReady) BOOL frontendReady;
@property(nonatomic, readonly) NSUInteger frontendGeneration;
@property(nonatomic, weak, nullable) id<PTFrontendBridgeDelegate> delegate;

- (instancetype)initWithSurface:(NSString *)surface
                       delegate:(nullable id<PTFrontendBridgeDelegate>)delegate;

- (void)configureWebViewConfiguration:(WKWebViewConfiguration *)configuration
                    initialAppearance:(nullable NSString *)appearance
                      initialLanguage:(nullable NSString *)language;

- (void)attachWebView:(WKWebView *)webView;
- (void)detach;

- (BOOL)loadBundledFrontendFromResourceURL:(nullable NSURL *)resourceURL error:(NSError * _Nullable * _Nullable)error;
- (void)pushThemeAppearance:(NSString *)appearance language:(nullable NSString *)language;
- (void)pushLanguage:(NSString *)language;
- (void)pushStateMethod:(NSString *)jsFunctionName payload:(id)payload;
- (void)pushWindowState:(NSDictionary *)windowState;

- (void)deliverClaudeSession:(NSDictionary *)metadata
                  completion:(nullable void (^)(BOOL ok, NSError * _Nullable error))completion;
- (void)deliverClaudeAppend:(NSDictionary *)metadata
                   messages:(NSArray<NSDictionary *> *)messages
                 completion:(nullable void (^)(BOOL ok, NSError * _Nullable error))completion;
- (void)deliverClaudePatch:(NSDictionary *)metadata
                   updates:(NSArray<NSDictionary *> *)updates
                  messages:(NSArray<NSDictionary *> *)messages
                completion:(nullable void (^)(BOOL ok, NSError * _Nullable error))completion;
- (void)deliverClaudeWaiting:(BOOL)waiting;
- (void)deliverClaudeStream:(NSDictionary *)snapshot;

- (NSDictionary<NSString *, id> *)currentWindowStateSnapshot;

@end

NS_ASSUME_NONNULL_END
