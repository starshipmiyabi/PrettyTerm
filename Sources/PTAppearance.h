#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PTThemeRole) {
    PTThemeRoleCanvas,
    PTThemeRoleSurface,
    PTThemeRoleSurfaceSecondary,
    PTThemeRoleElevated,
    PTThemeRoleBorder,
    PTThemeRoleBorderSecondary,
    PTThemeRoleText,
    PTThemeRoleMuted,
    PTThemeRoleTertiary,
    PTThemeRoleFill,
    PTThemeRoleFillHover,
    PTThemeRoleFillPressed,
    PTThemeRolePrimary,
    PTThemeRolePrimaryHover,
    PTThemeRolePrimaryPressed,
    PTThemeRolePrimaryText,
    PTThemeRoleAccent,
    PTThemeRoleSuccess,
    PTThemeRoleWarning,
    PTThemeRoleError,
    PTThemeRoleInfo
};

typedef NS_ENUM(NSInteger, PTButtonTone) {
    PTButtonTonePrimary,
    PTButtonToneNeutral,
    PTButtonToneQuiet,
    PTButtonToneDanger
};

FOUNDATION_EXPORT const CGFloat PTLayoutToolbarHeight;
FOUNDATION_EXPORT const CGFloat PTLayoutSidebarDefaultWidth;
FOUNDATION_EXPORT const CGFloat PTLayoutOverviewWidth;
FOUNDATION_EXPORT const CGFloat PTLayoutOverviewGutter;
FOUNDATION_EXPORT const CGFloat PTLayoutPanelDefaultWidth;
FOUNDATION_EXPORT const CGFloat PTLayoutPanelMinWidth;
FOUNDATION_EXPORT const CGFloat PTLayoutPanelMaxWidth;
FOUNDATION_EXPORT const CGFloat PTLayoutConversationMinWidth;
FOUNDATION_EXPORT const CGFloat PTLayoutShellMargin;
FOUNDATION_EXPORT const CGFloat PTLayoutOverlayMargin;
FOUNDATION_EXPORT const CGFloat PTRadiusXS;
FOUNDATION_EXPORT const CGFloat PTRadiusSM;
FOUNDATION_EXPORT const CGFloat PTRadiusDefault;
FOUNDATION_EXPORT const CGFloat PTRadiusLG;
FOUNDATION_EXPORT const CGFloat PTControlHeightSM;
FOUNDATION_EXPORT const CGFloat PTControlHeightDefault;
FOUNDATION_EXPORT const CGFloat PTFontSizeSM;
FOUNDATION_EXPORT const CGFloat PTFontSizeBase;
FOUNDATION_EXPORT const CGFloat PTFontSizeLG;
FOUNDATION_EXPORT const CGFloat PTFontSizeXL;

FOUNDATION_EXPORT NSColor *PTDynamicThemeColor(
    CGFloat lightRed, CGFloat lightGreen, CGFloat lightBlue, CGFloat lightAlpha,
    CGFloat darkRed, CGFloat darkGreen, CGFloat darkBlue, CGFloat darkAlpha
);

FOUNDATION_EXPORT NSColor *PTThemeColor(PTThemeRole role);

NS_ASSUME_NONNULL_END
