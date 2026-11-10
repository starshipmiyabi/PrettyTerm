#import "PTAppearance.h"

const CGFloat PTLayoutToolbarHeight = 44.0;
const CGFloat PTLayoutSidebarDefaultWidth = 248.0;
const CGFloat PTLayoutOverviewWidth = 340.0;
const CGFloat PTLayoutOverviewGutter = 32.0;
const CGFloat PTLayoutPanelDefaultWidth = 360.0;
const CGFloat PTLayoutPanelMinWidth = 300.0;
const CGFloat PTLayoutPanelMaxWidth = 1200.0;
const CGFloat PTLayoutConversationMinWidth = 520.0;
const CGFloat PTLayoutShellMargin = 8.0;
const CGFloat PTLayoutOverlayMargin = 12.0;
const CGFloat PTRadiusXS = 4.0;
const CGFloat PTRadiusSM = 6.0;
const CGFloat PTRadiusDefault = 8.0;
const CGFloat PTRadiusLG = 12.0;
const CGFloat PTControlHeightSM = 28.0;
const CGFloat PTControlHeightDefault = 36.0;
const CGFloat PTFontSizeSM = 12.0;
const CGFloat PTFontSizeBase = 14.0;
const CGFloat PTFontSizeLG = 16.0;
const CGFloat PTFontSizeXL = 20.0;

NSColor *PTDynamicThemeColor(
    CGFloat lightRed, CGFloat lightGreen, CGFloat lightBlue, CGFloat lightAlpha,
    CGFloat darkRed, CGFloat darkGreen, CGFloat darkBlue, CGFloat darkAlpha
) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]];
        BOOL dark = [match isEqual:NSAppearanceNameDarkAqua];
        return [NSColor colorWithSRGBRed:(dark ? darkRed : lightRed)
                                   green:(dark ? darkGreen : lightGreen)
                                    blue:(dark ? darkBlue : lightBlue)
                                   alpha:(dark ? darkAlpha : lightAlpha)];
    }];
}

static NSColor *PTHexColor(uint32_t lightHex, CGFloat lightAlpha, uint32_t darkHex, CGFloat darkAlpha) {
    return PTDynamicThemeColor(
        ((lightHex >> 16) & 0xFF) / 255.0,
        ((lightHex >> 8) & 0xFF) / 255.0,
        (lightHex & 0xFF) / 255.0,
        lightAlpha,
        ((darkHex >> 16) & 0xFF) / 255.0,
        ((darkHex >> 8) & 0xFF) / 255.0,
        (darkHex & 0xFF) / 255.0,
        darkAlpha
    );
}

NSColor *PTThemeColor(PTThemeRole role) {
    switch (role) {
        case PTThemeRoleCanvas:
            return PTHexColor(0xF8F8F8, 1.0, 0x000000, 1.0);
        case PTThemeRoleSurface:
            return PTHexColor(0xFFFFFF, 1.0, 0x0D0D0D, 1.0);
        case PTThemeRoleSurfaceSecondary:
            return PTHexColor(0xFBFBFB, 1.0, 0x070707, 1.0);
        case PTThemeRoleElevated:
            return PTHexColor(0xFFFFFF, 1.0, 0x1A1A1A, 1.0);
        case PTThemeRoleBorder:
            return PTHexColor(0xE3E3E3, 1.0, 0x202020, 1.0);
        case PTThemeRoleBorderSecondary:
            return PTHexColor(0xEEEEEE, 1.0, 0x1A1A1A, 1.0);
        case PTThemeRoleText:
            return PTHexColor(0x080808, 1.0, 0xFFFFFF, 1.0);
        case PTThemeRoleMuted:
            return PTHexColor(0x666666, 1.0, 0xAAAAAA, 1.0);
        case PTThemeRoleTertiary:
            return PTHexColor(0x999999, 1.0, 0x6F6F6F, 1.0);
        case PTThemeRoleFill:
            return PTDynamicThemeColor(0.0, 0.0, 0.0, 0.06, 1.0, 1.0, 1.0, 0.10);
        case PTThemeRoleFillHover:
            return PTDynamicThemeColor(0.0, 0.0, 0.0, 0.08, 1.0, 1.0, 1.0, 0.14);
        case PTThemeRoleFillPressed:
            return PTDynamicThemeColor(0.0, 0.0, 0.0, 0.13, 1.0, 1.0, 1.0, 0.20);
        case PTThemeRolePrimary:
            return PTHexColor(0x222222, 1.0, 0xEEEEEE, 1.0);
        case PTThemeRolePrimaryHover:
            return PTHexColor(0x363636, 1.0, 0xFFFFFF, 1.0);
        case PTThemeRolePrimaryPressed:
            return PTHexColor(0x111111, 1.0, 0xD4D4D4, 1.0);
        case PTThemeRolePrimaryText:
            return PTHexColor(0xFFFFFF, 1.0, 0x080808, 1.0);
        case PTThemeRoleAccent:
            // Keep PrettyTerm warm orange strictly for brand identity and accent badges.
            return PTHexColor(0xC95B1C, 1.0, 0xED8B4A, 1.0);
        case PTThemeRoleSuccess:
            return PTHexColor(0x379D4A, 1.0, 0xC4F042, 1.0);
        case PTThemeRoleWarning:
            return PTHexColor(0xEE9E0B, 1.0, 0xFFB224, 1.0);
        case PTThemeRoleError:
            return PTHexColor(0xEC5E41, 1.0, 0xF4416C, 1.0);
        case PTThemeRoleInfo:
            return PTHexColor(0x0072F5, 1.0, 0x60B1FF, 1.0);
    }
    return NSColor.labelColor;
}
