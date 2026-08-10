#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const PTInterfaceLanguageDefaultsKey = @"PTInterfaceLanguage";

NS_INLINE BOOL PTInterfaceLanguageIsEnglish(void) {
    NSString *stored = [NSUserDefaults.standardUserDefaults
        stringForKey:PTInterfaceLanguageDefaultsKey];
    if (stored.length > 0) return [stored isEqualToString:@"en"];
    NSString *preferred = NSLocale.preferredLanguages.firstObject.lowercaseString ?: @"";
    return ![preferred hasPrefix:@"zh"];
}

NS_INLINE NSString *PTInterfaceLanguageCode(void) {
    return PTInterfaceLanguageIsEnglish() ? @"en" : @"zh-Hans";
}

NS_INLINE NSString *PTLocalized(NSString *chinese, NSString *english) {
    return PTInterfaceLanguageIsEnglish() ? english : chinese;
}

#define PTL(chinese, english) PTLocalized((chinese), (english))

NS_ASSUME_NONNULL_END
