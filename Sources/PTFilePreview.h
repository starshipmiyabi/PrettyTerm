#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *PTFilePreviewKindForURL(NSURL *url);

FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable
PTFilePreviewPayloadForURL(NSURL *url, NSError **error);

FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, id> *> * _Nullable
PTFileTreeChildren(NSURL *directoryURL, NSError **error);

NS_ASSUME_NONNULL_END
