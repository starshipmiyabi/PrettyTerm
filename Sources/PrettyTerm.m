#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <errno.h>
#import <signal.h>
#import <string.h>
#import "PTAgentState.h"
#import "PTAppearance.h"
#import "PTFilePreview.h"
#import "PTFrontendBridge.h"
#import <ImageIO/ImageIO.h>
#import "PTGitReview.h"
#import "PTLocalization.h"
#import "PTUsageMetrics.h"

typedef NS_ENUM(NSInteger, PTAppearanceSurfaceStyle) {
    PTAppearanceSurfaceStyleCanvas,
    PTAppearanceSurfaceStyleCard,
    PTAppearanceSurfaceStyleChip,
    PTAppearanceSurfaceStyleSurface,
    PTAppearanceSurfaceStyleHairline
};

@interface PTAppearanceSurfaceView : NSView
@property(nonatomic) PTAppearanceSurfaceStyle surfaceStyle;
@end

// Finder 被拉到前台后，PrettyTerm 会变成非活动窗口。普通 recessed button 的
// 第一次鼠标按下只负责激活窗口，老师看到的就是“点不动”。这个按钮明确允许
// click-through，让同一次点击既激活窗口也执行定位动作。
@interface PTFirstMouseButton : NSButton
@end

@interface PTAnimatedButton : PTFirstMouseButton
@property(nonatomic, strong) NSColor *fillColor;
@property(nonatomic, strong) NSColor *hoverFillColor;
@property(nonatomic, strong) NSColor *pressedFillColor;
@property(nonatomic, strong) NSColor *strokeColor;
@property(nonatomic, strong, nullable) NSColor *textColor;
@property(nonatomic) CGFloat cornerRadius;
- (void)applyTone:(PTButtonTone)tone;
@end

@interface PTQuestionOptionButton : PTAnimatedButton
- (instancetype)initWithLabel:(NSString *)label
                  description:(NSString *)description
                        index:(NSInteger)index;
@end

@interface PTFlippedView : NSView
@end

@implementation PTFirstMouseButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}
@end

@implementation PTAnimatedButton {
    NSTrackingArea *_trackingArea;
    BOOL _hovered;
    BOOL _pressed;
}

- (void)setImage:(NSImage *)image {
    [super setImage:image];
    if (image && self.title.length == 0) {
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.imageHugsTitle = NO;
        self.alignment = NSTextAlignmentCenter;
    }
}

- (void)syncTitleTextColor {
    if (!self.textColor || self.title.length == 0) return;
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = self.alignment;
    NSFont *font = self.font ?: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:self.title
        attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: self.textColor,
            NSParagraphStyleAttributeName: paragraph
        }];
    [super setAttributedTitle:attributed];
    self.contentTintColor = self.textColor;
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    if (self.image && title.length == 0) {
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.imageHugsTitle = NO;
        self.alignment = NSTextAlignmentCenter;
    } else {
        [self syncTitleTextColor];
    }
}

- (void)setFont:(NSFont *)font {
    [super setFont:font];
    [self syncTitleTextColor];
}

- (void)setTextColor:(NSColor *)textColor {
    _textColor = textColor;
    if (textColor) {
        self.contentTintColor = textColor;
        [self syncTitleTextColor];
    }
    [self setNeedsDisplay:YES];
}

- (void)applyTone:(PTButtonTone)tone {
    switch (tone) {
        case PTButtonTonePrimary:
            self.fillColor = PTThemeColor(PTThemeRolePrimary);
            self.hoverFillColor = PTThemeColor(PTThemeRolePrimaryHover);
            self.pressedFillColor = PTThemeColor(PTThemeRolePrimaryPressed);
            self.strokeColor = PTThemeColor(PTThemeRolePrimary);
            self.textColor = PTThemeColor(PTThemeRolePrimaryText);
            break;
        case PTButtonToneNeutral:
            self.fillColor = PTThemeColor(PTThemeRoleSurface);
            self.hoverFillColor = PTThemeColor(PTThemeRoleFillHover);
            self.pressedFillColor = PTThemeColor(PTThemeRoleFillPressed);
            self.strokeColor = PTThemeColor(PTThemeRoleBorder);
            self.textColor = PTThemeColor(PTThemeRoleText);
            break;
        case PTButtonToneQuiet:
            self.fillColor = NSColor.clearColor;
            self.hoverFillColor = PTThemeColor(PTThemeRoleFill);
            self.pressedFillColor = PTThemeColor(PTThemeRoleFillPressed);
            self.strokeColor = NSColor.clearColor;
            self.textColor = PTThemeColor(PTThemeRoleMuted);
            break;
        case PTButtonToneDanger:
            self.fillColor = PTThemeColor(PTThemeRoleError);
            self.hoverFillColor = PTThemeColor(PTThemeRoleError);
            self.pressedFillColor = PTThemeColor(PTThemeRoleError);
            self.strokeColor = PTThemeColor(PTThemeRoleError);
            self.textColor = NSColor.whiteColor;
            break;
    }
    [self setNeedsDisplay:YES];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.bordered = NO;
        self.focusRingType = NSFocusRingTypeNone;
        self.imagePosition = NSImageLeading;
        self.imageHugsTitle = YES;
        _fillColor = NSColor.clearColor;
        _hoverFillColor = PTThemeColor(PTThemeRoleFill);
        _pressedFillColor = PTThemeColor(PTThemeRoleFillPressed);
        _strokeColor = NSColor.clearColor;
        _cornerRadius = PTRadiusDefault;
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (BOOL)wantsUpdateLayer { return YES; }

- (NSSize)intrinsicContentSize {
    NSSize size = [super intrinsicContentSize];
    BOOL imageOnly = self.image != nil && self.title.length == 0;
    return NSMakeSize(imageOnly ? PTControlHeightSM : MAX(32.0, size.width + 20.0), PTControlHeightSM);
}

- (NSEdgeInsets)alignmentRectInsets {
    return NSEdgeInsetsZero;
}

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *fill = self->_pressed ? self.pressedFillColor
            : (self->_hovered ? self.hoverFillColor : self.fillColor);
        self.layer.backgroundColor = fill.CGColor;
        self.layer.borderColor = self.strokeColor.CGColor;
        self.layer.borderWidth = self.strokeColor == NSColor.clearColor ? 0 : 0.75;
        self.layer.cornerRadius = self.cornerRadius;
        [self syncTitleTextColor];
    }];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    _hovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    _hovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    _pressed = YES;
    [self setNeedsDisplay:YES];
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.10];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    self.layer.transform = CATransform3DMakeScale(0.955, 0.955, 1);
    [CATransaction commit];
    [super mouseDown:event];
    _pressed = NO;
    [self setNeedsDisplay:YES];
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.22];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    self.layer.transform = CATransform3DIdentity;
    [CATransaction commit];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alphaValue = enabled ? 1.0 : 0.42;
    [self setNeedsDisplay:YES];
}

@end

static PTAnimatedButton *PTButtonWithTone(NSString *title, PTButtonTone tone, id target, SEL action) {
    PTAnimatedButton *button = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = title ?: @"";
    button.target = target;
    button.action = action;
    button.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    button.cornerRadius = PTRadiusDefault;
    [button applyTone:tone];
    return button;
}

static PTAnimatedButton *PTWarmButton(NSString *title, id target, SEL action) {
    return PTButtonWithTone(title, PTButtonToneNeutral, target, action);
}

@implementation PTQuestionOptionButton {
    NSTextField *_numberLabel;
    NSTextField *_optionLabel;
    NSTextField *_descriptionLabel;
    NSTextField *_checkLabel;
}

- (instancetype)initWithLabel:(NSString *)label
                  description:(NSString *)description
                        index:(NSInteger)index {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttonType = NSButtonTypePushOnPushOff;
    self.title = @"";
    self.identifier = label;
    self.fillColor = PTThemeColor(PTThemeRoleSurfaceSecondary);
    self.hoverFillColor = PTThemeColor(PTThemeRoleFill);
    self.pressedFillColor = PTThemeColor(PTThemeRoleFillPressed);
    self.strokeColor = PTThemeColor(PTThemeRoleBorder);
    self.cornerRadius = PTRadiusLG;
    self.focusRingType = NSFocusRingTypeNone;
    [self setAccessibilityLabel:description.length > 0
        ? [NSString stringWithFormat:@"%@，%@", label, description] : label];

    _numberLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", (long)index + 1]];
    _numberLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _numberLabel.alignment = NSTextAlignmentCenter;
    _numberLabel.font = [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightBold];
    _numberLabel.wantsLayer = YES;
    _numberLabel.layer.cornerRadius = 9;

    _optionLabel = [NSTextField labelWithString:label];
    _optionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _optionLabel.font = [NSFont systemFontOfSize:13.5 weight:NSFontWeightSemibold];
    _optionLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _descriptionLabel = [NSTextField labelWithString:description ?: @""];
    _descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descriptionLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    _descriptionLabel.textColor = NSColor.secondaryLabelColor;
    _descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _descriptionLabel.maximumNumberOfLines = 2;
    _descriptionLabel.hidden = description.length == 0;

    _checkLabel = [NSTextField labelWithString:@"✓"];
    _checkLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _checkLabel.alignment = NSTextAlignmentCenter;
    _checkLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightBold];

    [self addSubview:_numberLabel];
    [self addSubview:_optionLabel];
    [self addSubview:_descriptionLabel];
    [self addSubview:_checkLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_numberLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [_numberLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_numberLabel.widthAnchor constraintEqualToConstant:28],
        [_numberLabel.heightAnchor constraintEqualToConstant:28],
        [_optionLabel.leadingAnchor constraintEqualToAnchor:_numberLabel.trailingAnchor constant:12],
        [_optionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkLabel.leadingAnchor constant:-10],
        [_checkLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [_checkLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_checkLabel.widthAnchor constraintEqualToConstant:24]
    ]];
    if (description.length > 0) {
        [NSLayoutConstraint activateConstraints:@[
            [_optionLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
            [_descriptionLabel.topAnchor constraintEqualToAnchor:_optionLabel.bottomAnchor constant:2],
            [_descriptionLabel.leadingAnchor constraintEqualToAnchor:_optionLabel.leadingAnchor],
            [_descriptionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkLabel.leadingAnchor constant:-10],
            [_descriptionLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-10],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:62]
        ]];
    } else {
        [_optionLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:54].active = YES;
    }
    [self setNeedsDisplay:YES];
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    // NSView 的 hitTest: 参数位于当前 view 的父视图坐标系；这里若拿 bounds 判断，
    // 所有位置不在父视图原点的按钮都会把真实点击误判为范围外。
    if (self.hidden || !self.enabled || !NSPointInRect(point, self.frame)) return nil;
    return self;
}

- (void)setState:(NSControlStateValue)value {
    [super setState:value];
    [self setNeedsDisplay:YES];
}

- (void)updateLayer {
    [super updateLayer];
    BOOL selected = self.state == NSControlStateValueOn;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        if (selected) {
            self.layer.backgroundColor = PTThemeColor(PTThemeRoleFillHover).CGColor;
            self.layer.borderColor = PTThemeColor(PTThemeRolePrimary).CGColor;
            self.layer.borderWidth = 1.25;
        }
        self->_numberLabel.layer.backgroundColor =
            (selected ? PTThemeColor(PTThemeRolePrimary) : PTThemeColor(PTThemeRoleFill)).CGColor;
        self->_numberLabel.textColor = selected
            ? PTThemeColor(PTThemeRolePrimaryText) : PTThemeColor(PTThemeRoleMuted);
        self->_checkLabel.textColor = selected ? PTThemeColor(PTThemeRolePrimary) : NSColor.clearColor;
    }];
}
@end

@implementation PTFlippedView
- (BOOL)isFlipped { return YES; }
@end

@implementation PTAppearanceSurfaceView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) self.wantsLayer = YES;
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *background = PTThemeColor(PTThemeRoleCanvas);
        NSColor *border = NSColor.clearColor;
        if (self.surfaceStyle == PTAppearanceSurfaceStyleCard) {
            background = PTThemeColor(PTThemeRoleSurface);
            border = PTThemeColor(PTThemeRoleBorder);
        } else if (self.surfaceStyle == PTAppearanceSurfaceStyleChip) {
            background = PTThemeColor(PTThemeRoleSurfaceSecondary);
            border = PTThemeColor(PTThemeRoleBorderSecondary);
        } else if (self.surfaceStyle == PTAppearanceSurfaceStyleSurface) {
            background = PTThemeColor(PTThemeRoleSurface);
            border = NSColor.clearColor;
        } else if (self.surfaceStyle == PTAppearanceSurfaceStyleHairline) {
            background = PTThemeColor(PTThemeRoleBorder);
            border = NSColor.clearColor;
        }
        self.layer.backgroundColor = background.CGColor;
        self.layer.borderColor = border.CGColor;
    }];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}

@end

// 细长的圆角进度条：套餐额度、成本占比这类"一眼看出占比"的场合用它，
// 不用每次都从一堆文字里心算百分比。fillLayer 宽度按 bounds 手算，
// 不依赖 Auto Layout multiplier（multiplier 建好之后不能改，进度变化时得整条重建，麻烦）。
static NSString *PTShortText(NSString *value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class]) return @"";
    // firstPrompt 有时是几十 KB 的粘贴内容；标题预览只处理前 400 个字符，
    // 使下面的空格折叠保持线性规模。
    NSString *value2 = value;
    if (value2.length > 400) {
        NSRange safeRange = [value2 rangeOfComposedCharacterSequenceAtIndex:400];
        value2 = [value2 substringToIndex:NSMaxRange(safeRange)];
    }
    NSString *trimmed = [value2 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    trimmed = [trimmed stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    while ([trimmed containsString:@"  "]) {
        trimmed = [trimmed stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    if (trimmed.length <= limit) return trimmed;
    // substringToIndex: 按 UTF-16 code unit 切，会劈开 emoji 的代理对变乱码；
    // 用 rangeOfComposedCharacterSequenceAtIndex 对齐到完整字符边界。
    NSRange lastCharRange = [trimmed rangeOfComposedCharacterSequenceAtIndex:limit - 1];
    return [[trimmed substringToIndex:NSMaxRange(lastCharRange)] stringByAppendingString:@"…"];
}

static NSUInteger PTTokenCountFromCompactString(NSString *value) {
    NSString *trimmed = [value.lowercaseString
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return 0;
    double multiplier = 1.0;
    if ([trimmed hasSuffix:@"k"]) {
        multiplier = 1000.0;
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    } else if ([trimmed hasSuffix:@"m"]) {
        multiplier = 1000000.0;
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    return (NSUInteger)llround(trimmed.doubleValue * multiplier);
}

static NSString *PTContextCategoryKey(NSString *name) {
    NSString *normalized = [[name stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    // /context 的 Markdown 辅助记录还会列出 deferred 工具；它们没有装入当前
    // 上下文，官方状态图也不把它们算进占用，所以这里保持同一口径。
    if ([normalized containsString:@"deferred"]) return nil;
    NSDictionary<NSString *, NSString *> *keys = @{
        @"system prompt": @"system_prompt",
        @"system tools": @"system_tools",
        @"memory files": @"memory_files",
        @"skills": @"skills",
        @"messages": @"messages",
        @"free space": @"free_space",
        @"autocompact buffer": @"autocompact_buffer"
    };
    return keys[normalized];
}

// Claude Code 会把 /context 的真实结果同时写成 ANSI local-command 输出和
// isMeta Markdown 表。两种都读，轮询撞在两条 JSONL 之间时也不会短暂丢明细。
static NSDictionary *PTContextSnapshotFromText(NSString *text) {
    if (![text isKindOfClass:NSString.class] ||
        [text rangeOfString:@"Context Usage" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return nil;
    }
    static NSRegularExpression *ansiExpression;
    static NSRegularExpression *summaryExpression;
    static NSRegularExpression *tableRowExpression;
    static NSRegularExpression *plainRowExpression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ansiExpression = [NSRegularExpression regularExpressionWithPattern:
            @"\\x1B\\[[0-?]*[ -/]*[@-~]" options:0 error:nil];
        summaryExpression = [NSRegularExpression regularExpressionWithPattern:
            @"([0-9]+(?:\\.[0-9]+)?[kKmM]?)\\s*/\\s*([0-9]+(?:\\.[0-9]+)?[kKmM]?)\\s*(?:tokens\\s*)?\\(([0-9]+(?:\\.[0-9]+)?)%\\)"
            options:NSRegularExpressionCaseInsensitive error:nil];
        tableRowExpression = [NSRegularExpression regularExpressionWithPattern:
            @"^\\|\\s*([^|]+?)\\s*\\|\\s*~?([0-9]+(?:\\.[0-9]+)?[kKmM]?)\\s*\\|\\s*([0-9]+(?:\\.[0-9]+)?)%\\s*\\|\\s*$"
            options:NSRegularExpressionCaseInsensitive error:nil];
        plainRowExpression = [NSRegularExpression regularExpressionWithPattern:
            @"(System prompt|System tools|Memory files|Skills|Messages|Free space|Autocompact buffer):\\s*([0-9]+(?:\\.[0-9]+)?[kKmM]?)\\s*(?:tokens\\s*)?\\(([0-9]+(?:\\.[0-9]+)?)%\\)"
            options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSString *plain = [ansiExpression stringByReplacingMatchesInString:text options:0
        range:NSMakeRange(0, text.length) withTemplate:@""];
    NSTextCheckingResult *summary = [summaryExpression firstMatchInString:plain options:0
        range:NSMakeRange(0, plain.length)];
    if (!summary || summary.numberOfRanges < 4) return nil;
    NSUInteger used = PTTokenCountFromCompactString([plain substringWithRange:[summary rangeAtIndex:1]]);
    NSUInteger window = PTTokenCountFromCompactString([plain substringWithRange:[summary rangeAtIndex:2]]);
    if (used == 0 || window == 0) return nil;

    NSMutableArray<NSDictionary *> *categories = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *line in [plain componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSTextCheckingResult *match = [tableRowExpression firstMatchInString:line options:0
            range:NSMakeRange(0, line.length)];
        if (!match) {
            match = [plainRowExpression firstMatchInString:line options:0
                range:NSMakeRange(0, line.length)];
        }
        if (!match || match.numberOfRanges < 4) continue;
        NSString *name = [line substringWithRange:[match rangeAtIndex:1]];
        NSString *key = PTContextCategoryKey(name);
        if (key.length == 0 || [seen containsObject:key]) continue;
        [seen addObject:key];
        [categories addObject:@{
            @"category": key,
            @"tokens": @(PTTokenCountFromCompactString(
                [line substringWithRange:[match rangeAtIndex:2]])),
            @"percentage": @([[line substringWithRange:[match rangeAtIndex:3]] doubleValue])
        }];
    }
    return @{ @"used": @(used), @"window": @(window), @"categories": categories };
}

static NSString *PTTextFromMessageContent(id content) {
    if ([content isKindOfClass:NSString.class]) return content;
    if (![content isKindOfClass:NSArray.class]) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id block in (NSArray *)content) {
        if (![block isKindOfClass:NSDictionary.class]) continue;
        if ([block[@"type"] isEqual:@"text"] && [block[@"text"] isKindOfClass:NSString.class]) {
            [parts addObject:block[@"text"]];
        }
    }
    return [parts componentsJoinedByString:@"\n"];
}

static NSArray<NSDictionary *> *PTImagesFromMessageContent(id content) {
    if (![content isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *images = [NSMutableArray array];
    for (NSDictionary *block in content) {
        if (![block isKindOfClass:NSDictionary.class] || ![block[@"type"] isEqual:@"image"]) continue;
        NSDictionary *source = block[@"source"];
        if (![source isKindOfClass:NSDictionary.class]) continue;
        if ([source[@"type"] isEqual:@"base64"] && [source[@"data"] isKindOfClass:NSString.class]) {
            NSMutableDictionary *image = [@{
                @"dataUrl": [NSString stringWithFormat:@"data:%@;base64,%@",
                    source[@"media_type"], source[@"data"]]
            } mutableCopy];
            if ([source[@"media_type"] isKindOfClass:NSString.class])
                image[@"mediaType"] = source[@"media_type"];
            [images addObject:[image copy]];
        } else if ([source[@"type"] isEqual:@"url"] && [source[@"url"] isKindOfClass:NSString.class]) {
            [images addObject:@{@"dataUrl": source[@"url"]}];
        }
    }
    return images;
}

static NSArray<NSDictionary *> *PTQuestionUpdates(NSArray<NSDictionary *> *messages) {
    NSMutableArray *updates = [NSMutableArray array];
    for (NSDictionary *message in messages)
        if ([message[@"kind"] isEqual:@"question"] && [message[@"answered"] boolValue]) [updates addObject:message];
    return updates;
}

static NSString *PTAddedWorkingDirectoryFromText(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;
    static NSRegularExpression *ansiExpression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ansiExpression = [NSRegularExpression regularExpressionWithPattern:@"\\x1B\\[[0-?]*[ -/]*[@-~]"
                                                                    options:0
                                                                      error:nil];
    });
    NSString *plain = [ansiExpression stringByReplacingMatchesInString:text
        options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    NSRange prefix = [plain rangeOfString:@"Added "];
    if (prefix.location == NSNotFound) return nil;
    NSUInteger start = NSMaxRange(prefix);
    NSRange suffix = [plain rangeOfString:@" as a working directory for this session"
                                  options:0
                                    range:NSMakeRange(start, plain.length - start)];
    if (suffix.location == NSNotFound || suffix.location <= start) return nil;
    NSString *path = [[plain substringWithRange:NSMakeRange(start, suffix.location - start)]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    path = path.stringByExpandingTildeInPath.stringByStandardizingPath;
    return [path hasPrefix:@"/"] ? path : nil;
}

static void PTRememberObservedPath(NSString *rawPath,
                                   NSMutableOrderedSet<NSString *> *directories) {
    if (![rawPath isKindOfClass:NSString.class] || rawPath.length == 0) return;
    NSString *path = [rawPath stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while (path.length > 1 && [@"\"'`,;)]" containsString:[path substringFromIndex:path.length - 1]]) {
        path = [path substringToIndex:path.length - 1];
    }
    path = [[path stringByReplacingOccurrencesOfString:@"\\ " withString:@" "]
        stringByExpandingTildeInPath].stringByStandardizingPath;
    if (![path hasPrefix:@"/"]) return;
    if ([path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:
        @"*?[]<>|"]].location != NSNotFound) return;

    // 同一个路径在一个会话里会出现成百上千次，每次都 stat 一遍（外置卷上很慢）。
    // 只缓存"找到了目录"的结果；不存在的路径可能之后才被创建，所以不缓存。
    static NSMutableDictionary<NSString *, NSString *> *resolvedDirectories;
    static dispatch_once_t cacheOnce;
    dispatch_once(&cacheOnce, ^{ resolvedDirectories = [NSMutableDictionary dictionary]; });
    NSString *directory = nil;
    @synchronized (resolvedDirectories) { directory = resolvedDirectories[path]; }
    if (directory.length > 1) {
        [directories addObject:directory];
        return;
    }

    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
    if (exists) {
        directory = isDirectory ? path : path.stringByDeletingLastPathComponent;
    } else if (path.pathExtension.length > 0) {
        NSString *parent = path.stringByDeletingLastPathComponent;
        BOOL parentIsDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:parent isDirectory:&parentIsDirectory] &&
            parentIsDirectory) {
            directory = parent;
        }
    }
    if (directory.length > 1) {
        NSString *standardized = directory.stringByStandardizingPath;
        [directories addObject:standardized];
        @synchronized (resolvedDirectories) {
            if (resolvedDirectories.count >= 8192) [resolvedDirectories removeAllObjects];
            resolvedDirectories[path] = standardized;
        }
    }
}

static BOOL PTStoredDirectoryPathIsValid(NSString *path) {
    if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"] || path.length <= 1) {
        return NO;
    }
    if ([path hasPrefix:@"/c/Users/"]) return NO;
    if ([path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:
        @"*?[]<>|;\r\n"]].location != NSNotFound) return NO;
    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
    return (exists && isDirectory) || [path hasPrefix:@"/Volumes/"];
}

static BOOL PTTranscriptKeyNamesPath(NSString *key) {
    NSString *lower = key.lowercaseString ?: @"";
    return [lower isEqual:@"cwd"] || [lower isEqual:@"path"] ||
        [lower hasSuffix:@"path"] || [lower hasSuffix:@"_path"] ||
        [lower hasSuffix:@"directory"] || [lower hasSuffix:@"_dir"] ||
        [lower isEqual:@"dir"];
}

static void PTCollectAbsolutePathsFromCommand(NSString *command,
                                              NSMutableOrderedSet<NSString *> *directories) {
    if (![command isKindOfClass:NSString.class] || command.length == 0) return;
    NSCharacterSet *terminators = [NSCharacterSet characterSetWithCharactersInString:
        @" \t\r\n\"'`|;&<>(){}[]"];
    for (NSUInteger index = 0; index < command.length; index++) {
        if ([command characterAtIndex:index] != '/') continue;
        unichar previous = index > 0 ? [command characterAtIndex:index - 1] : 0;
        BOOL beginsArgument = index == 0 || [[NSCharacterSet whitespaceAndNewlineCharacterSet]
            characterIsMember:previous] || [@"\"'=:(" containsString:[NSString stringWithCharacters:&previous length:1]];
        if (!beginsArgument) continue;

        unichar quote = (previous == '\'' || previous == '"') ? previous : 0;
        NSUInteger end = index;
        while (end < command.length) {
            unichar character = [command characterAtIndex:end];
            if (end > index && ((quote && character == quote) ||
                (!quote && [terminators characterIsMember:character]))) break;
            end++;
        }
        if (end > index) {
            PTRememberObservedPath([command substringWithRange:NSMakeRange(index, end - index)],
                directories);
            index = end;
        }
    }
}

static void PTCollectTranscriptDirectories(id value,
                                           NSString *key,
                                           NSMutableOrderedSet<NSString *> *directories) {
    if ([value isKindOfClass:NSString.class]) {
        if ([key.lowercaseString isEqual:@"command"]) {
            PTCollectAbsolutePathsFromCommand(value, directories);
        } else if (PTTranscriptKeyNamesPath(key)) {
            PTRememberObservedPath(value, directories);
        }
        return;
    }
    if ([value isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)value) {
            PTCollectTranscriptDirectories(item, key, directories);
        }
        return;
    }
    if (![value isKindOfClass:NSDictionary.class]) return;
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id nestedKey, id nestedValue, BOOL *stop) {
        (void)stop;
        NSString *name = [nestedKey isKindOfClass:NSString.class] ? nestedKey : @"";
        // file-history-snapshot stores accessed file paths as dictionary keys.
        if ([name hasPrefix:@"/"]) PTRememberObservedPath(name, directories);
        PTCollectTranscriptDirectories(nestedValue, name, directories);
    }];
}

@interface PTSessionInfo : NSObject
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *cwd;
@property(nonatomic, copy) NSString *filePath;
@property(nonatomic, copy) NSString *model;
@property(nonatomic, copy) NSString *effort;
@property(nonatomic, strong) NSDate *modifiedAt;
@property(nonatomic, strong) NSArray<NSString *> *accessedDirectories;
@property(nonatomic, strong) NSArray<NSDictionary *> *assistantMessages;
@property(nonatomic) NSUInteger conversationTurnCount;
@property(nonatomic) BOOL fullTranscriptLoaded;
@property(nonatomic, strong) NSArray<NSDictionary *> *changedFiles;
@property(nonatomic, strong) NSArray<NSDictionary *> *tasks;
@property(nonatomic) NSUInteger contextUsed;
@property(nonatomic) NSUInteger contextWindow;
@property(nonatomic, strong) NSArray<NSDictionary *> *contextBreakdown;
@property(nonatomic) double apiEquivalentCostUSD;
@property(nonatomic) BOOL apiCostAvailable;
@property(nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *modelUsageBreakdown;
@property(nonatomic) NSUInteger codeLinesAdded;
@property(nonatomic) NSUInteger codeLinesRemoved;
@property(nonatomic, copy) NSString *parseCustomTitle;
@property(nonatomic, copy) NSString *parseGeneratedTitle;
@property(nonatomic, copy) NSString *parseLastPrompt;
@property(nonatomic, copy) NSString *parseFirstPrompt;
@property(nonatomic, strong) NSSet<NSString *> *parseMessageKeys;
@property(nonatomic, strong) NSSet<NSString *> *parseUsageMessageKeys;
@end

@implementation PTSessionInfo
@end

static NSString *const PTUnknownSessionProjectKey =
    @"prettyterm://unknown-session-project";

static NSString *PTSessionProjectKey(PTSessionInfo *session) {
    NSString *path = session.cwd.stringByStandardizingPath;
    return path.length > 0 ? path : PTUnknownSessionProjectKey;
}

static NSString *PTSessionProjectTitle(NSString *projectKey) {
    if ([projectKey isEqual:PTUnknownSessionProjectKey]) {
        return PTL(@"未知项目", @"Unknown project");
    }
    NSString *title = projectKey.lastPathComponent;
    return title.length > 0 ? title : projectKey;
}

static NSUInteger PTConversationTurnCount(NSArray<NSDictionary *> *messages) {
    NSUInteger count = 0;
    for (NSDictionary *message in messages ?: @[]) {
        if ([message[@"role"] isEqual:@"user"]) count++;
    }
    return count;
}

static NSUInteger PTSessionTurnCount(PTSessionInfo *session) {
    if (session.conversationTurnCount || session.assistantMessages.count == 0)
        return session.conversationTurnCount;
    return PTConversationTurnCount(session.assistantMessages);
}

static NSArray<NSDictionary *> *PTLoadTasksForSession(NSString *sessionID) {
    if (!sessionID.length) return @[];
    NSString *tasksDir = [NSHomeDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@".claude/tasks/%@", sessionID]];
    NSArray<NSString *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:tasksDir error:nil];
    if (!files) return @[];
    NSMutableArray<NSDictionary *> *tasks = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file.pathExtension isEqual:@"json"] || [file hasPrefix:@"."]) continue;
        NSString *path = [tasksDir stringByAppendingPathComponent:file];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        NSDictionary *task = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([task isKindOfClass:NSDictionary.class]) [tasks addObject:task];
    }
    [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger idA = [a[@"id"] integerValue];
        NSInteger idB = [b[@"id"] integerValue];
        return idA < idB ? NSOrderedAscending : (idA > idB ? NSOrderedDescending : NSOrderedSame);
    }];
    return tasks;
}

static BOOL PTBytesHavePrefix(const uint8_t *bytes, NSUInteger length, const char *prefix) {
    size_t prefixLength = strlen(prefix);
    return length >= prefixLength && memcmp(bytes, prefix, prefixLength) == 0;
}

static BOOL PTBytesContain(const uint8_t *bytes, NSUInteger length, const char *needle) {
    return memmem(bytes, length, needle, strlen(needle)) != NULL;
}

// 这些记录对会话列表和对话显示都没有用，却占了大会话文件的大部分体积，
// 所以在 JSON 解析之前就直接跳过：
// - api-request / api-request-blob：Claude 把发给 API 的请求原样又存了一遍。
// - 纯 tool_result 的用户记录：只有展开会话时才需要它的内容，列表里只需要
//   cwd，而 cwd 已经读到之后就不用再解析它了。
// 含 "type":"text" 或 "type":"image"（未转义的结构）的记录可能带用户文字，一律照常解析。
static BOOL PTTranscriptLineIsSkippable(const uint8_t *line, NSUInteger length,
                                        BOOL includeMessages, BOOL haveCWD) {
    if (PTBytesHavePrefix(line, length, "{\"type\":\"api-request")) return YES;
    if (includeMessages || !haveCWD) return NO;
    return PTBytesContain(line, length, "\"type\":\"tool_result\"") &&
        !PTBytesContain(line, length, "\"type\":\"text\"") &&
        !PTBytesContain(line, length, "\"type\":\"image\"");
}

static PTSessionInfo *PTParseSessionData(
    NSData *data,
    NSString *filePath,
    NSDate *modifiedAt,
    PTSessionInfo *baseSession,
    BOOL includeMessages
) {
    if (!data) return nil;
    // 按字节逐行解析，不把整个文件转成一个超大 NSString 再切行（大会话文件有
    // 上 GB，那样瞬时内存是文件大小的好几倍）。Claude 还在追加写时，文件末尾
    // 可能截在多字节 UTF-8 字符中间，这一行只会解析失败被跳过，不会拖垮整个
    // session，也就不会让活跃会话在侧栏里"消失"又"回来"。
    const uint8_t *bytes = data.bytes;
    const NSUInteger length = data.length;

    PTSessionInfo *session = [[PTSessionInfo alloc] init];
    session.sessionID = baseSession.sessionID.length
        ? baseSession.sessionID : filePath.lastPathComponent.stringByDeletingPathExtension;
    session.filePath = filePath;
    session.modifiedAt = modifiedAt;
    session.fullTranscriptLoaded = includeMessages;
    session.conversationTurnCount = baseSession.conversationTurnCount;
    session.cwd = baseSession.cwd ?: @"";
    session.model = baseSession.model ?: @"";
    session.effort = baseSession.effort ?: @"";
    session.contextUsed = baseSession.contextUsed;
    session.contextWindow = baseSession ? baseSession.contextWindow : 200000;
    session.contextBreakdown = baseSession.contextBreakdown ?: @[];
    session.apiEquivalentCostUSD = baseSession.apiEquivalentCostUSD;
    session.apiCostAvailable = baseSession.apiCostAvailable;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *modelBreakdown = [NSMutableDictionary dictionary];
    [baseSession.modelUsageBreakdown enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *value, BOOL *_Nonnull stop) {
        (void)stop;
        modelBreakdown[key] = [value mutableCopy];
    }];
    NSUInteger codeLinesAdded = baseSession.codeLinesAdded;
    NSUInteger codeLinesRemoved = baseSession.codeLinesRemoved;

    NSString *customTitle = baseSession.parseCustomTitle ?: @"";
    NSString *generatedTitle = baseSession.parseGeneratedTitle ?: @"";
    NSString *lastPrompt = baseSession.parseLastPrompt ?: @"";
    NSString *firstPrompt = baseSession.parseFirstPrompt ?: @"";
    NSMutableArray<NSDictionary *> *messages = includeMessages && baseSession
        ? [baseSession.assistantMessages mutableCopy] : [NSMutableArray array];
    NSMutableSet<NSString *> *messageKeys = baseSession
        ? [baseSession.parseMessageKeys mutableCopy] : [NSMutableSet set];
    NSMutableSet<NSString *> *usageMessageKeys = baseSession
        ? [baseSession.parseUsageMessageKeys mutableCopy] : [NSMutableSet set];
    NSMutableOrderedSet<NSString *> *accessedDirectories = [NSMutableOrderedSet orderedSetWithArray:
        baseSession.accessedDirectories ?: @[]];

    // AskUserQuestion 事件在被问出来那一刻先以 answered=NO 落进 messages；
    // 老师在 Terminal 里手动作答（或未来 PrettyTerm 里点了 UI 回填）后，
    // transcript 里对应的 tool_result 记录要能原地把这条事件改成 answered=YES，
    // 而不是另起一条新气泡。这个字典按 toolUseId 找到那条事件的可变字典引用。
    NSMutableDictionary<NSString *, NSMutableDictionary *> *questionEventsByToolUseId =
        [NSMutableDictionary dictionary];
    for (NSDictionary *existing in messages) {
        NSString *toolUseId = [existing[@"toolUseId"] isKindOfClass:NSString.class] ? existing[@"toolUseId"] : nil;
        if ([existing[@"kind"] isEqual:@"question"] && toolUseId.length > 0 &&
            [existing isKindOfClass:NSMutableDictionary.class]) {
            questionEventsByToolUseId[toolUseId] = (NSMutableDictionary *)existing;
        }
    }

    NSUInteger position = 0;
    while (position < length) { @autoreleasepool {
        const uint8_t *lineStart = bytes + position;
        const uint8_t *newline = memchr(lineStart, '\n', length - position);
        NSUInteger lineLength = newline ? (NSUInteger)(newline - lineStart) : length - position;
        position += lineLength + 1;
        if (lineLength < 2) continue;
        if (PTTranscriptLineIsSkippable(lineStart, lineLength, includeMessages,
                                        session.cwd.length > 0)) continue;
        NSData *lineData = [NSData dataWithBytesNoCopy:(void *)lineStart
                                                length:lineLength
                                          freeWhenDone:NO];
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
        if (![object isKindOfClass:NSDictionary.class]) continue;

        // Remember every structured directory the Agent actually touches: cwd values,
        // Read/Edit/Write paths, Bash absolute arguments, tool results, and file snapshots.
        if (includeMessages) PTCollectTranscriptDirectories(object, nil, accessedDirectories);

        NSString *type = object[@"type"];
        NSString *objectSessionID = object[@"sessionId"];
        if ([objectSessionID isKindOfClass:NSString.class] && objectSessionID.length > 0) {
            session.sessionID = objectSessionID;
        }
        // 只认第一次出现的 cwd（= Claude 进程真正启动时所在目录，跟 lsof 探测到的
        // OS 级 cwd 是同一个东西）。之前每行都覆盖，Bash 工具在会话中途 cd 到别的
        // 项目目录后，transcript 里记录的 cwd 会跟着漂移，但 Claude 主进程的 OS cwd
        // 从头到尾不会变——用最后一次覆盖的值去跟 lsof 比对，必然对不上。
        NSString *recordedCWD = [object[@"cwd"] isKindOfClass:NSString.class]
            ? [object[@"cwd"] stringByStandardizingPath] : @"";
        if (recordedCWD.length > 0 && [recordedCWD hasPrefix:@"/"]) {
            [accessedDirectories addObject:recordedCWD];
        }
        if (session.cwd.length == 0 && recordedCWD.length > 0) {
            session.cwd = recordedCWD;
        }

        if ([type isEqual:@"system"] && [object[@"content"] isKindOfClass:NSString.class]) {
            NSDictionary *snapshot = PTContextSnapshotFromText(object[@"content"]);
            if (snapshot) {
                session.contextUsed = [snapshot[@"used"] unsignedIntegerValue];
                session.contextWindow = [snapshot[@"window"] unsignedIntegerValue];
                session.contextBreakdown = snapshot[@"categories"] ?: @[];
            }
        }

        if ([type isEqual:@"custom-title"] && [object[@"customTitle"] isKindOfClass:NSString.class]) {
            customTitle = object[@"customTitle"];
        } else if ([type isEqual:@"ai-title"]) {
            NSString *candidate = object[@"title"] ?: object[@"aiTitle"];
            if ([candidate isKindOfClass:NSString.class]) generatedTitle = candidate;
        } else if ([type isEqual:@"last-prompt"] && [object[@"lastPrompt"] isKindOfClass:NSString.class]) {
            lastPrompt = includeMessages ? object[@"lastPrompt"] : PTShortText(object[@"lastPrompt"], 58);
        } else if ([type isEqual:@"user"]) {
            if ([object[@"isSidechain"] boolValue]) continue;
            NSDictionary *message = object[@"message"];
            if (![message isKindOfClass:NSDictionary.class]) continue; // transcript 消息只处理字典记录

            // Edit/MultiEdit 结果自带 structuredPatch（标准 unified diff hunk），
            // 直接数 +/- 行数，跟 git diff --numstat 是同一套口径。
            NSDictionary *toolUseResult = [object[@"toolUseResult"] isKindOfClass:NSDictionary.class]
                ? object[@"toolUseResult"] : nil;
            NSArray *structuredPatch = [toolUseResult[@"structuredPatch"] isKindOfClass:NSArray.class]
                ? toolUseResult[@"structuredPatch"] : nil;
            NSString *patchKey = [NSString stringWithFormat:@"%@:patch", object[@"uuid"] ?: @""];
            if (includeMessages && structuredPatch.count > 0 && object[@"uuid"] && ![messageKeys containsObject:patchKey]) {
                [messageKeys addObject:patchKey];
                for (NSDictionary *hunk in structuredPatch) {
                    NSArray *hunkLines = [hunk[@"lines"] isKindOfClass:NSArray.class] ? hunk[@"lines"] : nil;
                    for (NSString *lineText in hunkLines) {
                        if (![lineText isKindOfClass:NSString.class] || lineText.length == 0) continue;
                        unichar marker = [lineText characterAtIndex:0];
                        if (marker == '+') codeLinesAdded++;
                        else if (marker == '-') codeLinesRemoved++;
                    }
                }
            }

            id rawContent = message[@"content"];
            if (includeMessages && [rawContent isKindOfClass:NSArray.class]) {
                NSUInteger resultIndex = 0;
                for (NSDictionary *block in (NSArray *)rawContent) {
                    if (![block isKindOfClass:NSDictionary.class] ||
                        ![block[@"type"] isEqual:@"tool_result"]) {
                        resultIndex++;
                        continue;
                    }
                    NSString *toolUseId = [block[@"tool_use_id"] isKindOfClass:NSString.class]
                        ? block[@"tool_use_id"] : nil;
                    NSMutableDictionary *questionEvent = toolUseId ? questionEventsByToolUseId[toolUseId] : nil;
                    if (questionEvent) {
                        // 回答落在这里：不新起一条工具结果气泡，直接原地改已经在 messages
                        // 里的那条 question 事件。answers 字典比 content 里那段面向模型的
                        // 提示语干净得多，优先用它拼展示文本。
                        NSDictionary *answers = [toolUseResult[@"answers"] isKindOfClass:NSDictionary.class]
                            ? toolUseResult[@"answers"] : nil;
                        questionEvent[@"answered"] = @YES;
                        questionEvent[@"answerText"] = answers.count > 0
                            ? PTFormattedQuestionAnswers(answers)
                            : (PTEventFromToolResultBlock(block, @"", @"")[@"text"] ?: @"");
                        resultIndex++;
                        continue;
                    }
                    NSString *uuid = object[@"uuid"] ?: message[@"id"] ?: NSUUID.UUID.UUIDString;
                    NSString *key = [NSString stringWithFormat:@"%@:result:%lu",
                        uuid, (unsigned long)resultIndex];
                    NSDictionary *event = PTEventFromToolResultBlock(
                        block, key, object[@"timestamp"] ?: @"");
                    if (event && ![messageKeys containsObject:key]) {
                        [messageKeys addObject:key];
                        [messages addObject:event];
                    }
                    resultIndex++;
                }
            }
            NSString *text = PTTextFromMessageContent(message[@"content"]);
            NSArray<NSString *> *images = includeMessages
                ? PTImagesFromMessageContent(rawContent) : @[];
            BOOL hasImage = images.count > 0;
            if (!includeMessages && [rawContent isKindOfClass:NSArray.class]) {
                for (NSDictionary *block in (NSArray *)rawContent) {
                    NSDictionary *imageSource = [block isKindOfClass:NSDictionary.class] &&
                        [block[@"type"] isEqual:@"image"] ? block[@"source"] : nil;
                    if ([imageSource isKindOfClass:NSDictionary.class] &&
                        (([imageSource[@"type"] isEqual:@"base64"] &&
                          [imageSource[@"data"] isKindOfClass:NSString.class]) ||
                         ([imageSource[@"type"] isEqual:@"url"] &&
                          [imageSource[@"url"] isKindOfClass:NSString.class]))) {
                        hasImage = YES;
                        break;
                    }
                }
            }
            NSDictionary *contextSnapshot = PTContextSnapshotFromText(text);
            if (contextSnapshot) {
                session.contextUsed = [contextSnapshot[@"used"] unsignedIntegerValue];
                session.contextWindow = [contextSnapshot[@"window"] unsignedIntegerValue];
                session.contextBreakdown = contextSnapshot[@"categories"] ?: @[];
            }
            NSString *addedDirectory = PTAddedWorkingDirectoryFromText(text);
            if (addedDirectory.length > 0) [accessedDirectories addObject:addedDirectory];
            BOOL isMeta = [object[@"isMeta"] boolValue];
            if (firstPrompt.length == 0 && text.length > 0 && !isMeta) {
                firstPrompt = includeMessages ? text : PTShortText(text, 58);
            }
            // 图片消息也是完整的用户回合；工具结果没有顶层文字或图片。
            if ((text.length > 0 || hasImage) && !isMeta) {
                NSString *uuid = object[@"uuid"] ?: message[@"id"] ?: NSUUID.UUID.UUIDString;
                NSString *key = [NSString stringWithFormat:@"%@:user", uuid];
                if (![messageKeys containsObject:key]) {
                    [messageKeys addObject:key];
                    session.conversationTurnCount++;
                    if (includeMessages) {
                        [messages addObject:@{
                            @"messageKey": key,
                            @"text": text,
                            @"images": images,
                            @"timestamp": object[@"timestamp"] ?: @"",
                            @"role": @"user"
                        }];
                    }
                }
            }
        } else if ([type isEqual:@"assistant"]) {
            NSDictionary *message = object[@"message"];
            if (![message isKindOfClass:NSDictionary.class] || ![message[@"role"] isEqual:@"assistant"]) continue;
            NSString *model = [message[@"model"] isKindOfClass:NSString.class] ? message[@"model"] : @"";
            if ([model isEqual:@"<synthetic>"]) continue;
            NSDictionary *usage = message[@"usage"];
            NSString *usageKey = object[@"requestId"] ?: message[@"id"];
            NSDictionary *rowUsage = nil;
            if ([usage isKindOfClass:NSDictionary.class]) {
                BOOL costSupported = NO;
                NSDate *pricingDate = PTDateFromClaudeAPIString(object[@"timestamp"]) ?: NSDate.date;
                PTAPIUsageCost rowCost = PTAPIEquivalentCostBreakdownForUsage(model, usage, pricingDate, &costSupported);
                unsigned long long inTok = [usage[@"input_tokens"] unsignedLongLongValue];
                unsigned long long outTok = [usage[@"output_tokens"] unsignedLongLongValue];
                unsigned long long cacheReadTok = [usage[@"cache_read_input_tokens"] unsignedLongLongValue];
                unsigned long long cacheWriteTok = [usage[@"cache_creation_input_tokens"] unsignedLongLongValue];
                NSMutableDictionary *meta = [@{
                    @"usageId": usageKey.length ? usageKey : (object[@"uuid"] ?: @""),
                    @"outputTokens": @(outTok),
                    @"totalTokens": @(inTok + outTok + cacheReadTok + cacheWriteTok)
                } mutableCopy];
                if (costSupported) meta[@"costUSD"] = @(rowCost.total);
                rowUsage = meta;

                if (usageKey.length > 0 && ![usageMessageKeys containsObject:usageKey]) {
                    [usageMessageKeys addObject:usageKey];
                    NSString *modelKey = model.length ? model : @"unknown";
                    NSMutableDictionary *entry = modelBreakdown[modelKey];
                    if (!entry) modelBreakdown[modelKey] = entry = [NSMutableDictionary dictionary];
                    entry[@"input"] = @([entry[@"input"] unsignedLongLongValue] + inTok);
                    entry[@"output"] = @([entry[@"output"] unsignedLongLongValue] + outTok);
                    entry[@"cacheRead"] = @([entry[@"cacheRead"] unsignedLongLongValue] + cacheReadTok);
                    entry[@"cacheWrite"] = @([entry[@"cacheWrite"] unsignedLongLongValue] + cacheWriteTok);
                    if (costSupported) {
                        session.apiEquivalentCostUSD += rowCost.total;
                        session.apiCostAvailable = YES;
                        entry[@"cost"] = @([entry[@"cost"] doubleValue] + rowCost.total);
                        entry[@"inputCost"] = @([entry[@"inputCost"] doubleValue] + rowCost.input);
                        entry[@"outputCost"] = @([entry[@"outputCost"] doubleValue] + rowCost.output);
                        entry[@"cacheReadCost"] = @([entry[@"cacheReadCost"] doubleValue] + rowCost.cacheRead);
                        entry[@"cacheWriteCost"] = @([entry[@"cacheWriteCost"] doubleValue] + rowCost.cacheWrite);
                    }
                }
            }
            if ([object[@"isSidechain"] boolValue] || [object[@"isApiErrorMessage"] boolValue]) continue;
            NSString *effort = [object[@"effort"] isKindOfClass:NSString.class] ? object[@"effort"] : @"";
            if (effort.length > 0) session.effort = effort;
            if ([model isKindOfClass:NSString.class] && model.length > 0) {
                session.model = model;
                NSString *lowerModel = model.lowercaseString;
                if ([lowerModel containsString:@"sonnet-5"] ||
                    [lowerModel containsString:@"opus-5"] ||
                    [lowerModel containsString:@"fable-5"]) {
                    session.contextWindow = 1000000;
                } else {
                    session.contextWindow = 200000;
                }
            }
            if ([usage isKindOfClass:NSDictionary.class]) {
                session.contextUsed =
                    [usage[@"input_tokens"] unsignedIntegerValue] +
                    [usage[@"cache_creation_input_tokens"] unsignedIntegerValue] +
                    [usage[@"cache_read_input_tokens"] unsignedIntegerValue];
            }

            if (!includeMessages) continue;
            NSArray *content = message[@"content"];
            if (![content isKindOfClass:NSArray.class]) continue;
            NSUInteger blockIndex = 0;
            for (NSDictionary *block in content) {
                if (![block isKindOfClass:NSDictionary.class]) {
                    blockIndex++;
                    continue;
                }
                NSString *blockType = block[@"type"];
                NSString *uuid = object[@"uuid"] ?: message[@"id"] ?: NSUUID.UUID.UUIDString;
                NSString *key = [NSString stringWithFormat:@"%@:%lu", uuid, (unsigned long)blockIndex];
                if ([messageKeys containsObject:key]) {
                    blockIndex++;
                    continue;
                }

                if ([blockType isEqual:@"text"]) {
                    NSString *text = block[@"text"];
                    if (![text isKindOfClass:NSString.class] || text.length == 0) {
                        blockIndex++;
                        continue;
                    }
                    [messageKeys addObject:key];
                    NSMutableDictionary *textEvent = [@{
                        @"messageKey": key,
                        @"text": text,
                        @"timestamp": object[@"timestamp"] ?: @"",
                        @"model": model ?: @"Claude",
                        @"role": @"assistant"
                    } mutableCopy];
                    if (rowUsage) [textEvent addEntriesFromDictionary:rowUsage];
                    [messages addObject:textEvent];
                    blockIndex++;
                    continue;
                }

                NSDictionary *event = PTEventFromAssistantBlock(
                    block, key, object[@"timestamp"] ?: @"", model ?: @"Claude");
                if (event) {
                    if (rowUsage && [event isKindOfClass:NSMutableDictionary.class]) {
                        [(NSMutableDictionary *)event addEntriesFromDictionary:rowUsage];
                    }
                    [messageKeys addObject:key];
                    [messages addObject:event];
                    NSString *toolUseId = [event[@"toolUseId"] isKindOfClass:NSString.class]
                        ? event[@"toolUseId"] : nil;
                    if ([event[@"kind"] isEqual:@"question"] && toolUseId.length > 0 &&
                        [event isKindOfClass:NSMutableDictionary.class]) {
                        questionEventsByToolUseId[toolUseId] = (NSMutableDictionary *)event;
                    }
                }
                blockIndex++;
            }
        }
    } }

    NSString *title = customTitle.length ? customTitle :
        (generatedTitle.length ? generatedTitle :
        (lastPrompt.length ? lastPrompt : firstPrompt));
    session.title = PTShortText(title.length ? title : @"未命名会话", 58);
    session.parseCustomTitle = customTitle;
    session.parseGeneratedTitle = generatedTitle;
    session.parseLastPrompt = lastPrompt;
    session.parseFirstPrompt = firstPrompt;
    session.parseMessageKeys = messageKeys;
    session.parseUsageMessageKeys = usageMessageKeys;
    session.modelUsageBreakdown = modelBreakdown;
    session.codeLinesAdded = codeLinesAdded;
    session.codeLinesRemoved = codeLinesRemoved;
    session.accessedDirectories = accessedDirectories.array;
    session.assistantMessages = messages;
    session.changedFiles = includeMessages ? PTAggregateChangedFiles(messages) : @[];
    session.tasks = PTLoadTasksForSession(session.sessionID);
    if (session.assistantMessages.count == 0 && session.conversationTurnCount == 0 &&
        firstPrompt.length == 0 && customTitle.length == 0) {
        return nil;
    }
    return session;
}

static NSUInteger PTCompleteJSONLLength(NSData *data) {
    if (data.length == 0) return 0;
    const uint8_t *bytes = data.bytes;
    NSUInteger lastNewline = NSNotFound;
    for (NSUInteger index = data.length; index > 0; index--) {
        if (bytes[index - 1] == '\n') {
            lastNewline = index;
            break;
        }
    }
    if (lastNewline == data.length) return data.length;
    NSUInteger tailStart = lastNewline == NSNotFound ? 0 : lastNewline;
    NSData *tail = [data subdataWithRange:NSMakeRange(tailStart, data.length - tailStart)];
    id object = tail.length
        ? [NSJSONSerialization JSONObjectWithData:tail options:0 error:nil] : nil;
    if ([object isKindOfClass:NSDictionary.class]) return data.length;
    return lastNewline == NSNotFound ? 0 : lastNewline;
}

static NSData *PTReadFileDataFromOffset(NSString *filePath, NSUInteger offset) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!handle) return nil;
    @try {
        [handle seekToFileOffset:offset];
        NSData *data = [handle readDataToEndOfFile];
        [handle closeFile];
        return data;
    } @catch (__unused NSException *exception) {
        [handle closeFile];
        return nil;
    }
}

static PTSessionInfo *PTParseSessionWithDetail(
    NSString *filePath,
    NSDate *modifiedAt,
    NSUInteger *parsedSize,
    BOOL includeMessages
) {
    NSData *data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    NSUInteger completeLength = PTCompleteJSONLLength(data);
    if (parsedSize) *parsedSize = completeLength;
    if (completeLength == 0) return nil;
    NSData *completeData = completeLength == data.length
        ? data : [data subdataWithRange:NSMakeRange(0, completeLength)];
    return PTParseSessionData(completeData, filePath, modifiedAt, nil, includeMessages);
}

static PTSessionInfo *PTParseSession(
    NSString *filePath,
    NSDate *modifiedAt,
    NSUInteger *parsedSize
) {
    return PTParseSessionWithDetail(filePath, modifiedAt, parsedSize, YES);
}

static PTSessionInfo *PTParseSessionAppendingWithDetail(
    NSString *filePath,
    NSDate *modifiedAt,
    NSUInteger previousParsedSize,
    PTSessionInfo *baseSession,
    NSUInteger *parsedSize,
    BOOL includeMessages
) {
    NSData *newData = PTReadFileDataFromOffset(filePath, previousParsedSize);
    if (!newData) return nil;
    NSUInteger completeLength = PTCompleteJSONLLength(newData);
    if (parsedSize) *parsedSize = previousParsedSize + completeLength;
    if (completeLength == 0) {
        baseSession.modifiedAt = modifiedAt;
        return baseSession;
    }
    NSData *completeData = completeLength == newData.length
        ? newData : [newData subdataWithRange:NSMakeRange(0, completeLength)];
    return PTParseSessionData(completeData, filePath, modifiedAt, baseSession, includeMessages);
}

static __attribute__((unused)) PTSessionInfo *PTParseSessionAppending(
    NSString *filePath,
    NSDate *modifiedAt,
    NSUInteger previousParsedSize,
    PTSessionInfo *baseSession,
    NSUInteger *parsedSize
) {
    return PTParseSessionAppendingWithDetail(
        filePath, modifiedAt, previousParsedSize, baseSession, parsedSize, YES);
}

@interface PTSessionStore : NSObject
@property(nonatomic, copy) void (^sessionsChanged)(NSArray<PTSessionInfo *> *sessions);
@property(nonatomic, copy) void (^globalModelChanged)(NSString *model);
@property(nonatomic, copy) void (^globalEffortChanged)(NSString *effort);
@property(atomic, copy) NSSet<NSString *> *fullSessionIDs;
- (void)refresh;
- (void)refreshChangedPath:(NSString *)filePath
                completion:(void (^)(PTSessionInfo * _Nullable session))completion;
- (void)refreshForcingPath:(NSString *)filePath
                completion:(void (^)(PTSessionInfo * _Nullable session))completion;
- (void)startWatchingGlobalSettings;
- (void)stopWatchingGlobalSettings;
@end

@implementation PTSessionStore {
    dispatch_queue_t _queue;
    NSMutableDictionary<NSString *, NSDictionary *> *_cache;
    PTRefreshGate *_refreshGate;
    dispatch_source_t _settingsWatcher;
    int _settingsFD;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.yuuka.prettyterm.session-reader", DISPATCH_QUEUE_SERIAL);
        _cache = [NSMutableDictionary dictionary];
        _fullSessionIDs = [NSSet set];
        _refreshGate = [[PTRefreshGate alloc] init];
        _settingsFD = -1;
    }
    return self;
}

- (void)startWatchingGlobalSettings {
    NSString *settingsPath = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/settings.json"];
    int fd = open(settingsPath.UTF8String, O_EVTONLY);
    if (fd < 0) return;
    _settingsFD = fd;
    _settingsWatcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd,
        DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_RENAME,
        dispatch_get_main_queue());
    if (!_settingsWatcher) {
        close(fd);
        _settingsFD = -1;
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_settingsWatcher, ^{
        PTSessionStore *self = weakSelf;
        if (!self) return;
        NSData *data = [NSData dataWithContentsOfFile:settingsPath];
        if (!data) return;
        NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![settings isKindOfClass:NSDictionary.class]) return;
        NSString *model = [settings[@"model"] isKindOfClass:NSString.class] ? settings[@"model"] : @"";
        if (model.length && self.globalModelChanged) {
            self.globalModelChanged(model);
        }
        NSString *effort = [settings[@"effortLevel"] isKindOfClass:NSString.class]
            ? settings[@"effortLevel"] : @"";
        if (effort.length && self.globalEffortChanged) self.globalEffortChanged(effort);
    });
    dispatch_source_set_cancel_handler(_settingsWatcher, ^{
        if (self->_settingsFD >= 0) {
            close(self->_settingsFD);
            self->_settingsFD = -1;
        }
    });
    dispatch_resume(_settingsWatcher);
}

- (void)stopWatchingGlobalSettings {
    if (_settingsWatcher) {
        dispatch_source_cancel(_settingsWatcher);
        _settingsWatcher = nil;
    }
}

- (void)dealloc {
    [self stopWatchingGlobalSettings];
}

- (void)refresh {
    if (![_refreshGate beginRefresh]) return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        PTSessionStore *self = weakSelf;
        if (!self) return;

        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/projects"];
        NSDirectoryEnumerator<NSURL *> *enumerator = [NSFileManager.defaultManager
            enumeratorAtURL:[NSURL fileURLWithPath:root]
            includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLContentModificationDateKey, NSURLFileSizeKey]
            options:NSDirectoryEnumerationSkipsHiddenFiles
            errorHandler:nil];

        NSMutableArray<PTSessionInfo *> *sessions = [NSMutableArray array];
        NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
        NSSet<NSString *> *fullSessionIDs = self.fullSessionIDs;
        for (NSURL *url in enumerator) { @autoreleasepool {
            if (![url.pathExtension.lowercaseString isEqual:@"jsonl"]) continue;
            NSNumber *regular = nil;
            NSDate *modified = nil;
            NSNumber *size = nil;
            [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
            if (!regular.boolValue) continue;
            [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
            [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            [seenPaths addObject:url.path];
            BOOL includeMessages = [fullSessionIDs containsObject:
                url.lastPathComponent.stringByDeletingPathExtension];

            NSDictionary *cached = self->_cache[url.path];
            PTSessionInfo *session = nil;
            NSUInteger parsedSize = 0;
            if (cached && [cached[@"modified"] isEqual:modified] && [cached[@"size"] isEqual:size] &&
                ((PTSessionInfo *)cached[@"session"]).fullTranscriptLoaded == includeMessages) {
                session = cached[@"session"];
            } else {
                NSUInteger previousParsedSize = [cached[@"parsedSize"] unsignedIntegerValue];
                BOOL canAppend = cached[@"session"] &&
                    ((PTSessionInfo *)cached[@"session"]).fullTranscriptLoaded == includeMessages &&
                    size.unsignedIntegerValue > previousParsedSize;
                session = canAppend
                    ? PTParseSessionAppendingWithDetail(
                        url.path, modified ?: NSDate.distantPast, previousParsedSize,
                        cached[@"session"], &parsedSize, includeMessages)
                    : PTParseSessionWithDetail(url.path, modified ?: NSDate.distantPast,
                        &parsedSize, includeMessages);
                if (session) {
                    self->_cache[url.path] = @{
                        @"modified": modified ?: NSDate.distantPast,
                        @"size": size ?: @0,
                        @"parsedSize": @(parsedSize),
                        @"session": session
                    };
                } else {
                    [self->_cache removeObjectForKey:url.path];
                }
            }
            if (session) [sessions addObject:session];
        } }

        for (NSString *path in self->_cache.allKeys.copy) {
            if (![seenPaths containsObject:path]) [self->_cache removeObjectForKey:path];
        }
        [sessions sortUsingComparator:^NSComparisonResult(PTSessionInfo *a, PTSessionInfo *b) {
            return [b.modifiedAt compare:a.modifiedAt];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL needsAnotherPass = [self->_refreshGate finishRefreshNeedsAnotherPass];
            if (self.sessionsChanged) self.sessionsChanged(sessions);
            if (needsAnotherPass) [self refresh];
        });
    });
}

- (void)refreshChangedPath:(NSString *)filePath
                completion:(void (^)(PTSessionInfo * _Nullable session))completion {
    if (filePath.length == 0) {
        if (completion) completion(nil);
        return;
    }
    dispatch_async(_queue, ^{
        NSURL *url = [NSURL fileURLWithPath:filePath];
        NSNumber *regular = nil;
        NSDate *modified = nil;
        NSNumber *size = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];

        NSDictionary *cached = self->_cache[filePath];
        BOOL includeMessages = [self.fullSessionIDs containsObject:
            filePath.lastPathComponent.stringByDeletingPathExtension];
        NSUInteger previousParsedSize = [cached[@"parsedSize"] unsignedIntegerValue];
        NSUInteger parsedSize = 0;
        PTSessionInfo *session = nil;
        if (regular.boolValue) {
            BOOL canAppend = cached[@"session"] &&
                ((PTSessionInfo *)cached[@"session"]).fullTranscriptLoaded == includeMessages &&
                size.unsignedIntegerValue >= previousParsedSize;
            session = canAppend
                ? PTParseSessionAppendingWithDetail(filePath, modified ?: NSDate.distantPast,
                    previousParsedSize, cached[@"session"], &parsedSize, includeMessages)
                : PTParseSessionWithDetail(filePath, modified ?: NSDate.distantPast,
                    &parsedSize, includeMessages);
        }
        if (session) {
            self->_cache[filePath] = @{
                @"modified": modified ?: NSDate.distantPast,
                @"size": size ?: @0,
                @"parsedSize": @(parsedSize),
                @"session": session
            };
        } else {
            [self->_cache removeObjectForKey:filePath];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(session);
        });
    });
}

- (void)refreshForcingPath:(NSString *)filePath
                completion:(void (^)(PTSessionInfo * _Nullable session))completion {
    if (filePath.length == 0) {
        if (completion) completion(nil);
        return;
    }
    dispatch_async(_queue, ^{
        NSURL *url = [NSURL fileURLWithPath:filePath];
        NSNumber *regular = nil;
        NSDate *modified = nil;
        NSNumber *size = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        NSUInteger parsedSize = 0;
        PTSessionInfo *session = regular.boolValue
            ? PTParseSession(filePath, modified ?: NSDate.distantPast, &parsedSize)
            : nil;
        if (session) {
            self->_cache[filePath] = @{
                @"modified": modified ?: NSDate.distantPast,
                @"size": size ?: @0,
                @"parsedSize": @(parsedSize),
                @"session": session
            };
        } else {
            [self->_cache removeObjectForKey:filePath];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(session);
        });
    });
}
@end

@interface PTClaudeBridge : NSObject
@property(nonatomic, copy) void (^statusChanged)(NSString *status);
@property(nonatomic, copy) void (^outputObserved)(NSString *chunk);
@property(nonatomic, copy) dispatch_block_t turnCompleted;
@property(nonatomic, copy) dispatch_block_t streamChanged;
@property(nonatomic, copy) dispatch_block_t tasksChanged;
@property(nonatomic, copy) void (^usageChanged)(NSDictionary *payload, NSString *error);
@property(nonatomic, copy) dispatch_block_t modelChanged;
@property(nonatomic, readonly) NSString *currentModel;
@property(nonatomic, readonly) NSString *currentEffort;
@property(nonatomic, readonly) NSString *permissionMode;
@property(nonatomic, readonly) NSArray<NSDictionary *> *commands;
@property(nonatomic, readonly) BOOL compacting;
@property(nonatomic, readonly) NSNumber *contextTokens;
@property(nonatomic, copy) void (^commandOutputChanged)(NSString *text);
@property(nonatomic, copy) void (^toolPermissionRequested)(NSString *requestID, NSDictionary *request);
@property(nonatomic, copy) void (^toolRequestCancelled)(NSString *requestID);
- (void)answerToolRequest:(NSString *)requestID response:(NSDictionary *)response;
@property(nonatomic, readonly) NSDictionary *streamPayload;
@property(nonatomic, readonly) NSDictionary *tasksPayload;
@property(nonatomic, readonly) BOOL responding;
@property(nonatomic, readonly) NSString *sessionID;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) NSString *lastSendError;
- (void)connectToSession:(PTSessionInfo *)session;
- (void)connectToSession:(PTSessionInfo *)session completion:(void (^)(BOOL))completion;
- (void)refreshUsage;
- (void)startNewSession:(PTSessionInfo *)session prompt:(NSString *)prompt;
- (void)startNewSessionInDirectory:(NSString *)directory;
- (BOOL)sendMessage:(NSString *)message;
- (BOOL)sendMessage:(NSString *)message withImagePNGs:(NSArray<NSData *> *)imagePNGs;
- (void)submitMessage:(NSString *)message withImagePNGs:(NSArray<NSData *> *)imagePNGs
          completion:(void (^)(BOOL))completion;
- (BOOL)sendEscape;
- (void)backgroundTaskForToolUseID:(NSString *)toolUseID
                       completion:(void (^)(NSDictionary *, NSString *))completion;
- (void)readTaskOutput:(NSString *)taskID
             completion:(void (^)(NSDictionary *, NSString *))completion;
- (void)stop;
- (void)reconcileStreamWithMessages:(NSArray<NSDictionary *> *)messages;
@end


static NSString *PTRunGit(NSString *directory, NSArray<NSString *> *arguments, int *exitStatus) {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSMutableArray<NSString *> *allArguments = [NSMutableArray arrayWithObjects:@"-C", directory, nil];
    [allArguments addObjectsFromArray:arguments];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.arguments = allArguments;
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (exitStatus) *exitStatus = -1;
        return launchError.localizedDescription ?: PTL(@"无法启动 Git", @"Unable to launch Git");
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (exitStatus) *exitStatus = task.terminationStatus;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSDictionary<NSString *, NSString *> *PTGitReviewSnapshotForDirectory(NSString *directory) {
    BOOL isDirectory = NO;
    BOOL exists = directory.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:directory isDirectory:&isDirectory];
    if (!exists || !isDirectory) {
        return @{ @"directory": directory ?: @"", @"error": PTL(@"所选 Git 观察目录不存在。", @"The selected Git observation directory does not exist.") };
    }

    int rootStatus = 0;
    NSString *root = [PTRunGit(directory, @[@"rev-parse", @"--show-toplevel"], &rootStatus)
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (rootStatus != 0 || root.length == 0) {
        return @{
            @"directory": directory,
            @"error": PTL(@"这里不是 Git 仓库。切换目录只影响 PrettyTerm 的 Git 探测，不会改变 Claude Code；需要 Claude 访问该目录时，请在 Claude Code 执行 /add-dir。", @"This is not a Git repository. Changing this directory only affects PrettyTerm's Git probe and does not change Claude Code; run /add-dir in Claude Code when Claude needs access.")
        };
    }

    int branchCode = 0;
    NSString *branch = [PTRunGit(directory, @[@"branch", @"--show-current"], &branchCode)
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    int upstreamCode = 0;
    NSString *upstream = [PTRunGit(directory,
        @[@"rev-parse", @"--abbrev-ref", @"--symbolic-full-name", @"@{upstream}"], &upstreamCode)
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    int statusCode = 0;
    NSString *status = PTRunGit(directory,
        @[@"-c", @"core.quotepath=false", @"status", @"--short", @"--untracked-files=normal"],
        &statusCode);
    int diffCode = 0;
    NSString *diff = PTRunGit(directory,
        @[@"-c", @"core.quotepath=false", @"diff", @"--no-ext-diff", @"--no-color",
          @"--unified=3", @"HEAD", @"--", @"."], &diffCode);
    if (diffCode != 0) {
        diff = PTRunGit(directory,
            @[@"-c", @"core.quotepath=false", @"diff", @"--no-ext-diff", @"--no-color",
              @"--unified=3", @"--", @"."], &diffCode);
    }
    if (statusCode != 0 || diffCode != 0) {
        return @{
            @"directory": directory,
            @"root": root,
            @"error": [NSString stringWithFormat:PTL(@"Git 探测失败：%@%@", @"Git probe failed: %@%@"),
                status ?: @"", diff ?: @""]
        };
    }
    return @{
        @"directory": directory,
        @"root": root,
        @"branch": branchCode == 0 ? branch : @"HEAD",
        @"upstream": upstreamCode == 0 ? upstream : @"",
        @"status": status ?: @"",
        @"diff": diff ?: @""
    };
}


static NSString *PTAttachmentThumbnail(NSData *png) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)png, NULL);
    if (!source) return @"";
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @160
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnail) return @"";
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:thumbnail];
    CGImageRelease(thumbnail);
    NSData *bytes = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return bytes.length ? [@"data:image/png;base64," stringByAppendingString:[bytes base64EncodedStringWithOptions:0]] : @"";
}

static NSData *PTPNGDataForImage(NSImage *image) {
    if (!image.isValid) return nil;
    NSData *tiff = image.TIFFRepresentation;
    NSBitmapImageRep *representation = tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
    return [representation representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

NSData *PTPNGDataForImageFileURL(NSURL *url) {
    if (!url.isFileURL) return nil;
    NSData *source = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (source.length == 0) return nil;
    static const unsigned char pngSignature[] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    BOOL isPNG = source.length >= sizeof(pngSignature) &&
        memcmp(source.bytes, pngSignature, sizeof(pngSignature)) == 0;
    NSBitmapImageRep *representation = [NSBitmapImageRep imageRepWithData:source];
    if (!representation) return nil;
    // PNG 文件保持原始像素流；其他格式直接从文件数据解码。
    if (isPNG) return source;
    return [representation representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static NSString *const PTSessionModelOverridesKey = @"PTSessionModelOverrides";

@implementation PTClaudeBridge {
    NSString *_sessionID;
    NSString *_connectingSessionID;
    NSString *_lastSendError;
    NSString *_stderrText;
    BOOL _running;
    NSUInteger _connectionGeneration;
    NSTask *_task;
    NSPipe *_inputPipe;
    NSPipe *_outputPipe;
    NSPipe *_errorPipe;
    NSMutableData *_outputBuffer;
    NSMutableDictionary<NSString *, id> *_pendingSends;
    NSMutableDictionary<NSString *, id> *_pendingControls;
    NSMutableArray *_pendingConnections;
    NSString *_usageRequestID;
    NSDictionary *_usagePayload;
    NSString *_currentModel;
    NSString *_currentEffort;
    NSUInteger _settingsReadRevision;
    NSUInteger _appliedSettingsRevision;
    NSUInteger _modelChangeRevision;
    NSUInteger _confirmedModelChangeRevision;
    NSString *_permissionMode;
    NSArray<NSDictionary *> *_commands;
    NSMutableDictionary *_pendingQueries;
    NSMutableDictionary<NSString *, NSString *> *_submittedCommands;
    NSString *_activeCommand;
    BOOL _compacting;
    NSNumber *_contextTokens;
    NSMutableSet<NSString *> *_toolRequests;
    NSString *_initializeID;
    NSString *_initialPrompt;
    dispatch_queue_t _ioQueue;
    BOOL _stdoutEnded;
    BOOL _processEnded;
    int _exitStatus;
    NSMutableOrderedSet<NSString *> *_streamOrder;
    NSMutableDictionary<NSString *, NSDictionary *> *_streamRecords;
    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *_streamBlocks;
    NSMutableDictionary<NSString *, NSDictionary *> *_streamQuestions;
    NSSet<NSString *> *_persistedStreamKeys;
    NSDictionary<NSString *, NSDictionary *> *_persistedStreamQuestions;
    NSString *_streamMessageID;
    NSString *_streamModel;
    NSNumber *_streamBlockIndex;
    BOOL _responding;
    NSMutableSet<NSString *> *_workingMessageIDs;
    NSString *_activeWorkID;
    BOOL _streamNotificationScheduled;
    NSUInteger _streamRevision;
    NSString *_streamGeneration;
    NSMutableDictionary<NSString *, NSDictionary *> *_foregroundTasks;
    NSArray<NSDictionary *> *_backgroundTasks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ioQueue = dispatch_queue_create("com.yuuka.prettyterm.bridge-write", DISPATCH_QUEUE_SERIAL);
        _pendingSends = [NSMutableDictionary dictionary];
        _pendingControls = [NSMutableDictionary dictionary];
        _pendingConnections = [NSMutableArray array];
        _pendingQueries = [NSMutableDictionary dictionary];
        _submittedCommands = [NSMutableDictionary dictionary];
        _toolRequests = [NSMutableSet set];
        _streamOrder = [NSMutableOrderedSet orderedSet];
        _streamRecords = [NSMutableDictionary dictionary];
        _streamBlocks = [NSMutableDictionary dictionary];
        _streamQuestions = [NSMutableDictionary dictionary];
        _streamGeneration = NSUUID.UUID.UUIDString;
        _workingMessageIDs = [NSMutableSet set];
        _foregroundTasks = [NSMutableDictionary dictionary];
        _backgroundTasks = @[];
    }
    return self;
}

- (NSString *)sessionID { return _sessionID; }
- (BOOL)running { return _running; }
- (NSString *)lastSendError { return _lastSendError; }
- (BOOL)responding { return _responding; }
- (NSString *)currentModel { return _currentModel; }
- (NSString *)currentEffort { return _currentEffort; }
- (NSString *)permissionMode { return _permissionMode; }
- (NSArray *)commands { return _commands ?: @[]; }
- (BOOL)compacting { return _compacting; }
- (NSNumber *)contextTokens { return _contextTokens; }

- (NSDictionary *)tasksPayload {
    return @{
        @"sessionId": _sessionID ?: @"",
        @"generation": _streamGeneration,
        @"foreground": _foregroundTasks.allValues,
        @"background": _backgroundTasks
    };
}

- (void)clearLiveTasks {
    BOOL changed = _foregroundTasks.count || _backgroundTasks.count;
    [_foregroundTasks removeAllObjects];
    _backgroundTasks = @[];
    if (changed && self.tasksChanged) self.tasksChanged();
}

static NSDictionary *PTClaudeTaskSummary(NSDictionary *task) {
    if (![task isKindOfClass:NSDictionary.class] || ![task[@"task_id"] isKindOfClass:NSString.class]) return nil;
    NSMutableDictionary *summary = [NSMutableDictionary dictionaryWithObject:task[@"task_id"] forKey:@"task_id"];
    for (NSString *key in @[@"run_id", @"tool_use_id", @"task_type", @"description"]) {
        if ([task[key] isKindOfClass:NSString.class]) summary[key] = task[key];
    }
    return summary;
}

- (void)consumeTaskEvent:(NSDictionary *)frame {
    NSString *subtype = frame[@"subtype"];
    if ([subtype isEqual:@"background_tasks_changed"]) {
        NSArray *tasks = frame[@"tasks"];
        if (![tasks isKindOfClass:NSArray.class]) return;
        NSMutableArray *snapshot = [NSMutableArray arrayWithCapacity:tasks.count];
        BOOL changed = NO;
        for (NSDictionary *task in tasks) {
            NSDictionary *summary = PTClaudeTaskSummary(task);
            if (!summary) continue;
            [snapshot addObject:summary];
            NSString *taskID = summary[@"task_id"];
            NSDictionary *foreground = _foregroundTasks[taskID];
            NSString *runID = summary[@"run_id"];
            NSString *foregroundRunID = foreground[@"run_id"];
            if (foreground && (!runID || !foregroundRunID || [runID compare:foregroundRunID] != NSOrderedAscending)) {
                [_foregroundTasks removeObjectForKey:taskID];
                changed = YES;
            }
        }
        changed |= ![_backgroundTasks isEqualToArray:snapshot];
        _backgroundTasks = [snapshot copy];
        if (changed && self.tasksChanged) self.tasksChanged();
        return;
    }
    if (![@[@"task_started", @"task_updated", @"task_notification"] containsObject:subtype ?: @""]) return;
    NSString *taskID = [frame[@"task_id"] isKindOfClass:NSString.class] ? frame[@"task_id"] : nil;
    if (!taskID.length) return;
    NSDictionary *previous = _foregroundTasks[taskID];
    NSString *runID = frame[@"run_id"];
    NSString *previousRunID = previous[@"run_id"];
    if (runID.length && previousRunID.length && [runID compare:previousRunID] == NSOrderedAscending) return;
    if ([subtype isEqual:@"task_started"]) {
        NSString *type = frame[@"task_type"];
        if ([frame[@"is_backgrounded"] boolValue] || ![frame[@"tool_use_id"] length] ||
            ![@[@"local_bash", @"local_agent"] containsObject:type ?: @""]) return;
        for (NSDictionary *task in _backgroundTasks) {
            if ([task[@"task_id"] isEqual:taskID] && (!runID || !task[@"run_id"] || [task[@"run_id"] isEqual:runID])) return;
        }
        NSDictionary *summary = PTClaudeTaskSummary(frame);
        if ([previous isEqualToDictionary:summary]) return;
        _foregroundTasks[taskID] = summary;
    } else {
        if (!previous || (runID.length && previousRunID.length && ![runID isEqual:previousRunID])) return;
        NSDictionary *patch = frame[@"patch"];
        NSString *status = patch[@"status"];
        if (![subtype isEqual:@"task_notification"] && ![patch[@"is_backgrounded"] boolValue] &&
            ![@[@"completed", @"failed", @"killed", @"stopped"] containsObject:status ?: @""]) return;
        [_foregroundTasks removeObjectForKey:taskID];
    }
    if (self.tasksChanged) self.tasksChanged();
}

- (NSDictionary *)streamPayload {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSString *key in _streamOrder) if (_streamRecords[key]) [messages addObject:_streamRecords[key]];
    return @{@"sessionId": _sessionID ?: @"", @"messages": messages,
        @"questionUpdates": _streamQuestions.allValues, @"generation": _streamGeneration,
        @"active": @(_responding), @"compacting": @(_compacting), @"revision": @(_streamRevision)};
}

- (void)notifyStreamChanged {
    _streamRevision++;
    if (_streamNotificationScheduled) return;
    _streamNotificationScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        PTClaudeBridge *self = weakSelf;
        if (!self) return;
        self->_streamNotificationScheduled = NO;
        if (self.streamChanged) self.streamChanged();
    });
}

- (void)reconcileStreamWithMessages:(NSArray<NSDictionary *> *)messages {
    NSMutableSet *keys = [NSMutableSet set];
    NSMutableDictionary *questions = [NSMutableDictionary dictionary];
    BOOL changed = NO;
    for (NSDictionary *message in messages) {
        if (message[@"messageKey"]) [keys addObject:message[@"messageKey"]];
        if ([message[@"kind"] isEqual:@"question"] && [message[@"toolUseId"] length]) {
            NSString *toolID = message[@"toolUseId"];
            questions[toolID] = [message copy];
            NSDictionary *live = _streamQuestions[toolID];
            if (live && (![live[@"answered"] boolValue] || [message[@"answered"] boolValue])) {
                [_streamQuestions removeObjectForKey:toolID];
                changed = YES;
            }
        }
    }
    _persistedStreamKeys = keys;
    _persistedStreamQuestions = questions;
    for (NSString *identity in [_streamOrder.array copy]) {
        NSDictionary *record = _streamRecords[identity];
        NSString *toolID = record[@"toolUseId"];
        BOOL mergedQuestionResult = ![record[@"kind"] isEqual:@"question"] &&
            toolID.length && (_streamQuestions[toolID] || _persistedStreamQuestions[toolID]);
        if (![keys containsObject:record[@"messageKey"]] && !mergedQuestionResult) continue;
        [_streamRecords removeObjectForKey:identity];
        [_streamOrder removeObject:identity];
        changed = YES;
    }
    if (changed) [self notifyStreamChanged];
}

- (void)putStreamRecord:(NSDictionary *)record identity:(NSString *)identity {
    if (!record || !identity.length) return;
    if ([record[@"kind"] isEqual:@"question"] && [record[@"toolUseId"] length])
        _streamQuestions[record[@"toolUseId"]] = [record copy];
    if ([_persistedStreamKeys containsObject:record[@"messageKey"]]) {
        [_streamRecords removeObjectForKey:identity];
        [_streamOrder removeObject:identity];
    } else {
        NSMutableDictionary *item = [record mutableCopy];
        item[@"streamID"] = identity;
        [_streamOrder addObject:identity];
        _streamRecords[identity] = item;
    }
    [self notifyStreamChanged];
}

- (NSDictionary *)streamRecordForBlock:(NSDictionary *)block key:(NSString *)key
                                model:(NSString *)model partial:(BOOL)partial {
    NSString *type = block[@"type"];
    NSMutableDictionary *record = nil;
    if ([type isEqual:@"text"]) {
        record = [@{@"role": @"assistant", @"text": block[@"text"] ?: @"",
            @"messageKey": key, @"model": model ?: @"Claude"} mutableCopy];
    } else if (partial && [type isEqual:@"tool_use"]) {
        record = [@{@"role": @"tool", @"kind": @"tool", @"toolName": block[@"name"] ?: @"",
            @"toolUseId": block[@"id"] ?: @"",
            @"text": block[@"partial_json"] ?: @"", @"messageKey": key} mutableCopy];
    } else {
        record = [PTEventFromAssistantBlock(block, key, @"", model ?: @"Claude") mutableCopy];
    }
    record[@"streaming"] = @(partial);
    return record;
}

- (void)consumeStreamFrame:(NSDictionary *)frame {
    // 子代理完整消息另有 parent_tool_use_id，不混进主会话正在生成的内容块。
    if ([frame[@"parent_tool_use_id"] isKindOfClass:NSString.class]) return;
    NSString *type = frame[@"type"];
    if ([type isEqual:@"command_lifecycle"]) {
        NSString *uuid = frame[@"command_uuid"];
        NSString *state = frame[@"state"];
        if (uuid.length && [state isEqual:@"started"]) {
            _activeWorkID = uuid;
            [_workingMessageIDs addObject:uuid];
            _responding = YES;
        } else if (uuid.length && ![state isEqual:@"queued"]) {
            [_workingMessageIDs removeObject:uuid];
            if ([_activeWorkID isEqual:uuid]) _activeWorkID = nil;
            _responding = _workingMessageIDs.count > 0;
        }
        [self notifyStreamChanged];
    }
    if ([type isEqual:@"stream_event"]) {
        NSDictionary *event = frame[@"event"];
        NSString *eventType = event[@"type"];
        _responding = YES;
        if ([eventType isEqual:@"message_start"]) {
            _streamMessageID = event[@"message"][@"id"];
            _streamModel = event[@"message"][@"model"];
            NSDictionary *usage = event[@"message"][@"usage"];
            if ([usage isKindOfClass:NSDictionary.class]) {
                _contextTokens = @([usage[@"input_tokens"] unsignedIntegerValue] +
                    [usage[@"cache_read_input_tokens"] unsignedIntegerValue] + [usage[@"cache_creation_input_tokens"] unsignedIntegerValue]);
            }
            [_streamBlocks removeAllObjects];
            _streamBlockIndex = nil;
        } else if ([eventType isEqual:@"content_block_start"]) {
            _streamBlockIndex = event[@"index"];
            _streamBlocks[_streamBlockIndex] = [event[@"content_block"] mutableCopy];
        } else if ([eventType isEqual:@"content_block_delta"]) {
            _streamBlockIndex = event[@"index"];
            NSMutableDictionary *block = _streamBlocks[_streamBlockIndex];
            NSDictionary *delta = event[@"delta"];
            NSString *field = [delta[@"type"] isEqual:@"text_delta"] ? @"text" :
                ([delta[@"type"] isEqual:@"thinking_delta"] ? @"thinking" :
                 ([delta[@"type"] isEqual:@"input_json_delta"] ? @"partial_json" : nil));
            if (!field) return;
            block[field] = [block[field] ?: @"" stringByAppendingString:delta[field] ?: @""];
        } else {
            return; // 完整 assistant 块已在 content_block_stop 之前交付。
        }
        if (_streamBlockIndex && _streamMessageID.length) {
            NSString *identity = [NSString stringWithFormat:@"%@:%@", _streamMessageID, _streamBlockIndex];
            NSDictionary *record = [self streamRecordForBlock:_streamBlocks[_streamBlockIndex]
                key:identity model:_streamModel partial:YES];
            [self putStreamRecord:record identity:identity];
        }
    } else if ([type isEqual:@"assistant"]) {
        NSDictionary *message = frame[@"message"];
        // Local-command acknowledgements are synthetic and never enter the
        // persisted assistant history. Keep them out of the live history too.
        if ([message[@"model"] isEqual:@"<synthetic>"]) return;
        NSArray *content = message[@"content"];
        if (![content isKindOfClass:NSArray.class]) return;
        [content enumerateObjectsUsingBlock:^(NSDictionary *block, NSUInteger index, BOOL *stop) {
            (void)stop;
            // SDK 每完成一个内容块发一条 assistant；该条记录的 block index 从 0 起，
            // 而 stream_event.index 属于原始 API 消息。用当前流块连接两种标识。
            NSString *key = [NSString stringWithFormat:@"%@:%lu",
                frame[@"uuid"] ?: message[@"id"], (unsigned long)index];
            NSString *identity = [message[@"id"] isEqual:self->_streamMessageID] && self->_streamBlockIndex
                ? [NSString stringWithFormat:@"%@:%@", self->_streamMessageID, self->_streamBlockIndex] : key;
            [self putStreamRecord:[self streamRecordForBlock:block key:key
                model:message[@"model"] partial:NO] identity:identity];
        }];
    } else if ([type isEqual:@"user"]) {
        NSDictionary *message = frame[@"message"];
        NSString *uuid = frame[@"uuid"];
        if (!uuid.length) return;
        NSString *text = PTTextFromMessageContent(message[@"content"]);
        NSArray<NSDictionary *> *images = PTImagesFromMessageContent(message[@"content"]);
        if ((text.length || images.count) && ![frame[@"isMeta"] boolValue] && !_submittedCommands[uuid]) {
            NSString *key = [uuid stringByAppendingString:@":user"];
            [self putStreamRecord:@{@"role": @"user", @"text": text, @"images": images, @"messageKey": key} identity:key];
        }
        if ([message[@"content"] isKindOfClass:NSArray.class]) {
            [message[@"content"] enumerateObjectsUsingBlock:^(NSDictionary *block, NSUInteger index, BOOL *stop) {
                (void)stop;
                if (![block[@"type"] isEqual:@"tool_result"]) return;
                NSString *toolID = block[@"tool_use_id"];
                NSMutableDictionary *question = [(self->_streamQuestions[toolID ?: @""] ?:
                    self->_persistedStreamQuestions[toolID ?: @""]) mutableCopy];
                if (question) {
                    question[@"answered"] = @YES;
                    id result = frame[@"tool_use_result"] ?: frame[@"toolUseResult"];
                    NSDictionary *answers = [result isKindOfClass:NSDictionary.class] ? result[@"answers"] : nil;
                    question[@"answerText"] = answers.count ? PTFormattedQuestionAnswers(answers)
                        : PTEventFromToolResultBlock(block, @"", @"")[@"text"];
                    NSString *identity = question[@"messageKey"];
                    for (NSString *candidate in self->_streamOrder)
                        if ([self->_streamRecords[candidate][@"toolUseId"] isEqual:toolID] &&
                            [self->_streamRecords[candidate][@"kind"] isEqual:@"question"]) { identity = candidate; break; }
                    [self putStreamRecord:question identity:identity];
                    return;
                }
                NSString *key = [NSString stringWithFormat:@"%@:result:%lu", uuid, (unsigned long)index];
                [self putStreamRecord:PTEventFromToolResultBlock(block, key, @"") identity:key];
            }];
        }
    } else if ([type isEqual:@"result"]) {
        NSString *completed = frame[@"user_message_uuid"] ?: _activeWorkID;
        if (completed) [_workingMessageIDs removeObject:completed];
        _activeWorkID = nil;
        _responding = _workingMessageIDs.count > 0;
        for (NSString *key in _streamOrder) {
            NSMutableDictionary *record = [_streamRecords[key] mutableCopy];
            record[@"streaming"] = @NO;
            _streamRecords[key] = record;
        }
        [self notifyStreamChanged];
    }
}

- (void)reportError:(NSString *)message {
    _lastSendError = message;
    if (self.statusChanged) self.statusChanged(message);
}

- (void)completePendingSends:(BOOL)accepted {
    NSArray *callbacks = _pendingSends.allValues;
    callbacks = [callbacks arrayByAddingObjectsFromArray:_pendingControls.allValues];
    callbacks = [callbacks arrayByAddingObjectsFromArray:_pendingConnections];
    [_pendingSends removeAllObjects];
    [_pendingControls removeAllObjects];
    [_pendingConnections removeAllObjects];
    for (void (^completion)(BOOL) in callbacks) completion(accepted);
    NSArray *queries = _pendingQueries.allValues;
    [_pendingQueries removeAllObjects];
    for (void (^query)(NSDictionary *, NSString *) in queries) query(nil, _lastSendError ?: @"Claude session ended");
    [_submittedCommands removeAllObjects];
}

- (BOOL)writeFrame:(NSDictionary *)frame completion:(void (^)(BOOL))completion {
    NSError *error = nil;
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:frame options:0 error:&error] mutableCopy];
    if (!data || !_task.running) {
        [self reportError:error.localizedDescription ?: PTL(@"Claude 会话未连接", @"Claude session is disconnected")];
        if (completion) completion(NO);
        return NO;
    }
    [data appendBytes:"\n" length:1];
    NSFileHandle *input = _inputPipe.fileHandleForWriting;
    NSUInteger generation = _connectionGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_ioQueue, ^{
        NSError *writeError = nil;
        BOOL written = [input writeData:data error:&writeError];
        dispatch_async(dispatch_get_main_queue(), ^{
            PTClaudeBridge *self = weakSelf;
            if (!self || generation != self->_connectionGeneration) return;
            if (!written) [self reportError:[NSString stringWithFormat:
                PTL(@"Claude 消息写入失败：%@", @"Claude message write failed: %@"), writeError.localizedDescription]];
            if (completion) completion(written);
        });
    });
    return YES;
}

- (BOOL)sendControl:(NSDictionary *)request {
    return [self writeFrame:@{@"type": @"control_request",
        @"request_id": NSUUID.UUID.UUIDString.lowercaseString, @"request": request} completion:nil];
}

- (void)refreshUsage {
    if (!_running || _usageRequestID) return;
    _usageRequestID = NSUUID.UUID.UUIDString.lowercaseString;
    [self writeFrame:@{@"type": @"control_request", @"request_id": _usageRequestID,
        @"request": @{@"subtype": @"get_usage", @"skip_behaviors": @YES}}
        completion:^(BOOL written) {
            if (written) return;
            self->_usageRequestID = nil;
            if (self.usageChanged) self.usageChanged(nil, self.lastSendError);
        }];
}

- (void)recordConfigurationEvent:(NSDictionary *)event {
    NSMutableDictionary *entry = [event mutableCopy];
    entry[@"timestamp"] = [[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
    entry[@"session_id"] = _sessionID ?: @"";
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/PrettyTerm"];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"PrettyTerm configuration log: %@", error.localizedDescription);
        return;
    }
    NSString *path = [directory stringByAppendingPathComponent:@"configuration.jsonl"];
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:entry options:0 error:&error] mutableCopy];
    if (!data) { NSLog(@"PrettyTerm configuration log: %@", error.localizedDescription); return; }
    [data appendBytes:"\n" length:1];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        if (![data writeToFile:path options:0 error:&error]) NSLog(@"PrettyTerm configuration log: %@", error.localizedDescription);
        return;
    }
    NSFileHandle *file = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:path] error:&error];
    if (!file || ![file seekToEndReturningOffset:NULL error:&error] || ![file writeData:data error:&error])
        NSLog(@"PrettyTerm configuration log: %@", error.localizedDescription);
    [file closeAndReturnError:nil];
}

- (BOOL)persistConfigurationForControl:(NSDictionary *)control {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/settings.json"];
    NSError *error = nil;
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error] : nil;
        if (![parsed isKindOfClass:NSDictionary.class]) {
            [self reportError:[NSString stringWithFormat:PTL(@"当前会话已应用，配置文件读取失败：%@", @"Session updated; could not read settings: %@"), error.localizedDescription ?: path]];
            [self recordConfigurationEvent:@{@"event": @"save_failed", @"error": self.lastSendError}];
            return NO;
        }
        settings = parsed;
    }
    NSMutableDictionary *changed = [NSMutableDictionary dictionary];
    if (control[@"model"] && _currentModel.length) {
        settings[@"model"] = _currentModel;
        changed[@"model"] = _currentModel;
    }
    if (control[@"settings"][@"effortLevel"] && _currentModel.length) {
        NSString *modelKey = [[_currentModel.lowercaseString stringByReplacingOccurrencesOfString:@"[1m]" withString:@""] stringByReplacingOccurrencesOfString:@"[2m]" withString:@""];
        NSMutableDictionary *models = [settings[@"modelSettings"] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *model = [models[modelKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        if (_currentEffort.length) model[@"effortLevel"] = _currentEffort;
        else [model removeObjectForKey:@"effortLevel"];
        models[modelKey] = model;
        settings[@"modelSettings"] = models;
        changed[@"modelSettings"] = @{modelKey: @{ @"effortLevel": _currentEffort.length ? _currentEffort : (id)NSNull.null }};
    }
    if (control[@"mode"] && _permissionMode.length) {
        NSMutableDictionary *permissions = [settings[@"permissions"] mutableCopy] ?: [NSMutableDictionary dictionary];
        permissions[@"defaultMode"] = _permissionMode;
        settings[@"permissions"] = permissions;
        changed[@"permissions"] = @{@"defaultMode": _permissionMode};
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    BOOL saved = data && [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:&error] && [data writeToFile:path options:NSDataWritingAtomic error:&error];
    [self recordConfigurationEvent:@{@"event": saved ? @"saved" : @"save_failed", @"path": path,
        @"changed": changed, @"error": error.localizedDescription ?: @""}];
    if (!saved) [self reportError:[NSString stringWithFormat:PTL(@"当前会话已应用，配置保存失败：%@", @"Session updated; could not save settings: %@"), error.localizedDescription]];
    return saved;
}

- (void)queryControl:(NSDictionary *)request completion:(void (^)(NSDictionary *, NSString *))completion {
    NSString *requestID = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *subtype = request[@"subtype"];
    BOOL configuration = [@[@"set_model", @"set_permission_mode", @"apply_flag_settings", @"get_settings"] containsObject:subtype];
    if (configuration) [self recordConfigurationEvent:@{@"event": @"request", @"request_id": requestID, @"request": request}];
    __weak typeof(self) weakSelf = self;
    _pendingQueries[requestID] = [^(NSDictionary *body, NSString *error) {
        if (configuration) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            if ([body[@"applied"] isKindOfClass:NSDictionary.class]) result[@"applied"] = body[@"applied"];
            if ([body[@"mode"] isKindOfClass:NSString.class]) result[@"mode"] = body[@"mode"];
            [weakSelf recordConfigurationEvent:@{@"event": @"response", @"request_id": requestID,
                @"subtype": subtype, @"result": result, @"error": error ?: @""}];
        }
        completion(body, error);
    } copy];
    [self writeFrame:@{@"type": @"control_request", @"request_id": requestID, @"request": request}
        completion:^(BOOL written) {
            if (written) return;
            void (^callback)(NSDictionary *, NSString *) = self->_pendingQueries[requestID];
            [self->_pendingQueries removeObjectForKey:requestID];
            if (callback) callback(nil, self.lastSendError);
        }];
}

- (void)backgroundTaskForToolUseID:(NSString *)toolUseID
                       completion:(void (^)(NSDictionary *, NSString *))completion {
    [self queryControl:@{@"subtype": @"background_tasks", @"tool_use_id": toolUseID}
            completion:^(NSDictionary *body, NSString *error) {
        if (error) { completion(nil, error); return; }
        if (![body[@"backgrounded"] boolValue]) {
            completion(nil, PTL(@"该命令已结束或已在后台", @"The command has finished or is already in the background"));
            return;
        }
        completion(body, nil);
    }];
}

- (void)readTaskOutput:(NSString *)taskID
             completion:(void (^)(NSDictionary *, NSString *))completion {
    [self queryControl:@{@"subtype": @"get_task_output", @"task_id": taskID} completion:completion];
}

- (void)refreshSettings {
    [self refreshSettingsWithCompletion:nil];
}

- (void)refreshSettingsWithCompletion:(void (^)(NSString *, BOOL))completion {
    NSUInteger revision = ++_settingsReadRevision;
    __weak typeof(self) weakSelf = self;
    [self queryControl:@{@"subtype": @"get_settings"} completion:^(NSDictionary *body, NSString *error) {
        PTClaudeBridge *self = weakSelf;
        if (!self) return;
        NSDictionary *applied = [body[@"applied"] isKindOfClass:NSDictionary.class] ? body[@"applied"] : nil;
        NSString *model = !error && [applied[@"model"] isKindOfClass:NSString.class] ? applied[@"model"] : nil;
        BOOL receivedEffort = !error &&
            ([applied[@"effort"] isKindOfClass:NSString.class] || applied[@"effort"] == NSNull.null);
        if (revision >= self->_appliedSettingsRevision && (model.length || receivedEffort)) {
            self->_appliedSettingsRevision = revision;
            if (model.length) self->_currentModel = [model copy];
            // An explicit null means Claude has no named effective effort.
            if (receivedEffort) self->_currentEffort = applied[@"effort"] == NSNull.null ? @"" : [applied[@"effort"] copy];
            if (self.modelChanged) self.modelChanged();
        }
        if (!model.length && !receivedEffort) {
            [self reportError:error ?: PTL(@"未读取到 Claude 当前配置", @"Could not read Claude's current settings")];
        }
        if (completion) completion(model, receivedEffort);
    }];
}

- (void)answerToolRequest:(NSString *)requestID response:(NSDictionary *)response {
    if (![_toolRequests containsObject:requestID]) return;
    [_toolRequests removeObject:requestID];
    [self writeFrame:@{@"type": @"control_response", @"response": @{
        @"subtype": @"success", @"request_id": requestID, @"response": response}} completion:nil];
}

- (void)showCommandOutput:(NSString *)text {
    if (!text.length) return;
    if (self.commandOutputChanged) self.commandOutputChanged(text);
}

- (void)consumeFrame:(NSDictionary *)frame {
    [self consumeStreamFrame:frame];
    NSString *type = frame[@"type"];
    if ([type isEqual:@"system"]) [self consumeTaskEvent:frame];
    if ([type isEqual:@"assistant"] && [frame[@"message"][@"model"] isEqual:@"<synthetic>"]) {
        [self showCommandOutput:PTTextFromMessageContent(frame[@"message"][@"content"])];
        return;
    }
    if ([type isEqual:@"control_response"]) {
        NSDictionary *response = frame[@"response"];
        NSString *responseID = response[@"request_id"];
        void (^query)(NSDictionary *, NSString *) = responseID ? _pendingQueries[responseID] : nil;
        if (query) {
            [_pendingQueries removeObjectForKey:responseID];
            query(response[@"response"], [response[@"subtype"] isEqual:@"error"] ? response[@"error"] : nil);
        } else if ([responseID isEqual:_usageRequestID]) {
            _usageRequestID = nil;
            NSDictionary *body = response[@"response"];
            NSDictionary *limits = [body[@"rate_limits"] isKindOfClass:NSDictionary.class] ? body[@"rate_limits"] : nil;
            NSString *error = [response[@"subtype"] isEqual:@"error"] ? response[@"error"] : nil;
            if (!limits && !error) error = PTL(@"Claude Code 未返回套餐额度", @"Claude Code did not return plan limits");
            _usagePayload = [limits copy];
            if (self.usageChanged) self.usageChanged(_usagePayload, error);
        } else if ([response[@"request_id"] isEqual:_initializeID]) {
            if ([response[@"subtype"] isEqual:@"error"]) {
                [self reportError:response[@"error"] ?: PTL(@"Claude 会话恢复失败", @"Claude session resume failed")];
                _connectingSessionID = nil;
                [self completePendingSends:NO];
                return;
            }
            _connectingSessionID = nil;
            _running = YES;
            NSArray *commands = response[@"response"][@"commands"];
            if ([commands isKindOfClass:NSArray.class]) _commands = commands;
            NSString *prompt = _initialPrompt;
            _initialPrompt = nil;
            if (self.statusChanged) self.statusChanged(PTL(@"Claude 后台会话已连接", @"Claude background session connected"));
            NSArray *connections = [_pendingConnections copy];
            [_pendingConnections removeAllObjects];
            for (void (^completion)(BOOL) in connections) completion(YES);
            [self refreshUsage];
            [self refreshSettings];
            if (prompt.length) [self sendMessage:prompt];
        } else {
            NSString *requestID = response[@"request_id"];
            BOOL accepted = ![response[@"subtype"] isEqual:@"error"];
            if (!accepted) [self reportError:response[@"error"] ?: PTL(@"Claude 指令执行失败", @"Claude command failed")];
            void (^completion)(BOOL) = requestID ? _pendingControls[requestID] : nil;
            if (requestID) [_pendingControls removeObjectForKey:requestID];
            if (completion) completion(accepted);
        }
    } else if ([type isEqual:@"control_request"]) {
        NSDictionary *request = frame[@"request"];
        if ([request[@"subtype"] isEqual:@"can_use_tool"] && self.toolPermissionRequested) {
            [_toolRequests addObject:frame[@"request_id"]];
            self.toolPermissionRequested(frame[@"request_id"], request);
        }
    } else if ([type isEqual:@"control_cancel_request"]) {
        NSString *requestID = frame[@"request_id"];
        [_toolRequests removeObject:requestID];
        if (self.toolRequestCancelled) self.toolRequestCancelled(requestID);
    } else if ([type isEqual:@"command_lifecycle"]) {
        NSString *uuid = frame[@"command_uuid"];
        NSString *command = _submittedCommands[uuid];
        if (!command) return;
        NSString *state = frame[@"state"];
        if ([state isEqual:@"queued"]) return;
        BOOL accepted = [state isEqual:@"started"] || [state isEqual:@"completed"];
        void (^completion)(BOOL) = _pendingSends[uuid];
        [_pendingSends removeObjectForKey:uuid];
        if ([state isEqual:@"started"]) _activeCommand = command;
        if (!accepted) [self reportError:[NSString stringWithFormat:@"%@ · %@", command, state]];
        if (completion) completion(accepted);
        if (![state isEqual:@"started"]) {
            _compacting = NO;
            [self notifyStreamChanged];
            [_submittedCommands removeObjectForKey:uuid];
            if (self.turnCompleted) self.turnCompleted();
        }
    } else if ([type isEqual:@"rate_limit_event"]) {
        NSDictionary *windows = frame[@"rate_limit_info"][@"unifiedWindows"];
        NSMutableDictionary *limits = [_usagePayload mutableCopy] ?: [NSMutableDictionary dictionary];
        NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
        for (NSString *name in @[@"five_hour", @"seven_day"]) {
            NSDictionary *window = windows[name];
            if (![window isKindOfClass:NSDictionary.class]) continue;
            limits[name] = @{@"utilization": @([window[@"utilization"] doubleValue] * 100.0),
                @"resets_at": [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[window[@"resetsAt"] doubleValue]]]};
        }
        if (limits.count) {
            _usagePayload = [limits copy];
            if (self.usageChanged) self.usageChanged(_usagePayload, nil);
        }
    } else if ([type isEqual:@"system"] && [frame[@"subtype"] isEqual:@"init"]) {
        NSString *model = frame[@"model"];
        if ([frame[@"permissionMode"] isKindOfClass:NSString.class]) _permissionMode = frame[@"permissionMode"];
        if (!_currentModel.length && [model isKindOfClass:NSString.class] && model.length) {
            _currentModel = [model copy];
            if (self.modelChanged) self.modelChanged();
        }
    } else if ([type isEqual:@"system"]) {
        NSString *subtype = frame[@"subtype"];
        if ([subtype isEqual:@"commands_changed"]) _commands = frame[@"commands"];
        if ([subtype isEqual:@"local_command_output"]) [self showCommandOutput:frame[@"content"]];
        if ([subtype isEqual:@"status"]) {
            if ([frame[@"permissionMode"] isKindOfClass:NSString.class]) {
                _permissionMode = frame[@"permissionMode"];
                if (self.modelChanged) self.modelChanged();
            }
            _compacting = [frame[@"status"] isEqual:@"compacting"];
            if (_compacting) {
                _responding = YES;
                if (self.statusChanged) self.statusChanged(PTL(@"Claude 正在压缩上下文…", @"Claude is compacting context…"));
            }
            if ([frame[@"status"] isEqual:@"requesting"]) _responding = YES;
            if ([frame[@"compact_result"] isEqual:@"failed"]) [self reportError:frame[@"compact_error"] ?: PTL(@"压缩失败", @"Compaction failed")];
            [self notifyStreamChanged];
        }
        if ([subtype isEqual:@"compact_boundary"]) {
            _compacting = NO;
            NSDictionary *metadata = frame[@"compact_metadata"];
            if ([metadata[@"post_tokens"] isKindOfClass:NSNumber.class]) _contextTokens = metadata[@"post_tokens"];
            NSString *text = metadata[@"post_tokens"]
                ? [NSString stringWithFormat:PTL(@"压缩完成：%@ → %@ tokens", @"Compacted: %@ → %@ tokens"), metadata[@"pre_tokens"], metadata[@"post_tokens"]]
                : [NSString stringWithFormat:PTL(@"压缩完成 · 压缩前 %@ tokens", @"Compacted · %@ tokens before"), metadata[@"pre_tokens"]];
            [self showCommandOutput:text];
            if (self.modelChanged) self.modelChanged();
            [self notifyStreamChanged];
        }
    } else if ([type isEqual:@"user"]) {
        // --replay-user-messages 保留输入 UUID：此时整条图文已进入 Claude，
        // 不再依赖终端画面、图片缓存位置或粘贴后的回车时序。
        NSString *uuid = frame[@"uuid"];
        void (^completion)(BOOL) = uuid ? _pendingSends[uuid] : nil;
        if (completion) {
            [_pendingSends removeObjectForKey:uuid];
            if (self.statusChanged) self.statusChanged(PTL(@"图文已提交，等待 Claude 回复…", @"Message submitted; waiting for Claude…"));
            completion(YES);
        }
    } else if ([type isEqual:@"result"]) {
        _compacting = NO;
        if (!_responding && _foregroundTasks.count) {
            [_foregroundTasks removeAllObjects];
            if (self.tasksChanged) self.tasksChanged();
        }
        [self notifyStreamChanged];
        if (_activeCommand.length && [frame[@"result"] isKindOfClass:NSString.class]) [self showCommandOutput:frame[@"result"]];
        _activeCommand = nil;
        if ([frame[@"is_error"] boolValue]) {
            NSArray *errors = frame[@"errors"];
            NSString *message = errors.count ? [errors componentsJoinedByString:@"\n"] : frame[@"result"];
            [self reportError:message ?: PTL(@"Claude 未完成本次请求", @"Claude did not complete the request")];
            [self completePendingSends:NO];
        }
        if (self.turnCompleted) self.turnCompleted();
        [self refreshUsage];
        [self refreshSettings];
    }
    if (self.outputObserved && ([type isEqual:@"control_response"] || [type isEqual:@"system"])) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:frame options:0 error:nil];
        self.outputObserved([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
    }
}

- (void)consumeOutput:(NSData *)data {
    [_outputBuffer appendData:data];
    while (_outputBuffer.length) {
        const void *newline = memchr(_outputBuffer.bytes, '\n', _outputBuffer.length);
        if (!newline) break;
        NSUInteger length = (const uint8_t *)newline - (const uint8_t *)_outputBuffer.bytes;
        NSData *line = [_outputBuffer subdataWithRange:NSMakeRange(0, length)];
        [_outputBuffer replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
        if (!line.length) continue;
        id frame = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
        if ([frame isKindOfClass:NSDictionary.class]) [self consumeFrame:frame];
        else [self reportError:PTL(@"Claude 返回了无法解析的消息", @"Claude returned an unreadable message")];
    }
}

- (void)finishProcessIfEnded {
    if (!_processEnded || !_stdoutEnded) return;
    [_workingMessageIDs removeAllObjects];
    [self consumeStreamFrame:@{@"type": @"result"}];
    _running = NO;
    _connectingSessionID = nil;
    [self clearLiveTasks];
    NSString *message = _stderrText.length ? _stderrText :
        [NSString stringWithFormat:PTL(@"Claude 后台会话已结束（%d）", @"Claude background session ended (%d)"), _exitStatus];
    [self reportError:message];
    [self completePendingSends:NO];
}

// 接管同一 session 的旧交互进程后再恢复，避免两个进程同时续写同一会话。
// 这是已确认的连接迁移，只匹配 Claude 自己记录的 sessionId。
- (NSString *)releaseInteractiveSession:(NSString *)sessionID {
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/sessions"];
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *name in [files contentsOfDirectoryAtPath:directory error:nil]) {
        NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
        NSDictionary *metadata = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![metadata isKindOfClass:NSDictionary.class] || ![metadata[@"sessionId"] isEqual:sessionID]) continue;
        pid_t pid = [metadata[@"pid"] intValue];
        if (pid <= 0 || kill(pid, 0) != 0) continue;
        dispatch_semaphore_t exited = dispatch_semaphore_create(0);
        dispatch_source_t observer = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid,
            DISPATCH_PROC_EXIT, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
        dispatch_source_set_event_handler(observer, ^{ dispatch_semaphore_signal(exited); });
        dispatch_resume(observer);
        int result = kill(pid, SIGTERM);
        if (result == 0) dispatch_semaphore_wait(exited, DISPATCH_TIME_FOREVER);
        dispatch_source_cancel(observer);
        if (result != 0 && errno != ESRCH) return [NSString stringWithFormat:
            PTL(@"Claude 会话接管失败：%s", @"Claude session takeover failed: %s"), strerror(errno)];
    }
    return nil;
}

- (void)launchSession:(PTSessionInfo *)session resume:(BOOL)resume prompt:(NSString *)prompt {
    [self stop];
    _sessionID = [session.sessionID copy];
    _connectingSessionID = _sessionID;
    _initialPrompt = [prompt copy];
    NSUInteger generation = _connectionGeneration;
    NSString *sessionID = _sessionID;
    NSString *cwd = [session.cwd copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(_ioQueue, ^{
        PTClaudeBridge *self = weakSelf;
        if (!self || generation != self->_connectionGeneration) return;
        NSString *error = resume ? [self releaseInteractiveSession:sessionID] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_connectionGeneration) return;
            if (error) {
                [self reportError:error];
                self->_connectingSessionID = nil;
                [self completePendingSends:NO];
                return;
            }
            NSString *model = nil;
            if (resume) {
                model = [NSUserDefaults.standardUserDefaults dictionaryForKey:PTSessionModelOverridesKey][sessionID];
                if (!model.length) model = session.model;
            }
            [self startProcessInDirectory:cwd resume:resume model:model];
        });
    });
}

- (void)startProcessInDirectory:(NSString *)cwd resume:(BOOL)resume model:(NSString *)model {
    _task = [NSTask new];
    _inputPipe = [NSPipe pipe];
    _outputPipe = [NSPipe pipe];
    _errorPipe = [NSPipe pipe];
    _outputBuffer = [NSMutableData data];
    _stderrText = @"";
    _stdoutEnded = NO;
    _processEnded = NO;
    _task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    _task.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    NSData *settingsData = [NSData dataWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@".claude/settings.json"]];
    NSDictionary *settings = settingsData ? [NSJSONSerialization JSONObjectWithData:settingsData options:0 error:nil] : nil;
    NSString *configuredMode = settings[@"permissions"][@"defaultMode"];
    // 未保存模式时延续原有 Bypass；保存后按老师选择的模式启动，仍可随时切回 Bypass。
    NSString *launchMode = [configuredMode isKindOfClass:NSString.class] && configuredMode.length ? configuredMode : @"bypassPermissions";
    _permissionMode = launchMode;
    NSMutableArray<NSString *> *arguments = [@[@"-lic", @"export TZ=UTC\nexec \"$(whence -p claude)\" \"$@\"",
        @"PrettyTerm", @"--allow-dangerously-skip-permissions", @"--permission-mode", launchMode,
        @"--permission-prompt-tool", @"stdio", @"--print",
        @"--input-format", @"stream-json", @"--output-format", @"stream-json",
        @"--verbose", @"--replay-user-messages", @"--include-partial-messages",
        resume ? @"--resume" : @"--session-id", _sessionID] mutableCopy];
    if (resume && model.length) [arguments addObjectsFromArray:@[@"--model", model]];
    _task.arguments = arguments;
    _task.standardInput = _inputPipe;
    _task.standardOutput = _outputPipe;
    _task.standardError = _errorPipe;
    NSUInteger generation = _connectionGeneration;
    __weak typeof(self) weakSelf = self;
    _outputPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (!data.length) handle.readabilityHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            PTClaudeBridge *self = weakSelf;
            if (!self || generation != self->_connectionGeneration) return;
            if (data.length) [self consumeOutput:data];
            else { self->_stdoutEnded = YES; [self finishProcessIfEnded]; }
        });
    };
    _errorPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (!data.length) { handle.readabilityHandler = nil; return; }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            PTClaudeBridge *self = weakSelf;
            if (!self || generation != self->_connectionGeneration || !text) return;
            self->_stderrText = [self->_stderrText stringByAppendingString:text];
        });
    };
    _task.terminationHandler = ^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            PTClaudeBridge *self = weakSelf;
            if (!self || generation != self->_connectionGeneration) return;
            self->_processEnded = YES;
            self->_exitStatus = task.terminationStatus;
            [self finishProcessIfEnded];
        });
    };
    NSError *error = nil;
    if (![_task launchAndReturnError:&error]) {
        [self reportError:error.localizedDescription];
        _connectingSessionID = nil;
        [self completePendingSends:NO];
        return;
    }
    _initializeID = NSUUID.UUID.UUIDString.lowercaseString;
    [self writeFrame:@{@"type": @"control_request", @"request_id": _initializeID,
        @"request": @{@"subtype": @"initialize"}} completion:nil];
}

- (void)connectToSession:(PTSessionInfo *)session {
    if ([_connectingSessionID isEqual:session.sessionID] ||
        (_running && [_sessionID isEqual:session.sessionID])) return;
    [self launchSession:session resume:YES prompt:nil];
}

- (void)connectToSession:(PTSessionInfo *)session completion:(void (^)(BOOL))completion {
    if (_running && [_sessionID isEqual:session.sessionID]) {
        if (completion) completion(YES);
        return;
    }
    [self connectToSession:session];
    if (completion) [_pendingConnections addObject:[completion copy]];
}

- (void)startNewSession:(PTSessionInfo *)session prompt:(NSString *)prompt {
    [self launchSession:session resume:NO prompt:prompt];
}

- (void)startNewSessionInDirectory:(NSString *)directory {
    PTSessionInfo *session = [PTSessionInfo new];
    session.sessionID = NSUUID.UUID.UUIDString.lowercaseString;
    session.cwd = directory;
    [self launchSession:session resume:NO prompt:nil];
}

- (void)submitMessage:(NSString *)message withImagePNGs:(NSArray<NSData *> *)imagePNGs
          completion:(void (^)(BOOL))completion {
    _lastSendError = nil;
    if (!imagePNGs.count && [[message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] hasPrefix:@"/"])
        message = [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!_running) {
        [self reportError:PTL(@"Claude 会话未连接", @"Claude session is disconnected")];
        if (completion) completion(NO);
        return;
    }
    NSDictionary *control = nil;
    if (!imagePNGs.count && [message hasPrefix:@"/model "]) {
        control = @{@"subtype": @"set_model", @"model": [message substringFromIndex:7]};
    } else if (!imagePNGs.count && [message isEqual:@"/remote-control"]) {
        control = @{@"subtype": @"remote_control", @"enabled": @YES};
    } else if (!imagePNGs.count && [message hasPrefix:@"/effort "]) {
        control = @{@"subtype": @"apply_flag_settings", @"settings": @{@"effortLevel": [message substringFromIndex:8]}};
    } else if (!imagePNGs.count) {
        NSDictionary *modes = @{@"/plan": @"plan", @"/auto": @"auto", @"/bypass": @"bypassPermissions",
            @"/mode plan": @"plan", @"/mode auto": @"auto", @"/mode bypass": @"bypassPermissions",
            @"/mode default": @"default", @"/mode acceptEdits": @"acceptEdits"};
        NSString *mode = modes[message];
        if (mode) control = @{@"subtype": @"set_permission_mode", @"mode": mode};
    }
    if (control) {
        NSString *requestedModel = control[@"model"];
        NSUInteger modelRevision = requestedModel ? ++_modelChangeRevision : 0;
        __weak typeof(self) weakSelf = self;
        [self queryControl:control completion:^(NSDictionary *body, NSString *error) {
            PTClaudeBridge *self = weakSelf;
            if (!self) return;
            if (error) {
                [self reportError:error];
                if (self.modelChanged) self.modelChanged();
                if (completion) completion(NO);
                return;
            }
            if (control[@"mode"]) {
                NSString *mode = [body[@"mode"] isKindOfClass:NSString.class] ? body[@"mode"] : nil;
                self->_permissionMode = mode;
                if (!mode.length) [self reportError:PTL(@"Claude 未返回当前模式", @"Claude did not return its current mode")];
                if (self.modelChanged) self.modelChanged();
                BOOL saved = mode.length > 0 && [self persistConfigurationForControl:control];
                if (completion) completion(saved);
            } else if (requestedModel || control[@"settings"][@"effortLevel"]) {
                [self refreshSettingsWithCompletion:^(NSString *model, BOOL receivedEffort) {
                    if (requestedModel && modelRevision < self->_confirmedModelChangeRevision) {
                        if (completion) completion(NO);
                        return;
                    }
                    BOOL received = requestedModel ? (model.length && [model isEqual:self->_currentModel]) : receivedEffort;
                    if (requestedModel && received) {
                        if ([requestedModel hasPrefix:@"claude-"] && ![requestedModel isEqual:model]) {
                            [self reportError:[NSString stringWithFormat:PTL(
                                @"请求切换至 %@，Claude 确认的模型是 %@",
                                @"Requested %@; Claude confirmed %@"), requestedModel, model]];
                            if (completion) completion(NO);
                            return;
                        }
                        self->_confirmedModelChangeRevision = modelRevision;
                        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
                        NSMutableDictionary *overrides = [[defaults dictionaryForKey:PTSessionModelOverridesKey] mutableCopy]
                            ?: [NSMutableDictionary dictionary];
                        if ([requestedModel isEqual:@"default"]) [overrides removeObjectForKey:self->_sessionID];
                        else overrides[self->_sessionID] = model;
                        [defaults setObject:overrides forKey:PTSessionModelOverridesKey];
                    }
                    if (!received && !self.lastSendError) {
                        [self reportError:PTL(@"Claude 未确认所请求的配置", @"Claude did not confirm the requested setting")];
                    }
                    BOOL saved = received && [self persistConfigurationForControl:control];
                    if (completion) completion(saved);
                }];
            } else if (completion) {
                completion(YES);
            }
        }];
        return;
    }
    NSMutableArray *content = [NSMutableArray array];
    for (NSData *png in imagePNGs) {
        [content addObject:@{@"type": @"image", @"source": @{
            @"type": @"base64", @"media_type": @"image/png",
            @"data": [png base64EncodedStringWithOptions:0]}}];
    }
    if ([message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
        [content addObject:@{@"type": @"text", @"text": message}];
    NSString *uuid = NSUUID.UUID.UUIDString.lowercaseString;
    if (!imagePNGs.count && [message hasPrefix:@"/"]) _submittedCommands[uuid] = message;
    if (completion) _pendingSends[uuid] = [completion copy];
    NSDictionary *frame = @{@"type": @"user", @"uuid": uuid, @"session_id": _sessionID,
        @"parent_tool_use_id": NSNull.null, @"message": @{@"role": @"user", @"content": imagePNGs.count ? (id)content : message}};
    [_workingMessageIDs addObject:uuid];
    _responding = YES;
    [self notifyStreamChanged];
    [self writeFrame:frame completion:^(BOOL written) {
        if (written) return;
        [self->_workingMessageIDs removeObject:uuid];
        self->_responding = self->_workingMessageIDs.count > 0;
        [self notifyStreamChanged];
        void (^callback)(BOOL) = self->_pendingSends[uuid];
        [self->_pendingSends removeObjectForKey:uuid];
        if (callback) callback(NO);
    }];
}

- (BOOL)sendMessage:(NSString *)message {
    if (!_running) return NO;
    [self submitMessage:message withImagePNGs:@[] completion:nil];
    return YES;
}

- (BOOL)sendMessage:(NSString *)message withImagePNGs:(NSArray<NSData *> *)imagePNGs {
    if (!_running) return NO;
    [self submitMessage:message withImagePNGs:imagePNGs completion:nil];
    return YES;
}

- (BOOL)sendEscape {
    return [self sendControl:@{@"subtype": @"interrupt"}];
}

- (void)stop {
    _connectionGeneration++;
    _running = NO;
    _responding = NO;
    [_workingMessageIDs removeAllObjects];
    _activeWorkID = nil;
    [_streamOrder removeAllObjects];
    [_streamRecords removeAllObjects];
    [_streamBlocks removeAllObjects];
    [_streamQuestions removeAllObjects];
    _streamGeneration = NSUUID.UUID.UUIDString;
    [self clearLiveTasks];
    _persistedStreamKeys = nil;
    _persistedStreamQuestions = nil;
    [self notifyStreamChanged];
    _connectingSessionID = nil;
    _usageRequestID = nil;
    _usagePayload = nil;
    _currentModel = nil;
    _currentEffort = nil;
    _permissionMode = @"bypassPermissions";
    _commands = @[];
    _activeCommand = nil;
    _compacting = NO;
    _contextTokens = nil;
    for (NSString *requestID in _toolRequests.allObjects) if (self.toolRequestCancelled) self.toolRequestCancelled(requestID);
    [_toolRequests removeAllObjects];
    _outputPipe.fileHandleForReading.readabilityHandler = nil;
    _errorPipe.fileHandleForReading.readabilityHandler = nil;
    [_inputPipe.fileHandleForWriting closeAndReturnError:nil];
    if (_task.running) [_task terminate];
    _task = nil;
    _inputPipe = nil;
    _outputPipe = nil;
    _errorPipe = nil;
    _initialPrompt = nil;
    [self completePendingSends:NO];
}

- (void)dealloc {
    _outputPipe.fileHandleForReading.readabilityHandler = nil;
    _errorPipe.fileHandleForReading.readabilityHandler = nil;
    [_inputPipe.fileHandleForWriting closeAndReturnError:nil];
    if (_task.running) [_task terminate];
}
@end

@interface PTWorkspaceTab : NSObject
@property(nonatomic) NSUInteger draftRevision;
@property(nonatomic) BOOL reportedResponding;
@property(nonatomic, copy) NSString *commandOutput;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *draft;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSString *activeToolPageKind;
@property(nonatomic, copy) NSString *fileTreeRootPath;
@property(nonatomic, strong) PTClaudeBridge *bridge;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *pendingImages;
@property(nonatomic, strong) NSMutableArray<NSString *> *pendingFiles;
@property(nonatomic) BOOL connecting;
@property(nonatomic) BOOL reviewToolPageOpen;
@property(nonatomic) BOOL fileToolPageOpen;
@property(nonatomic) BOOL panelExpanded;
@property(nonatomic) BOOL overviewExpanded;
@end

@implementation PTWorkspaceTab
@end

@interface PTAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, PTFrontendBridgeDelegate>
- (void)updateWorkspaceTabBar;
- (void)syncFullSessionIDs;
- (PTSessionInfo *)sessionWithID:(NSString *)sessionID;
- (void)updateWindowMaximumSize;
- (void)pushFrontendWindowState;
- (void)pushFrontendWorkspace;
- (void)pushFrontendSessions;
- (void)pushFrontendGitState;
- (void)buildLobeFloatingPanelIfNeeded;
- (void)positionLobeFloatingPanelNearMainWindow;
@end

@implementation PTAppDelegate {
    NSWindow *_window;
    PTSessionStore *_store;
    PTClaudeBridge *_bridge;
    NSMutableArray<PTWorkspaceTab *> *_workspaceTabs;
    PTWorkspaceTab *_activeWorkspaceTab;
    NSString *_homeProjectPath;
    PTClaudeBridge *_homeStartingBridge;
    NSString *_homeBlankSessionDirectory;
    NSMutableDictionary<NSString *, PTSessionInfo *> *_newSessionsAwaitingTranscript;
    NSMutableDictionary<NSString *, PTClaudeBridge *> *_renameConnections;
    NSMutableDictionary<NSString *, NSString *> *_pendingRenameTitles;
    NSString *_homeStartingSessionID;
    NSArray<PTSessionInfo *> *_sessions;
    PTSessionInfo *_selectedSession;
    NSString *_statusText;
    NSString *_selectedComposerModelID;
    NSString *_selectedComposerEffort;
    NSMutableArray<NSDictionary *> *_pendingImages;
    NSMutableArray<NSString *> *_pendingFiles;
    NSMutableSet<NSString *> *_temporaryImagePaths;
    NSMenuItem *_floatingMenuItem;
    NSTimer *_refreshTimer;
    NSTimer *_usageRefreshTimer;
    NSString *_planUsageSessionID;
    BOOL _planUsageAvailable;
    double _fiveHourPercent;
    double _sevenDayPercent;
    NSDate *_fiveHourResetAt;
    NSDate *_sevenDayResetAt;
    NSString *_planUsageError;
    NSString *_floatingStatusText;
    NSMutableArray<NSDictionary *> *_floatingPendingImages;
    NSMutableArray<NSString *> *_floatingPendingFiles;
    NSString *_floatingSessionID;
    NSString *_floatingDraft;
    NSUInteger _floatingDraftRevision;
    BOOL _floatingRenderInFlight;
    PTSessionInfo *_pendingFloatingSession;
    NSString *_floatingRenderedSessionID;
    NSDate *_floatingRenderedModifiedAt;
    NSUInteger _floatingRenderedMessageCount;
    NSArray<NSDictionary *> *_floatingRenderedMessages;
    NSUInteger _floatingRenderGeneration;
    NSString *_sessionListSignature;
    NSString *_manualRefreshSessionID;
    NSString *_renderedSessionID;
    NSUInteger _renderedMessageCount;
    NSArray<NSDictionary *> *_renderedMessages;
    NSDate *_renderedModifiedAt;
    BOOL _renderInFlight;
    PTSessionInfo *_pendingRenderSession;
    NSMutableArray<NSString *> *_gitDirectoryPaths;
    NSMutableSet<NSString *> *_suppressedGitDirectoryPaths;
    NSString *_gitObservedDirectory;
    BOOL _gitReviewShowsTranscriptEdits;
    NSString *_gitVisibleTabID;
    BOOL _gitDirectoryManuallySelected;
    NSUInteger _gitDiffGeneration;
    BOOL _gitActionInFlight;
    PTAgentState *_agentState;
    PTTranscriptWatcher *_transcriptWatcher;
    NSString *_watchedTranscriptPath;
    BOOL _connecting;
    NSMutableDictionary<NSString *, NSNumber *> *_awaitingClaudeBaselineBySessionID;

    // ask_via_prettyterm MCP 桥：轮询 ~/.claude/prettyterm-questions 目录，
    // 跟 transcript 完全无关，绕开"问题和答案一起落盘"那个死结。
    NSTimer *_questionPollTimer;
    NSMutableSet<NSString *> *_processedQuestionRequestIDs;
    NSMutableArray<NSDictionary *> *_pendingQuestionRequests;
    NSPanel *_questionPanel;
    NSStackView *_questionPanelStack;
    NSTextField *_questionPanelStatusLabel;
    NSMutableArray<NSDictionary *> *_questionPanelBlocks;
    NSString *_questionPanelRequestID;
    NSMutableDictionary *_protocolQuestions;
    NSMutableDictionary<NSString *, NSAlert *> *_protocolAlerts;
    PTFrontendBridge *_lobeMainBridge;
    PTBridgeDropWebView *_lobeMainWebView;
    PTFrontendBridge *_lobeFloatingBridge;
    PTBridgeDropWebView *_lobeFloatingWebView;
    NSPanel *_lobeFloatingPanel;
    BOOL _lobeAppearanceObserved;
    NSDictionary *_lobeGitStateSnapshot;
    NSDictionary *_turnReviewSnapshot;
    NSString *_gitReviewInFlightDirectory;
    NSString *_gitReviewQueuedDirectory;
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *_directoryReadTargets;
    NSTask *_lobeTerminalTask;
    NSMutableString *_lobeTerminalOutput;
    NSString *_lobeTerminalCommand;
    NSString *_lobeTerminalCwd;
    NSString *_lobeTerminalTabID;
    BOOL _lobeTerminalRunning;
    NSNumber *_lobeTerminalExitCode;
    NSString *_terminalRunID;
    NSUInteger _terminalSequence;
    BOOL _terminalDrawerVisible;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    _agentState = [[PTAgentState alloc] init];
    _transcriptWatcher = [[PTTranscriptWatcher alloc] init];
    _processedQuestionRequestIDs = [NSMutableSet set];
    _pendingQuestionRequests = [NSMutableArray array];
    _protocolQuestions = [NSMutableDictionary dictionary];
    _protocolAlerts = [NSMutableDictionary dictionary];
    _pendingImages = [NSMutableArray array];
    _pendingFiles = [NSMutableArray array];
    _workspaceTabs = [NSMutableArray array];
    _awaitingClaudeBaselineBySessionID = [NSMutableDictionary dictionary];
    _floatingPendingImages = [NSMutableArray array];
    _floatingPendingFiles = [NSMutableArray array];
    _temporaryImagePaths = [NSMutableSet set];
    NSData *settingsData = [NSData dataWithContentsOfFile:
        [NSHomeDirectory() stringByAppendingPathComponent:@".claude/settings.json"]];
    NSDictionary *settings = settingsData
        ? [NSJSONSerialization JSONObjectWithData:settingsData options:0 error:nil] : nil;
    _selectedComposerEffort = [settings[@"effortLevel"] isKindOfClass:NSString.class]
        ? settings[@"effortLevel"] : @"";
    _selectedComposerModelID = [settings[@"model"] isKindOfClass:NSString.class]
        ? settings[@"model"] : @"";
    _gitDirectoryPaths = [NSMutableArray array];
    NSArray *suppressedDirectories = [NSUserDefaults.standardUserDefaults
        arrayForKey:@"PTGitSuppressedDirectories"];
    _suppressedGitDirectoryPaths = [NSMutableSet setWithArray:suppressedDirectories ?: @[]];
    [self buildMainMenu];
    [self buildWindow];
    [self connectStoreAndBridge];
    if (!_lobeAppearanceObserved) {
        [NSApp addObserver:self
                forKeyPath:@"effectiveAppearance"
                   options:NSKeyValueObservingOptionNew
                   context:(__bridge void *)self];
        _lobeAppearanceObserved = YES;
    }
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_store refresh];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(refreshSessions:) userInfo:nil repeats:YES];
    _usageRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refreshClaudeUsage:) userInfo:nil repeats:YES];
    _questionPollTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(pollQuestionRequests:) userInfo:nil repeats:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    NSString *appName = NSProcessInfo.processInfo.processName;
    [appMenu addItemWithTitle:[NSString stringWithFormat:PTL(@"关于 %@", @"About %@"), appName]
                       action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:PTL(@"隐藏 %@", @"Hide %@"), appName]
                       action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:PTL(@"隐藏其他", @"Hide Others")
                       action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:PTL(@"显示全部", @"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    _floatingMenuItem = [appMenu addItemWithTitle:PTL(@"悬浮当前对话", @"Float Current Conversation")
                       action:@selector(toggleFloatingConversation:) keyEquivalent:@"o"];
    _floatingMenuItem.target = self;
    _floatingMenuItem.enabled = NO;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:PTL(@"退出 %@", @"Quit %@"), appName]
                       action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:PTL(@"编辑", @"Edit")];
    [editMenu addItemWithTitle:PTL(@"撤销", @"Undo") action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:PTL(@"重做", @"Redo") action:@selector(redo:) keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:PTL(@"剪切", @"Cut") action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:PTL(@"拷贝", @"Copy") action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:PTL(@"粘贴", @"Paste") action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:PTL(@"全选", @"Select All") action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;

    NSApp.mainMenu = mainMenu;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (_lobeAppearanceObserved) {
        @try { [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:(__bridge void *)self]; } @catch (NSException *ignored) { (void)ignored; }
        _lobeAppearanceObserved = NO;
    }
    [_lobeMainBridge detach];
    [_lobeFloatingBridge detach];
    [_refreshTimer invalidate];
    [_questionPollTimer invalidate];
    for (PTWorkspaceTab *tab in _workspaceTabs.copy) {
        [tab.bridge stop];
    }
    [_transcriptWatcher stopWatching];
    [_usageRefreshTimer invalidate];
    [_store stopWatchingGlobalSettings];
    for (NSString *path in _temporaryImagePaths.copy) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}

- (void)buildWindow {
    NSDictionary *bundleInfo = NSBundle.mainBundle.infoDictionary ?: @{};
    NSString *displayName = bundleInfo[@"CFBundleDisplayName"] ?: @"PrettyTerm Beta";
    NSString *shortVersion = bundleInfo[@"CFBundleShortVersionString"] ?: @"—";
    NSString *buildVersion = bundleInfo[@"CFBundleVersion"] ?: @"—";
    NSString *visibleAppVersion = [NSString stringWithFormat:@"%@ · v%@ (%@)",
        displayName, shortVersion, buildVersion];
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1260, 780)
                                         styleMask:style
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _window.title = visibleAppVersion;
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.backgroundColor = PTThemeColor(PTThemeRoleCanvas);
    _window.minSize = NSMakeSize(680, 480);
    _window.delegate = self;
    [_window center];
    [self updateWindowMaximumSize];

    [self attachMainFrontend];
}

- (void)windowDidResize:(NSNotification *)notification {
    if (notification.object == _window) [self updateWindowMaximumSize];
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
    if (notification.object != _window) return;
    [self updateWindowMaximumSize];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
    if (sender != _window) return frameSize;
    NSScreen *screen = sender.screen ?: NSScreen.mainScreen;
    if (!screen) return frameSize;
    frameSize.width = MIN(frameSize.width, NSWidth(screen.visibleFrame));
    frameSize.height = MIN(frameSize.height, NSHeight(screen.visibleFrame));
    return frameSize;
}

- (void)updateWindowMaximumSize {
    NSScreen *screen = _window.screen ?: NSScreen.mainScreen;
    if (screen) _window.maxSize = screen.visibleFrame.size;
}

- (void)configureBridgeCallbacksForWorkspaceTab:(PTWorkspaceTab *)tab {
    if (!tab.bridge) return;
    __weak typeof(self) weakSelf = self;
    __weak PTWorkspaceTab *weakTab = tab;
    tab.bridge.statusChanged = ^(NSString *status) {
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab) return;
        strongTab.status = status ?: @"";
        strongTab.connecting = NO;
        NSString *bridgeSessionID = strongTab.bridge.sessionID ?: strongTab.sessionID;
        if (!strongTab.bridge.running && bridgeSessionID.length > 0) {
            [self finishAwaitingClaudeReplyForSessionID:bridgeSessionID];
        }
        if (self->_activeWorkspaceTab == strongTab) {
            self->_connecting = NO;
            self->_statusText = strongTab.status;
            self->_agentState.sendInFlight = NO;
            [self refreshAgentStateAndControls];
        }
        [self updateWorkspaceTabBar];
    };
    tab.bridge.outputObserved = ^(NSString *chunk) {
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab || self->_activeWorkspaceTab != strongTab) return;
        if ([chunk containsString:@"Remote Control"] && [chunk containsString:@"http"]) {
            self->_statusText = PTL(@"官方 Remote Control 已启用", @"Official Remote Control is enabled");
        }
    };
    tab.bridge.turnCompleted = ^{
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab) return;
        [self finishAwaitingClaudeReplyForSessionID:strongTab.bridge.sessionID];
        [self->_store refresh];
        if ([self->_gitVisibleTabID isEqual:strongTab.identifier] && self->_activeWorkspaceTab == strongTab &&
            !self->_gitReviewShowsTranscriptEdits) {
            [self pushFrontendGitDiffForDirectory:self->_gitObservedDirectory];
        }
    };
    tab.bridge.streamChanged = ^{
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (self && strongTab) {
            [self presentClaudeStreamForBridge:strongTab.bridge];
            BOOL responding = strongTab.bridge.responding;
            if (strongTab.reportedResponding != responding) {
                strongTab.reportedResponding = responding;
                [self pushFrontendWorkspaceState];
                [self pushFrontendSessions];
            }
        }
    };
    tab.bridge.tasksChanged = ^{
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        NSString *sessionID = strongTab.bridge.sessionID;
        if (!self || !sessionID.length) return;
        if ([self->_selectedSession.sessionID isEqual:sessionID]) {
            [self pushFrontendClaudeTasksTo:self->_lobeMainBridge sessionID:sessionID];
        }
        if ([self->_floatingSessionID isEqual:sessionID]) {
            [self pushFrontendClaudeTasksTo:self->_lobeFloatingBridge sessionID:sessionID];
        }
    };
    tab.bridge.usageChanged = ^(NSDictionary *payload, NSString *error) {
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab || ![strongTab.bridge.sessionID isEqual:self->_selectedSession.sessionID]) return;
        [self finishClaudeUsageWithPayload:payload error:error];
    };
    tab.bridge.modelChanged = ^{
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab) return;
        PTSessionInfo *session = [self sessionWithID:strongTab.bridge.sessionID];
        session.effort = strongTab.bridge.currentEffort;
        [self updateComposerConfigurationButtons];
    };
    tab.bridge.commandOutputChanged = ^(NSString *text) {
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab) return;
        strongTab.commandOutput = text;
        strongTab.status = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject;
        if (self->_activeWorkspaceTab == strongTab) self->_statusText = strongTab.status;
        if ([self->_floatingSessionID isEqual:strongTab.sessionID]) self->_floatingStatusText = strongTab.status;
        [self pushFrontendWindowState];
    };
    tab.bridge.toolPermissionRequested = ^(NSString *requestID, NSDictionary *request) {
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (self && strongTab) [self presentClaudeToolRequest:requestID request:request bridge:strongTab.bridge];
    };
    tab.bridge.toolRequestCancelled = ^(NSString *requestID) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        NSAlert *alert = self->_protocolAlerts[requestID];
        [self->_protocolAlerts removeObjectForKey:requestID];
        if (alert.window.sheetParent) [alert.window.sheetParent endSheet:alert.window returnCode:NSModalResponseCancel];
        [self->_protocolQuestions removeObjectForKey:requestID];
        NSIndexSet *indexes = [self->_pendingQuestionRequests indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
            (void)index; (void)stop;
            return [item[@"id"] isEqual:requestID];
        }];
        [self->_pendingQuestionRequests removeObjectsAtIndexes:indexes];
        if ([self->_questionPanelRequestID isEqual:requestID]) {
            [self->_questionPanel orderOut:nil];
            [self presentNextQuestionRequestIfIdle];
        }
    };
}

- (PTWorkspaceTab *)createWorkspaceTab {
    PTWorkspaceTab *tab = [[PTWorkspaceTab alloc] init];
    tab.identifier = NSUUID.UUID.UUIDString;
    tab.sessionID = @"";
    tab.draft = @"";
    tab.status = PTL(@"新标签已就绪，请从侧栏选择会话", @"New tab ready; choose a conversation from the sidebar");
    tab.activeToolPageKind = @"";
    tab.fileTreeRootPath = @"";
    tab.reviewToolPageOpen = NO;
    tab.fileToolPageOpen = NO;
    tab.panelExpanded = NO;
    tab.overviewExpanded = YES;
    tab.pendingImages = [NSMutableArray array];
    tab.pendingFiles = [NSMutableArray array];
    tab.bridge = [[PTClaudeBridge alloc] init];
    [self configureBridgeCallbacksForWorkspaceTab:tab];
    [_workspaceTabs addObject:tab];
    return tab;
}

- (void)showEmptyWorkspaceTab {
    _selectedSession = nil;
    [_transcriptWatcher stopWatching];
    _watchedTranscriptPath = nil;
    _renderedSessionID = nil;
    _renderedModifiedAt = nil;
    _renderedMessageCount = 0;
    _renderedMessages = nil;
    _pendingRenderSession = nil;
    [_lobeMainBridge deliverClaudeSession:@{@"sessionId": @"", @"messages": @[]} completion:nil];
    _statusText = _activeWorkspaceTab.status ?: @"";
    [self refreshAgentStateAndControls];
    [self updateFloatingControls];
}

- (void)activateWorkspaceTab:(PTWorkspaceTab *)tab animated:(BOOL)animated {
    (void)animated;
    if (!tab || _activeWorkspaceTab == tab) return;
    _activeWorkspaceTab = tab;
    _bridge = tab.bridge;
    _connecting = tab.connecting;
    _pendingImages = tab.pendingImages;
    _pendingFiles = tab.pendingFiles;
    _renderedSessionID = nil;
    _renderedModifiedAt = nil;
    _renderedMessageCount = 0;
    _renderedMessages = nil;
    _pendingRenderSession = nil;
    _selectedSession = [self sessionWithID:tab.sessionID];
    _statusText = tab.status ?: @"";
    if (_selectedSession) [self showSelectedSession];
    else [self showEmptyWorkspaceTab];
    [self pushFrontendWorkspace];
}

- (void)closeWorkspaceTabWithID:(NSString *)identifier {
    NSUInteger index = [_workspaceTabs indexOfObjectPassingTest:
        ^BOOL(PTWorkspaceTab *tab, NSUInteger tabIndex, BOOL *stop) {
            (void)tabIndex;
            (void)stop;
            return [tab.identifier isEqual:identifier];
        }];
    if (index == NSNotFound) return;

    PTWorkspaceTab *closingTab = _workspaceTabs[index];
    BOOL closingActiveTab = closingTab == _activeWorkspaceTab;
    NSString *closingSessionID = closingTab.bridge.sessionID ?: closingTab.sessionID;
    [closingTab.bridge stop];
    if (closingSessionID.length > 0) {
        [self finishAwaitingClaudeReplyForSessionID:closingSessionID];
    }
    [_workspaceTabs removeObjectAtIndex:index];

    if (!closingActiveTab) {
        [self syncFullSessionIDs];
        [self updateWorkspaceTabBar];
        return;
    }

    _activeWorkspaceTab = nil;
    _bridge = nil;
    _connecting = NO;
    if (_workspaceTabs.count > 0) {
        NSUInteger nextIndex = MIN(index, _workspaceTabs.count - 1);
        [self activateWorkspaceTab:_workspaceTabs[nextIndex] animated:YES];
    } else {
        _pendingImages = [NSMutableArray array];
        _pendingFiles = [NSMutableArray array];
        [self showEmptyWorkspaceTab];
        [self updateWorkspaceTabBar];
    }
    [self syncFullSessionIDs];
}

- (void)updateWorkspaceTabBar {
    [self pushFrontendWorkspace];
}

- (PTClaudeBridge *)newHomeBridge { return [PTClaudeBridge new]; }

- (void)homeLaunchStatusChanged:(NSString *)status {
    _statusText = status ?: @"";
    [self pushFrontendWindowState];
    if (!_homeStartingBridge.running) {
        _homeStartingSessionID = nil;
        _homeStartingBridge = nil;
        _homeBlankSessionDirectory = nil;
        return;
    }
    if (_homeBlankSessionDirectory.length) {
        _homeStartingSessionID = [_homeStartingBridge.sessionID copy];
        PTSessionInfo *session = [self sessionWithID:_homeStartingSessionID];
        if (!session) {
            session = [PTSessionInfo new];
            session.sessionID = _homeStartingSessionID;
            session.cwd = _homeBlankSessionDirectory;
            session.title = PTL(@"新对话", @"New conversation");
            session.modifiedAt = NSDate.date;
            session.assistantMessages = @[];
            if (!_newSessionsAwaitingTranscript) _newSessionsAwaitingTranscript = [NSMutableDictionary dictionary];
            _newSessionsAwaitingTranscript[session.sessionID] = session;
            _sessions = [(_sessions ?: @[]) arrayByAddingObject:session];
            [self pushFrontendSessions];
        }
    }
    [_store refresh];
    [self finishHomeSessionIfAvailable];
}

- (void)finishHomeSessionIfAvailable {
    if (!_homeStartingBridge.running || !_homeStartingSessionID.length) return;
    PTSessionInfo *session = [self sessionWithID:_homeStartingSessionID];
    if (!session) return;
    PTWorkspaceTab *tab = [self createWorkspaceTab];
    tab.sessionID = session.sessionID;
    tab.bridge = _homeStartingBridge;
    tab.status = PTL(@"新对话已创建", @"New conversation created");
    [self configureBridgeCallbacksForWorkspaceTab:tab];
    _homeStartingSessionID = nil;
    _homeStartingBridge = nil;
    _homeBlankSessionDirectory = nil;
    [self activateWorkspaceTab:tab animated:NO];
    [self pushFrontendSessions];
}

- (PTSessionInfo *)sessionWithID:(NSString *)sessionID {
    if (sessionID.length == 0) return nil;
    for (PTSessionInfo *session in _sessions) {
        if ([session.sessionID isEqual:sessionID]) return session;
    }
    return nil;
}

- (PTClaudeBridge *)bridgeForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return nil;
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        if (tab.bridge.running && [tab.bridge.sessionID isEqual:sessionID]) {
            return tab.bridge;
        }
    }
    return nil;
}

- (void)prepareBridgeForSessionID:(NSString *)sessionID
                      completion:(void (^)(PTClaudeBridge *))completion {
    PTClaudeBridge *bridge = [self bridgeForSessionID:sessionID];
    if (bridge) { completion(bridge); return; }
    PTSessionInfo *session = [self sessionWithID:sessionID];
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        if (!session || ![tab.sessionID isEqual:sessionID]) continue;
        tab.connecting = YES;
        if (_activeWorkspaceTab == tab) _connecting = YES;
        [tab.bridge connectToSession:session completion:^(BOOL connected) {
            completion(connected ? tab.bridge : nil);
        }];
        return;
    }
    completion(nil);
}

- (void)presentClaudeWaiting:(BOOL)waiting forSessionID:(NSString *)sessionID {
    if (!sessionID.length) return;
    if ([_selectedSession.sessionID isEqual:sessionID]) [_lobeMainBridge deliverClaudeWaiting:waiting];
    if (_lobeFloatingPanel.visible && [_floatingSessionID isEqual:sessionID]) {
        [_lobeFloatingBridge deliverClaudeWaiting:waiting];
    }
    [self pushFrontendWorkspaceState];
    [self pushFrontendSessions];
}

- (void)presentClaudeStreamForBridge:(PTClaudeBridge *)bridge {
    if (!bridge.sessionID.length) return;
    BOOL mainVisible = _lobeMainBridge.frontendReady && [_selectedSession.sessionID isEqual:bridge.sessionID];
    BOOL floatingVisible = _lobeFloatingBridge.frontendReady && _lobeFloatingPanel.visible &&
        [_floatingSessionID isEqual:bridge.sessionID];
    if (!mainVisible && !floatingVisible) return;
    NSDictionary *snapshot = bridge.streamPayload;
    if (mainVisible) [_lobeMainBridge deliverClaudeStream:snapshot];
    if (floatingVisible) [_lobeFloatingBridge deliverClaudeStream:snapshot];
}

- (void)beginAwaitingClaudeReplyForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    if (!_awaitingClaudeBaselineBySessionID) {
        _awaitingClaudeBaselineBySessionID = [NSMutableDictionary dictionary];
    }
    PTSessionInfo *session = [self sessionWithID:sessionID];
    _awaitingClaudeBaselineBySessionID[sessionID] = @(session.assistantMessages.count);
    [self presentClaudeWaiting:YES forSessionID:sessionID];
}

- (void)finishAwaitingClaudeReplyForSessionID:(NSString *)sessionID {
    if (!_awaitingClaudeBaselineBySessionID[sessionID]) return;
    [_awaitingClaudeBaselineBySessionID removeObjectForKey:sessionID];
    [self presentClaudeWaiting:NO forSessionID:sessionID];
}

- (void)reconcileAwaitingClaudeReplyWithSession:(PTSessionInfo *)session {
    // A managed turn ends at the protocol result, never at its first transcript event.
    if ([self bridgeForSessionID:session.sessionID].running) return;
    NSNumber *baselineValue = _awaitingClaudeBaselineBySessionID[session.sessionID];
    if (!baselineValue) return;
    NSUInteger baseline = baselineValue.unsignedIntegerValue;
    NSArray<NSDictionary *> *messages = session.assistantMessages ?: @[];
    if (messages.count <= baseline) return;
    for (NSUInteger index = baseline; index < messages.count; index++) {
        NSString *role = [messages[index][@"role"] isKindOfClass:NSString.class]
            ? messages[index][@"role"] : @"";
        if (![role isEqual:@"user"]) {
            [self finishAwaitingClaudeReplyForSessionID:session.sessionID];
            _statusText = PTL(@"Claude 已开始回复", @"Claude has started responding");
            return;
        }
    }
}

- (void)updateFloatingControls {
    BOOL showingSelection = _lobeFloatingPanel.visible && [_floatingSessionID isEqual:_selectedSession.sessionID];
    _floatingMenuItem.enabled = _selectedSession.sessionID.length > 0;
    _floatingMenuItem.title = showingSelection
        ? PTL(@"关闭悬浮对话", @"Close Floating Conversation")
        : PTL(@"悬浮当前对话", @"Float Current Conversation");
}

- (void)renderFloatingSession:(PTSessionInfo *)session {
    if (!session) return;
    BOOL panelReady = _lobeFloatingBridge.frontendReady && _lobeFloatingPanel.visible;
    if (!panelReady) return;
    PTClaudeBridge *streamBridge = [self bridgeForSessionID:session.sessionID];
    if (_floatingRenderInFlight) {
        if (!_pendingFloatingSession ||
            ![_pendingFloatingSession.sessionID isEqual:session.sessionID] ||
            [_pendingFloatingSession.modifiedAt compare:session.modifiedAt] != NSOrderedDescending) {
            _pendingFloatingSession = session;
        }
        return;
    }
    if (!PTSessionRenderNeedsUpdate(
        _floatingRenderedSessionID,
        _floatingRenderedModifiedAt,
        _floatingRenderedMessageCount,
        session.sessionID,
        session.modifiedAt,
        session.assistantMessages.count
    )) return;
    [streamBridge reconcileStreamWithMessages:session.assistantMessages];


    NSUInteger messageCount = session.assistantMessages.count;
    NSArray<NSDictionary *> *messages = session.assistantMessages ?: @[];
    BOOL canAppend = [_floatingRenderedSessionID isEqual:session.sessionID] &&
        _floatingRenderedMessages != nil && _floatingRenderedMessageCount <= messageCount &&
        [[messages subarrayWithRange:NSMakeRange(0, _floatingRenderedMessageCount)] isEqualToArray:_floatingRenderedMessages];
    BOOL canPatch = [_floatingRenderedSessionID isEqual:session.sessionID] &&
        _floatingRenderedMessages != nil && _floatingRenderedMessages.count <= messageCount;
    NSMutableArray *updates = [NSMutableArray array];
    if (canPatch && !canAppend) {
        for (NSUInteger index = 0; index < _floatingRenderedMessageCount; index++) {
            NSDictionary *previous = _floatingRenderedMessages[index];
            NSDictionary *message = messages[index];
            if (![previous[@"messageKey"] isEqual:message[@"messageKey"]]) { canPatch = NO; break; }
            if (![previous isEqualToDictionary:message]) [updates addObject:message];
        }
    }
    // Copy dictionaries, not their source strings or image data. The snapshot
    // also detects in-place question/configuration revisions at the same count.
    NSMutableArray *renderSnapshot = [NSMutableArray arrayWithCapacity:messageCount];
    for (NSDictionary *message in messages) [renderSnapshot addObject:[message copy]];

    // Unchanged historical messages need only metadata and question updates.
    NSMutableDictionary *payload = [@{
        @"sessionId": session.sessionID ?: @"",
        @"title": session.title ?: @"未命名会话",
        @"cwd": session.cwd ?: @"",
        @"model": session.model ?: @"Claude",
        @"interfaceLanguage": PTInterfaceLanguageCode(),
        @"awaitingReply": @(_awaitingClaudeBaselineBySessionID[session.sessionID] != nil)
    } mutableCopy];
    payload[@"questionUpdates"] = PTQuestionUpdates(session.assistantMessages);
    if (!canAppend && !canPatch) payload[@"messages"] = session.assistantMessages ?: @[];

    NSArray<NSDictionary *> *deltaMessages = (canAppend || canPatch)
        ? [messages subarrayWithRange:NSMakeRange(_floatingRenderedMessageCount, messageCount - _floatingRenderedMessageCount)]
        : @[];

    NSUInteger generation = _floatingRenderGeneration;
    PTFrontendBridge *frontend = _lobeFloatingBridge;
    NSUInteger frontendGeneration = frontend.frontendGeneration;
    NSString *targetSessionID = [session.sessionID copy];
    NSDate *targetModifiedAt = session.modifiedAt;
    _floatingRenderInFlight = YES;
    __weak typeof(self) weakSelf = self;
    void (^finishFloatingRender)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        if (self->_lobeFloatingBridge != frontend || frontend.frontendGeneration != frontendGeneration) return;
        self->_floatingRenderInFlight = NO;
        BOOL visible = self->_lobeFloatingPanel.visible;
        BOOL stillCurrent = generation == self->_floatingRenderGeneration &&
            visible && [self->_floatingSessionID isEqual:targetSessionID];
        if (stillCurrent && !error && ok) {
            self->_floatingRenderedSessionID = targetSessionID;
            self->_floatingRenderedModifiedAt = targetModifiedAt;
            self->_floatingRenderedMessageCount = messageCount;
            self->_floatingRenderedMessages = [renderSnapshot copy];
            [self presentClaudeStreamForBridge:streamBridge];
        } else if (stillCurrent && (error || !ok)) {
            self->_lobeFloatingPanel.title = @"悬浮对话 · 显示更新失败";
        }
        PTSessionInfo *pending = self->_pendingFloatingSession;
        self->_pendingFloatingSession = nil;
        if (pending && visible) {
            [self renderFloatingSession:pending];
        }
    };

    if (canAppend) {
        [_lobeFloatingBridge deliverClaudeAppend:payload messages:deltaMessages completion:finishFloatingRender];
    } else if (canPatch) {
        [_lobeFloatingBridge deliverClaudePatch:payload updates:updates messages:deltaMessages completion:finishFloatingRender];
    } else {
        [_lobeFloatingBridge deliverClaudeSession:payload completion:finishFloatingRender];
    }
}

- (void)refreshFloatingConversation {
    if (!_lobeFloatingPanel.visible || !_floatingSessionID.length) return;
    PTSessionInfo *session = [self sessionWithID:_floatingSessionID];
    if (session) [self renderFloatingSession:session];
}

- (void)toggleFloatingConversation:(id)sender {
    (void)sender;
    BOOL visible = _lobeFloatingPanel.visible;
    PTFloatingConversationAction action = PTFloatingConversationActionForState(
        visible, _floatingSessionID, _selectedSession.sessionID);
    if (action == PTFloatingConversationActionNone) return;
    if (action == PTFloatingConversationActionClose) {
        [_lobeFloatingPanel close];
        return;
    }

    if (![_floatingSessionID isEqual:_selectedSession.sessionID]) {
        [self clearFloatingPendingImagesAfterSuccessfulSend];
        _floatingPendingImages = [NSMutableArray array];
        _floatingPendingFiles = [NSMutableArray array];
        _floatingDraft = @"";
        _floatingDraftRevision++;
    }
    _floatingSessionID = [_selectedSession.sessionID copy];
    _floatingStatusText = @"";
    _floatingRenderedSessionID = nil;
    _floatingRenderedModifiedAt = nil;
    _floatingRenderedMessageCount = 0;
    _floatingRenderedMessages = nil;
    _pendingFloatingSession = nil;
    _floatingRenderGeneration++;
    [self buildLobeFloatingPanelIfNeeded];
    if (!visible) [self positionLobeFloatingPanelNearMainWindow];
    [_lobeFloatingPanel orderFrontRegardless];
    [self syncFullSessionIDs];
    [self refreshFloatingConversation];
    [self updateFloatingControls];
    [self pushFrontendWorkspace];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object != _lobeFloatingPanel) return;
    [_lobeFloatingBridge detach];
    [_lobeFloatingWebView removeFromSuperview];
    _lobeFloatingBridge = nil;
    _lobeFloatingWebView = nil;
    _lobeFloatingPanel = nil;
    _floatingRenderGeneration++;
    _floatingRenderInFlight = NO;
    _floatingSessionID = nil;
    _floatingRenderedSessionID = nil;
    _floatingRenderedModifiedAt = nil;
    _floatingRenderedMessageCount = 0;
    _floatingRenderedMessages = nil;
    _pendingFloatingSession = nil;
    _floatingDraft = @"";
    _floatingDraftRevision++;
    [self clearFloatingPendingImagesAfterSuccessfulSend];
    _floatingPendingImages = [NSMutableArray array];
    _floatingPendingFiles = [NSMutableArray array];
    [self syncFullSessionIDs];
    [self updateFloatingControls];
    [self pushFrontendWorkspace];
}

- (BOOL)addComposerAttachmentURLs:(NSArray<NSURL *> *)urls floating:(BOOL)floating {
    NSUInteger added = 0;
    for (NSURL *url in urls ?: @[]) {
        if (!url.isFileURL) continue;
        BOOL directory = NO;
        NSString *path = url.path.stringByStandardizingPath;
        if (path.length == 0 ||
            ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory]) continue;
        if (!directory && PTIsSupportedImagePath(path)) {
            BOOL accepted = floating
                ? [self addFloatingImageURL:[NSURL fileURLWithPath:path] temporary:NO]
                : [self addImageURL:[NSURL fileURLWithPath:path] temporary:NO];
            if (accepted) added++;
            continue;
        }
        NSMutableArray<NSString *> *files = floating ? _floatingPendingFiles : _pendingFiles;
        if (![files containsObject:path]) {
            [files addObject:path.mutableCopy];
            added++;
        }
    }
    if (floating) {
        _floatingStatusText = [NSString stringWithFormat:
            PTL(@"已添加 %lu 个附件", @"Added %lu attachments"), (unsigned long)added];
    } else {
        _statusText = [NSString stringWithFormat:
            PTL(@"已添加 %lu 个附件", @"Added %lu attachments"), (unsigned long)added];
    }
    return added > 0;
}

- (BOOL)addFloatingImageURL:(NSURL *)url temporary:(BOOL)temporary {
    if (!url.isFileURL || !PTIsSupportedImagePath(url.path)) return NO;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory] || isDirectory) return NO;
    for (NSDictionary *item in _floatingPendingImages) {
        if ([item[@"path"] isEqual:url.path]) return YES;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    NSData *pngData = PTPNGDataForImageFileURL(url);
    if (!image.isValid || pngData.length == 0) return NO;
    [_floatingPendingImages addObject:@{
        @"path": url.path,
        @"image": image,
        @"pngData": pngData,
        @"thumbnail": PTAttachmentThumbnail(pngData),
        @"temporary": @(temporary)
    }];
    if (temporary) [_temporaryImagePaths addObject:url.path];
    return YES;
}

- (BOOL)handleFloatingImagePasteboard:(NSPasteboard *)pasteboard {
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    NSArray<NSURL *> *fileURLs = [pasteboard readObjectsForClasses:@[NSURL.class] options:options];
    if (fileURLs.count > 0) {
        [self addComposerAttachmentURLs:fileURLs floating:YES];
        return YES;
    }

    NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
    if (!image || !image.isValid) return NO;
    NSURL *temporaryURL = [self writeTemporaryPasteImage:image];
    if (!temporaryURL || ![self addFloatingImageURL:temporaryURL temporary:YES]) {
        _floatingStatusText = @"无法读取剪贴板图片";
        return YES;
    }
    _floatingStatusText = @"已从剪贴板添加图片";
    return YES;
}

- (void)clearFloatingPendingImagesAfterSuccessfulSend {
    for (NSDictionary *item in _floatingPendingImages.copy) {
        if (![item[@"temporary"] boolValue]) continue;
        NSString *path = item[@"path"];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [_floatingPendingImages removeAllObjects];
    [_floatingPendingFiles removeAllObjects];
}

- (BOOL)addImageURL:(NSURL *)url temporary:(BOOL)temporary {
    if (!url.isFileURL || !PTIsSupportedImagePath(url.path)) return NO;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory] || isDirectory) return NO;
    for (NSDictionary *item in _pendingImages) {
        if ([item[@"path"] isEqual:url.path]) return YES;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    NSData *pngData = PTPNGDataForImageFileURL(url);
    if (!image.isValid || pngData.length == 0) return NO;
    [_pendingImages addObject:@{
        @"path": url.path,
        @"image": image,
        @"pngData": pngData,
        @"thumbnail": PTAttachmentThumbnail(pngData),
        @"temporary": @(temporary)
    }];
    if (temporary) [_temporaryImagePaths addObject:url.path];
    return YES;
}

- (NSURL *)writeTemporaryPasteImage:(NSImage *)image {
    NSData *png = PTPNGDataForImage(image);
    if (!png.length) return nil;
    NSString *fileName = [NSString stringWithFormat:@"PrettyTerm-paste-%@.png", NSUUID.UUID.UUIDString];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    return [png writeToFile:path atomically:YES] ? [NSURL fileURLWithPath:path] : nil;
}

- (BOOL)handleImagePasteboard:(NSPasteboard *)pasteboard {
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    NSArray<NSURL *> *fileURLs = [pasteboard readObjectsForClasses:@[NSURL.class] options:options];
    if (fileURLs.count > 0) {
        [self addComposerAttachmentURLs:fileURLs floating:NO];
        return YES;
    }

    NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
    if (!image || !image.isValid) return NO;
    NSURL *temporaryURL = [self writeTemporaryPasteImage:image];
    if (!temporaryURL || ![self addImageURL:temporaryURL temporary:YES]) {
        _statusText = @"无法读取剪贴板图片";
        return YES;
    }
    _statusText = @"已从剪贴板添加图片";
    return YES;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSArray<NSArray<NSString *> *> *)composerModelEntries {
    return @[
        @[@"Claude Fable 5.2", @"Fable 5.2", @"claude-fable-5-2"],
        @[@"Claude Opus 5.5", @"Opus 5.5", @"claude-opus-5-5"],
        @[@"Claude Sonnet 5.5", @"Sonnet 5.5", @"claude-sonnet-5-5"],
        @[@"Claude Sonnet 4.6", @"Sonnet 4.6", @"claude-sonnet-4-6"],
        @[@"Claude Haiku 4.5", @"Haiku 4.5", @"claude-haiku-4-5"]
    ];
}

- (NSArray<NSString *> *)composerEffortLevels {
    return @[@"low", @"medium", @"high", @"xhigh", @"max"];
}

- (NSString *)composerEffortTitle:(NSString *)effort {
    if (!effort) return PTL(@"未读取", @"Unknown");
    if (!effort.length) return PTL(@"默认", @"Default");
    NSDictionary *titles = @{
        @"low": @[PTL(@"低", @"Low"), @""],
        @"medium": @[PTL(@"中", @"Medium"), @""],
        @"high": @[PTL(@"高", @"High"), @""],
        @"xhigh": @[PTL(@"极高", @"XHigh"), @""],
        @"max": @[PTL(@"最高", @"Max"), @""]
    };
    NSArray *entry = titles[effort.lowercaseString];
    return entry.count ? entry.firstObject : PTL(@"推理强度", @"Effort");
}

- (NSString *)composerModelShortTitle:(NSString *)modelID {
    for (NSArray<NSString *> *entry in [self composerModelEntries]) {
        if ([entry[2] isEqual:modelID]) return entry[1];
    }
    return modelID.length ? modelID : PTL(@"当前模型", @"Current model");
}

- (NSString *)composerModelForSessionID:(NSString *)sessionID {
    return sessionID.length ? [self bridgeForSessionID:sessionID].currentModel : _selectedComposerModelID;
}

- (NSString *)composerEffortForSessionID:(NSString *)sessionID {
    PTClaudeBridge *bridge = [self bridgeForSessionID:sessionID];
    if (bridge) return bridge.currentEffort;
    if (sessionID.length) return [self sessionWithID:sessionID].effort;
    return _selectedComposerEffort;
}

- (void)updateComposerConfigurationButtons {
    [self pushFrontendWindowState];
    [self pushFrontendSessions];
}

- (void)showConfigurationStatus:(NSString *)status forSessionID:(NSString *)sessionID {
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        if ([tab.sessionID isEqual:sessionID]) {
            tab.status = status;
            tab.commandOutput = status;
        }
    }
    if ([_selectedSession.sessionID isEqual:sessionID]) _statusText = status;
    if ([_floatingSessionID isEqual:sessionID]) _floatingStatusText = status;
}

- (NSArray<NSDictionary *> *)commandSuggestions:(PTClaudeBridge *)bridge query:(NSString *)query {
    NSDictionary *labels = @{
        @"compact": @[PTL(@"压缩", @"Compact"), PTL(@"压缩当前聊天的上下文", @"Compact this conversation's context"), @"arrow.down.right.and.arrow.up.left"],
        @"model": @[PTL(@"模型", @"Model"), PTL(@"选择当前会话使用的模型", @"Choose the model for this conversation"), @"cpu"],
        @"effort": @[PTL(@"推理", @"Reasoning"), PTL(@"调整推理强度", @"Adjust reasoning effort"), @"brain"],
        @"mode": @[PTL(@"模式", @"Mode"), PTL(@"切换 Plan、Auto、Bypass 等模式", @"Switch Plan, Auto, Bypass and other modes"), @"slider.horizontal.3"],
        @"config": @[PTL(@"设置", @"Settings"), PTL(@"打开会话配置", @"Open conversation settings"), @"gearshape"],
        @"context": @[PTL(@"上下文", @"Context"), PTL(@"查看上下文占用情况", @"Inspect context usage"), @"chart.pie"],
        @"usage": @[PTL(@"套餐用量", @"Plan usage"), PTL(@"查看套餐额度与使用情况", @"View plan limits and usage"), @"gauge.medium"],
        @"cost": @[PTL(@"费用", @"Cost"), PTL(@"查看本次会话的用量和费用", @"View conversation usage and cost"), @"dollarsign.circle"],
        @"mcp": @[@"MCP", PTL(@"查看 MCP 服务器状态", @"View MCP server status"), @"puzzlepiece.extension"],
        @"init": @[PTL(@"初始化", @"Initialize"), PTL(@"为项目创建 CLAUDE.md 说明", @"Create project instructions in CLAUDE.md"), @"doc.text"],
        @"clear": @[PTL(@"清空", @"Clear"), PTL(@"清空当前会话上下文", @"Clear the conversation context"), @"trash"],
        @"plan": @[@"Plan", PTL(@"进入计划模式", @"Enter plan mode"), @"list.bullet.clipboard"],
        @"auto": @[@"Auto", PTL(@"进入自动模式", @"Enter auto mode"), @"sparkles"],
        @"bypass": @[@"Bypass", PTL(@"进入 Bypass 模式", @"Enter bypass mode"), @"bolt"],
        @"fast": @[PTL(@"快速", @"Fast"), PTL(@"切换快速模式", @"Toggle fast mode"), @"bolt"],
        @"commands": @[PTL(@"全部指令", @"Commands"), PTL(@"浏览可用的 Claude 指令", @"Browse available Claude commands"), @"command"]
    };
    NSArray *preferred = @[@"compact", @"model", @"effort", @"mode", @"config", @"context", @"usage", @"cost", @"mcp", @"init"];
    NSMutableArray *source = [bridge.commands mutableCopy] ?: [NSMutableArray array];
    NSMutableSet *names = [NSMutableSet set];
    for (NSDictionary *command in source) if (command[@"name"]) [names addObject:command[@"name"]];
    for (NSString *name in @[@"config", @"model", @"effort", @"mode", @"plan", @"auto", @"bypass", @"commands"])
        if (![names containsObject:name]) [source addObject:@{@"name": name}];
    [names removeAllObjects];
    NSString *needle = [query stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:NSLocale.currentLocale];
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *command in source) {
        NSString *name = command[@"name"];
        if (!name.length || [names containsObject:name]) continue;
        [names addObject:name];
        NSArray *label = labels[name];
        NSString *title = label ? label[0] : [@"/" stringByAppendingString:name];
        NSString *detail = label ? label[1] : (command[@"description"] ?: @"");
        NSString *hint = command[@"argumentHint"] ?: @"";
        if (hint.length) detail = [NSString stringWithFormat:@"%@  %@", detail, hint];
        NSString *search = [[NSString stringWithFormat:@"%@ %@ %@ %@", name, title, detail, command[@"description"] ?: @""]
            stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:NSLocale.currentLocale];
        NSInteger score = 0;
        if (needle.length) {
            NSString *foldedName = name.lowercaseString;
            if ([foldedName isEqual:needle]) score = 0;
            else if ([foldedName hasPrefix:needle]) score = 10;
            else if ([title.lowercaseString hasPrefix:needle]) score = 20;
            else if ([search containsString:needle]) score = 40;
            else {
                NSUInteger offset = 0;
                BOOL matches = YES;
                for (NSUInteger index = 0; index < needle.length; index++) {
                    NSRange match = [foldedName rangeOfString:[needle substringWithRange:NSMakeRange(index, 1)]
                        options:0 range:NSMakeRange(offset, foldedName.length - offset)];
                    if (match.location == NSNotFound) { matches = NO; break; }
                    offset = NSMaxRange(match);
                }
                if (!matches) continue;
                score = 80 + (NSInteger)foldedName.length;
            }
        }
        NSUInteger priority = [preferred indexOfObject:name];
        [results addObject:@{@"name": name, @"title": title, @"detail": detail,
            @"icon": label ? label[2] : @"command", @"score": @(score),
            @"priority": @(priority == NSNotFound ? preferred.count : priority)}];
    }
    [results sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"score"] compare:b[@"score"]];
        if (order == NSOrderedSame) order = [a[@"priority"] compare:b[@"priority"]];
        if (order == NSOrderedSame) order = [a[@"name"] localizedStandardCompare:b[@"name"]];
        return order;
    }];
    return results;
}

- (void)refreshAgentStateAndControls {
    _agentState.selectedSessionID = _selectedSession.sessionID ?: @"";
    _agentState.boundSessionID = _bridge.sessionID ?: @"";
    _agentState.bridgeRunning = _bridge.running;
    [self pushFrontendWorkspace];
    [self pushFrontendWindowState];
}

- (void)finishClaudeUsageWithPayload:(NSDictionary *)payload error:(NSString *)errorMessage {
    NSDictionary *fiveHour = [payload[@"five_hour"] isKindOfClass:NSDictionary.class]
        ? payload[@"five_hour"] : nil;
    NSDictionary *sevenDay = [payload[@"seven_day"] isKindOfClass:NSDictionary.class]
        ? payload[@"seven_day"] : nil;
    NSNumber *fiveValue = [fiveHour[@"utilization"] isKindOfClass:NSNumber.class]
        ? fiveHour[@"utilization"] : nil;
    NSNumber *sevenValue = [sevenDay[@"utilization"] isKindOfClass:NSNumber.class]
        ? sevenDay[@"utilization"] : nil;
    if (fiveValue && sevenValue) {
        _planUsageAvailable = YES;
        _fiveHourPercent = MIN(100.0, MAX(0.0, fiveValue.doubleValue));
        _sevenDayPercent = MIN(100.0, MAX(0.0, sevenValue.doubleValue));
        _fiveHourResetAt = PTDateFromClaudeAPIString(fiveHour[@"resets_at"]);
        _sevenDayResetAt = PTDateFromClaudeAPIString(sevenDay[@"resets_at"]);
        _planUsageError = nil;
    } else {
        _planUsageAvailable = NO;
        _fiveHourPercent = 0;
        _sevenDayPercent = 0;
        _fiveHourResetAt = nil;
        _sevenDayResetAt = nil;
        _planUsageError = errorMessage.length ? errorMessage : @"Claude 未返回额度字段";
    }
    [self pushFrontendWindowState];
}

- (void)refreshClaudeUsage:(NSTimer *)timer {
    (void)timer;
    [[self bridgeForSessionID:_selectedSession.sessionID] refreshUsage];
}

- (void)selectObservedGitDirectory:(NSString *)path {
    _gitObservedDirectory = [_gitDirectoryPaths containsObject:path ?: @""]
        ? [path copy] : [_gitDirectoryPaths.firstObject copy];
}

- (void)rememberGitDirectoriesForSession:(PTSessionInfo *)session {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    for (NSString *path in session.accessedDirectories ?: @[]) {
        if ([path isKindOfClass:NSString.class] && [path hasPrefix:@"/"] &&
            ![_suppressedGitDirectoryPaths containsObject:path]) {
            [paths addObject:path];
        }
    }
    if (session.cwd.length > 0 && [session.cwd hasPrefix:@"/"] &&
        ![_suppressedGitDirectoryPaths containsObject:session.cwd]) {
        [paths addObject:session.cwd];
    }
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:@"PTGitObservedDirectories"];
    for (id value in stored ?: @[]) {
        if (PTStoredDirectoryPathIsValid(value)) [paths addObject:value];
    }
    NSArray<NSString *> *nextPaths = paths.array;
    NSString *preferred = _gitObservedDirectory;
    if (!_gitDirectoryManuallySelected && !_gitObservedDirectory.length) {
        preferred = session.accessedDirectories.lastObject ?: session.cwd;
    }
    if (![_gitDirectoryPaths isEqualToArray:nextPaths]) {
        _gitDirectoryPaths = [nextPaths mutableCopy];
        [NSUserDefaults.standardUserDefaults setObject:nextPaths forKey:@"PTGitObservedDirectories"];
        [self selectObservedGitDirectory:preferred];
    } else if (!_gitObservedDirectory.length && nextPaths.count > 0) {
        [self selectObservedGitDirectory:preferred];
    }
}

- (NSArray<NSDictionary *> *)transcriptEditEventsForSession:(PTSessionInfo *)session
                                                   turnIndex:(NSUInteger)turnIndex {
    NSMutableArray<NSDictionary *> *edits = [NSMutableArray array];
    NSInteger currentTurn = -1;
    for (NSDictionary *event in session.assistantMessages ?: @[]) {
        BOOL isUser = [event[@"role"] isEqual:@"user"];
        if (isUser) {
            currentTurn++;
            continue;
        }
        if (currentTurn < 0) currentTurn = 0;
        if ((NSUInteger)currentTurn == turnIndex && [event[@"kind"] isEqual:@"diff"]) {
            [edits addObject:event];
        }
    }
    return edits;
}

- (void)connectStoreAndBridge {
    _store = [[PTSessionStore alloc] init];
    __weak typeof(self) weakSelf = self;
    _store.sessionsChanged = ^(NSArray<PTSessionInfo *> *sessions) {
        [weakSelf applySessions:sessions];
    };
    _store.globalModelChanged = ^(NSString *model) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        self->_selectedComposerModelID = [model copy];
        [self pushFrontendWindowState];
    };
    _store.globalEffortChanged = ^(NSString *effort) {
        PTAppDelegate *self = weakSelf;
        if (!self || effort.length == 0) return;
        if (self->_bridge.currentEffort.length) return;
        self->_selectedComposerEffort = effort;
        if (self->_selectedSession && self->_bridge.running &&
            [self->_bridge.sessionID isEqual:self->_selectedSession.sessionID]) {
            self->_selectedSession.effort = effort;
        }
        [self updateComposerConfigurationButtons];
    };
    if (_workspaceTabs.count == 0) {
        PTWorkspaceTab *initialTab = [self createWorkspaceTab];
        _activeWorkspaceTab = initialTab;
        _bridge = initialTab.bridge;
        _pendingImages = initialTab.pendingImages;
        _pendingFiles = initialTab.pendingFiles;
    }
    [self updateWorkspaceTabBar];
    [_store startWatchingGlobalSettings];
}

- (void)applySessions:(NSArray<PTSessionInfo *> *)sessions {
    NSMutableArray<PTSessionInfo *> *combined = [sessions mutableCopy];
    for (PTSessionInfo *session in sessions) {
        if (session.filePath.length) [_newSessionsAwaitingTranscript removeObjectForKey:session.sessionID];
    }
    for (PTSessionInfo *pending in _newSessionsAwaitingTranscript.allValues) {
        BOOL present = NO;
        for (PTSessionInfo *session in combined) if ([session.sessionID isEqual:pending.sessionID]) { present = YES; break; }
        if (!present) [combined addObject:pending];
    }
    sessions = combined;
    NSDictionary<NSString *, NSString *> *titles = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"PTSessionTitleOverrides"];
    for (PTSessionInfo *session in sessions) {
        NSString *title = titles[session.sessionID];
        if ([title isKindOfClass:NSString.class]) session.title = title;
    }
    NSMutableArray<NSString *> *signatureParts = [NSMutableArray arrayWithCapacity:sessions.count];
    for (PTSessionInfo *session in sessions) {
        if (session.fullTranscriptLoaded) [self reconcileAwaitingClaudeReplyWithSession:session];
        [signatureParts addObject:[NSString stringWithFormat:@"%@|%.6f|%lu|%d|%@|%@",
            session.sessionID,
            session.modifiedAt.timeIntervalSince1970,
            (unsigned long)PTSessionTurnCount(session),
            session.fullTranscriptLoaded,
            session.title,
            session.cwd]];
    }
    NSString *signature = [signatureParts componentsJoinedByString:@"\n"];
    BOOL manualRefresh = _manualRefreshSessionID.length > 0;
    if ([_sessionListSignature isEqual:signature] && !manualRefresh) return;
    _sessionListSignature = signature;

    NSString *selectedID = _selectedSession.sessionID;
    _sessions = sessions;

    PTSessionInfo *nextSelectedSession = nil;
    if (selectedID.length) {
        for (PTSessionInfo *session in sessions) {
            if ([session.sessionID isEqual:selectedID]) {
                nextSelectedSession = session;
                break;
            }
        }
    }
    BOOL initialWorkspaceSelection = _workspaceTabs.count == 1 &&
        _activeWorkspaceTab.sessionID.length == 0 && _selectedSession == nil;
    if (!nextSelectedSession && initialWorkspaceSelection && sessions.count > 0) {
        nextSelectedSession = sessions.firstObject;
    }
    if (nextSelectedSession) {
        _selectedSession = nextSelectedSession;
        _activeWorkspaceTab.sessionID = nextSelectedSession.sessionID ?: @"";
        if (manualRefresh && [_manualRefreshSessionID isEqual:_selectedSession.sessionID]) {
            _renderedSessionID = nil;
            _renderedModifiedAt = nil;
            _renderedMessageCount = 0;
            _renderedMessages = nil;
        }
        [self showSelectedSession];
    } else if (selectedID.length > 0 || _selectedSession == nil) {
        _activeWorkspaceTab.sessionID = @"";
        [self showEmptyWorkspaceTab];
    }
    if (manualRefresh && [_manualRefreshSessionID isEqual:_floatingSessionID]) {
        _floatingRenderedSessionID = nil;
        _floatingRenderedModifiedAt = nil;
        _floatingRenderedMessageCount = 0;
        _floatingRenderedMessages = nil;
    }
    [self refreshFloatingConversation];
    [self updateFloatingControls];
    _manualRefreshSessionID = nil;
    if (!_bridge.running) {
        _statusText = [NSString stringWithFormat:PTL(@"已发现 %lu 个本地会话", @"Found %lu local conversations"), (unsigned long)sessions.count];
    }
    [self finishHomeSessionIfAvailable];
    [self pushFrontendSessions];
    [self pushFrontendWindowState];
    [self pushFrontendWorkspace];
}

- (void)syncFullSessionIDs {
    if (!_store) return;
    NSMutableSet<NSString *> *sessionIDs = [NSMutableSet set];
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        if (tab.sessionID.length) [sessionIDs addObject:tab.sessionID];
    }
    if (_lobeFloatingPanel.visible && _floatingSessionID.length)
        [sessionIDs addObject:_floatingSessionID];
    if ([sessionIDs isEqualToSet:_store.fullSessionIDs]) return;
    _store.fullSessionIDs = sessionIDs;
    [_store refresh];
}

- (void)showSelectedSession {
    if (!_selectedSession) return;
    _activeWorkspaceTab.sessionID = _selectedSession.sessionID ?: @"";
    [self syncFullSessionIDs];
    [self watchSelectedSessionTranscript];
    if (![_planUsageSessionID isEqual:_selectedSession.sessionID]) {
        _planUsageSessionID = [_selectedSession.sessionID copy];
        [self finishClaudeUsageWithPayload:nil error:PTL(@"正在读取 Claude Code 套餐用量…", @"Reading Claude Code plan usage…")];
        NSString *requestedID = _planUsageSessionID;
        [self prepareBridgeForSessionID:requestedID completion:^(PTClaudeBridge *bridge) {
            if (bridge) [bridge refreshUsage];
            else if ([self->_selectedSession.sessionID isEqual:requestedID])
                [self finishClaudeUsageWithPayload:nil error:self->_bridge.lastSendError];
        }];
    }
    [self rememberGitDirectoriesForSession:_selectedSession];
    [self renderSession:_selectedSession];
    [self updateFloatingControls];
    [self pushFrontendGitState];
}

- (void)watchSelectedSessionTranscript {
    NSString *path = _selectedSession.filePath ?: @"";
    if ([_watchedTranscriptPath isEqual:path]) return;
    [_transcriptWatcher stopWatching];
    _watchedTranscriptPath = [path copy];
    if (path.length == 0) return;

    __weak typeof(self) weakSelf = self;
    [_transcriptWatcher watchFileAtPath:path onChange:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            PTAppDelegate *self = weakSelf;
            if (!self || ![self->_watchedTranscriptPath isEqual:path]) return;
            NSString *expectedSessionID = [self->_selectedSession.sessionID copy];
            [self->_store refreshChangedPath:path completion:^(PTSessionInfo *session) {
                PTAppDelegate *self = weakSelf;
                if (!self || !session || ![self->_watchedTranscriptPath isEqual:path]) return;
                if (expectedSessionID.length > 0 &&
                    ![session.sessionID isEqual:expectedSessionID]) return;

                NSMutableArray<PTSessionInfo *> *updated =
                    [self->_sessions mutableCopy] ?: [NSMutableArray array];
                NSUInteger index = [updated indexOfObjectPassingTest:
                    ^BOOL(PTSessionInfo *candidate, NSUInteger itemIndex, BOOL *stop) {
                        (void)itemIndex;
                        (void)stop;
                        return [candidate.sessionID isEqual:session.sessionID] ||
                            [candidate.filePath isEqual:path];
                    }];
                if (index == NSNotFound) [updated addObject:session];
                else updated[index] = session;
                [self applySessions:updated];
            }];
        });
    }];
}

// 被 applySessions（每 1.5 秒一次）和 tableViewSelectionDidChange 双双调用到。
// JSONL 只追加新消息时走 DOM 增量追加，保留老师展开的 details、选区和滚动位置；
// 切换会话、消息数减少或同数量内容修订时使用当前完整快照。
- (void)renderSession:(PTSessionInfo *)session {
    if (!session) return;
    BOOL viewReady = _lobeMainBridge.frontendReady;
    if (!viewReady) return;
    PTClaudeBridge *streamBridge = [self bridgeForSessionID:session.sessionID];
    if (_renderInFlight) {
        if (!_pendingRenderSession ||
            ![_pendingRenderSession.sessionID isEqual:session.sessionID] ||
            [_pendingRenderSession.modifiedAt compare:session.modifiedAt] != NSOrderedDescending) {
            _pendingRenderSession = session;
        }
        return;
    }
    NSUInteger messageCount = session.assistantMessages.count;
    if (!PTSessionRenderNeedsUpdate(
        _renderedSessionID,
        _renderedModifiedAt,
        _renderedMessageCount,
        session.sessionID,
        session.modifiedAt,
        messageCount
    )) return;
    [streamBridge reconcileStreamWithMessages:session.assistantMessages];


    NSArray<NSDictionary *> *messages = session.assistantMessages ?: @[];
    BOOL canAppend = [_renderedSessionID isEqual:session.sessionID] &&
        _renderedMessages != nil && _renderedMessageCount <= messageCount &&
        [[messages subarrayWithRange:NSMakeRange(0, _renderedMessageCount)] isEqualToArray:_renderedMessages];
    BOOL canPatch = [_renderedSessionID isEqual:session.sessionID] &&
        _renderedMessages != nil && _renderedMessages.count <= messageCount;
    NSMutableArray *updates = [NSMutableArray array];
    if (canPatch && !canAppend) {
        for (NSUInteger index = 0; index < _renderedMessageCount; index++) {
            NSDictionary *previous = _renderedMessages[index];
            NSDictionary *message = messages[index];
            if (![previous[@"messageKey"] isEqual:message[@"messageKey"]]) { canPatch = NO; break; }
            if (![previous isEqualToDictionary:message]) [updates addObject:message];
        }
    }
    // Copy dictionaries, not their source strings or image data. The snapshot
    // also detects in-place question/configuration revisions at the same count.
    NSMutableArray *renderSnapshot = [NSMutableArray arrayWithCapacity:messageCount];
    for (NSDictionary *message in messages) [renderSnapshot addObject:[message copy]];

    // Unchanged historical messages need only metadata and question updates.
    NSMutableDictionary *payload = [@{
        @"sessionId": session.sessionID ?: @"",
        @"title": session.title ?: @"未命名会话",
        @"cwd": session.cwd ?: @"",
        @"model": session.model ?: @"Claude",
        @"interfaceLanguage": PTInterfaceLanguageCode(),
        @"awaitingReply": @(_awaitingClaudeBaselineBySessionID[session.sessionID] != nil)
    } mutableCopy];
    payload[@"questionUpdates"] = PTQuestionUpdates(session.assistantMessages);
    if (!canAppend && !canPatch) payload[@"messages"] = session.assistantMessages ?: @[];

    NSArray<NSDictionary *> *deltaMessages = (canAppend || canPatch)
        ? [messages subarrayWithRange:NSMakeRange(_renderedMessageCount, messageCount - _renderedMessageCount)]
        : @[];

    NSString *targetSessionID = [session.sessionID copy];
    NSDate *targetModifiedAt = session.modifiedAt;
    PTFrontendBridge *frontend = _lobeMainBridge;
    NSUInteger frontendGeneration = frontend.frontendGeneration;
    _renderInFlight = YES;
    __weak typeof(self) weakSelf = self;
    void (^finishMainRender)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
        PTAppDelegate *self = weakSelf;
        if (!self || frontend.frontendGeneration != frontendGeneration) return;
        self->_renderInFlight = NO;
        BOOL stillCurrent = [self->_selectedSession.sessionID isEqual:targetSessionID];
        if (stillCurrent && (error || !ok)) {
            self->_statusText = PTL(@"显示更新失败", @"Display update failed");
            [self pushFrontendWindowState];
        } else if (stillCurrent) {
            self->_renderedSessionID = targetSessionID;
            self->_renderedMessageCount = messageCount;
            self->_renderedMessages = [renderSnapshot copy];
            self->_renderedModifiedAt = targetModifiedAt;
            [self presentClaudeStreamForBridge:streamBridge];
        }

        PTSessionInfo *pending = self->_pendingRenderSession;
        self->_pendingRenderSession = nil;
        if (pending) [self renderSession:pending];
    };

    if (canAppend) {
        [_lobeMainBridge deliverClaudeAppend:payload messages:deltaMessages completion:finishMainRender];
    } else if (canPatch) {
        [_lobeMainBridge deliverClaudePatch:payload updates:updates messages:deltaMessages completion:finishMainRender];
    } else {
        [_lobeMainBridge deliverClaudeSession:payload completion:finishMainRender];
    }
}

- (void)renameSession:(PTSessionInfo *)session toTitle:(NSString *)title {
    NSMutableDictionary *titles = [[NSUserDefaults.standardUserDefaults dictionaryForKey:@"PTSessionTitleOverrides"] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    titles[session.sessionID] = title;
    [NSUserDefaults.standardUserDefaults setObject:titles forKey:@"PTSessionTitleOverrides"];
    session.title = title;
    [self applySessions:_sessions ?: @[]];
    [self syncClaudeRenameForSession:session title:title];
}

- (PTClaudeBridge *)newRenameBridge { return [PTClaudeBridge new]; }

- (void)sendClaudeRenameTitle:(NSString *)title usingBridge:(PTClaudeBridge *)bridge {
    NSString *command = [@"/rename " stringByAppendingString:title];
    BOOL sent = [bridge sendMessage:command];
    _statusText = sent
        ? PTL(@"已向 Claude 发送重命名指令", @"Rename command sent to Claude")
        : PTL(@"本地名称已保存，Terminal 未接受重命名指令", @"Local name saved; Terminal did not accept the rename command");
}

- (void)syncClaudeRenameForSession:(PTSessionInfo *)session title:(NSString *)title {
    NSString *sessionID = [session.sessionID copy];
    if (_renameConnections[sessionID]) {
        _pendingRenameTitles[sessionID] = title;
        return;
    }
    PTClaudeBridge *connected = [self bridgeForSessionID:sessionID];
    if (connected) {
        [self sendClaudeRenameTitle:title usingBridge:connected];
        return;
    }
    if (!_renameConnections) _renameConnections = [NSMutableDictionary dictionary];
    if (!_pendingRenameTitles) _pendingRenameTitles = [NSMutableDictionary dictionary];
    PTClaudeBridge *connection = [self newRenameBridge];
    _renameConnections[sessionID] = connection;
    _pendingRenameTitles[sessionID] = title;
    _statusText = PTL(@"正在接入 Claude 并同步名称…", @"Connecting to Claude to sync the name…");
    __weak typeof(self) weakSelf = self;
    __weak PTClaudeBridge *weakConnection = connection;
    connection.statusChanged = ^(NSString *status) {
        PTAppDelegate *self = weakSelf;
        PTClaudeBridge *bridge = weakConnection;
        if (!self || !bridge || self->_renameConnections[sessionID] != bridge) return;
        NSString *pendingTitle = self->_pendingRenameTitles[sessionID];
        [self->_pendingRenameTitles removeObjectForKey:sessionID];
        bridge.statusChanged = nil;
        if (bridge.running && [bridge.sessionID isEqual:sessionID]) {
            bridge.turnCompleted = ^{
                PTAppDelegate *self = weakSelf;
                PTClaudeBridge *bridge = weakConnection;
                if (!self || !bridge) return;
                NSString *nextTitle = self->_pendingRenameTitles[sessionID];
                [self->_pendingRenameTitles removeObjectForKey:sessionID];
                if (nextTitle.length) {
                    [self sendClaudeRenameTitle:nextTitle usingBridge:bridge];
                    return;
                }
                bridge.turnCompleted = nil;
                [bridge stop];
                [self->_renameConnections removeObjectForKey:sessionID];
            };
            [self sendClaudeRenameTitle:pendingTitle usingBridge:bridge];
        } else {
            [self->_renameConnections removeObjectForKey:sessionID];
            self->_statusText = [NSString stringWithFormat:PTL(@"本地名称已保存，Claude 名称同步失败：%@", @"Local name saved; Claude name sync failed: %@"), status ?: @""];
        }
    };
    [connection connectToSession:session];
}

- (void)refreshSessions:(id)sender {
    (void)sender;
    [_store refresh];
}

- (void)connectSelectedSession:(id)sender {
    if (!_selectedSession) return;
    PTWorkspaceTab *requestedWorkspaceTab = _activeWorkspaceTab;
    NSString *requestedSessionID = [_selectedSession.sessionID copy];
    NSString *requestedPath = [_selectedSession.filePath copy];
    _connecting = YES;
    _activeWorkspaceTab.connecting = YES;
    _activeWorkspaceTab.sessionID = requestedSessionID ?: @"";
    _agentState.sendInFlight = NO;
    [_bridge connectToSession:_selectedSession];
    [self updateWorkspaceTabBar];
    __weak typeof(self) weakSelf = self;
    [_store refreshForcingPath:_selectedSession.filePath completion:^(PTSessionInfo *session) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        if (!session || ![session.sessionID isEqual:requestedSessionID]) {
            NSString *status = @"JSONL 会话文件不存在或无法读取";
            requestedWorkspaceTab.status = status;
            if (self->_activeWorkspaceTab == requestedWorkspaceTab) {
                self->_statusText = status;
            }
            return;
        }
        NSMutableArray<PTSessionInfo *> *updated = [self->_sessions mutableCopy] ?: [NSMutableArray array];
        NSUInteger index = [updated indexOfObjectPassingTest:
            ^BOOL(PTSessionInfo *candidate, NSUInteger itemIndex, BOOL *stop) {
                (void)itemIndex;
                (void)stop;
                return [candidate.sessionID isEqual:requestedSessionID] ||
                    [candidate.filePath isEqual:requestedPath];
            }];
        if (index == NSNotFound) [updated addObject:session];
        else updated[index] = session;
        self->_manualRefreshSessionID = requestedSessionID;
        [self applySessions:updated];
        NSString *status = [NSString stringWithFormat:@"已从 JSONL 完整同步 · %lu 条消息",
            (unsigned long)session.assistantMessages.count];
        requestedWorkspaceTab.status = status;
        if (self->_activeWorkspaceTab == requestedWorkspaceTab) {
            self->_statusText = status;
        }
    }];
}

- (BOOL)interruptClaudeOutputForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return NO;
    PTClaudeBridge *targetBridge = [self bridgeForSessionID:sessionID];
    if (!targetBridge.running || ![targetBridge sendEscape]) return NO;
    // Keep Stop available until Claude confirms completion of the interrupted turn.
    return YES;
}

- (BOOL)submitOutgoingMessage:(NSString *)message
                    imagePNGs:(NSArray<NSData *> *)imagePNGs
                 forSessionID:(NSString *)sessionID
                   completion:(void (^)(NSString *error))completion {
    NSString *outgoing = PTMessageForClaudeAttachments(message, imagePNGs.count);
    if (!outgoing.length) {
        completion(PTL(@"消息为空", @"Empty message"));
        return NO;
    }
    BOOL configuration = !imagePNGs.count && [self isConfigurationCommand:outgoing];
    if (!configuration && _agentState.sendInFlight) {
        completion(PTL(@"正在提交到 Claude Code…", @"Submitting to Claude Code…"));
        return NO;
    }

    PTClaudeBridge *target = [self bridgeForSessionID:sessionID];
    if (!target) {
        PTClaudeBridge *attempted = nil;
        for (PTWorkspaceTab *tab in _workspaceTabs) {
            if ([tab.sessionID isEqual:sessionID]) { attempted = tab.bridge; break; }
        }
        [self prepareBridgeForSessionID:sessionID completion:^(PTClaudeBridge *connected) {
            if (connected) {
                [self submitOutgoingMessage:message imagePNGs:imagePNGs
                               forSessionID:sessionID completion:completion];
            } else {
                completion(attempted.lastSendError ?: PTL(@"无法连接 Claude Code 会话", @"Could not connect to the Claude Code conversation"));
            }
        }];
        return YES;
    }

    if (!configuration) _agentState.sendInFlight = YES;
    [target submitMessage:outgoing withImagePNGs:imagePNGs ?: @[] completion:^(BOOL sent) {
        if (!configuration) self->_agentState.sendInFlight = NO;
        completion(sent ? nil : (target.lastSendError ?: PTL(@"Claude 未接受消息", @"Claude did not accept the message")));
    }];
    return YES;
}

- (BOOL)sendOutgoingMessage:(NSString *)message
                  imagePNGs:(NSArray<NSData *> *)imagePNGs
               forSessionID:(NSString *)sessionID
                    success:(dispatch_block_t)success
           failureResponder:(NSResponder *)failureResponder {
    return [self submitOutgoingMessage:message imagePNGs:imagePNGs forSessionID:sessionID completion:^(NSString *error) {
        if (!error) {
            if (success) success();
            return;
        }
        if ([sessionID isEqual:self->_floatingSessionID]) self->_floatingStatusText = error;
        if ([sessionID isEqual:self->_selectedSession.sessionID]) {
            self->_statusText = error;
            if (failureResponder) [self->_window makeFirstResponder:failureResponder];
        }
        [self pushFrontendWindowState];
    }];
}

- (BOOL)isConfigurationCommand:(NSString *)text {
    NSString *command = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [command hasPrefix:@"/model "] || [command hasPrefix:@"/effort "] || [command hasPrefix:@"/mode "] ||
        [@[@"/plan", @"/auto", @"/bypass", @"/remote-control"] containsObject:command];
}

- (void)presentClaudeToolRequest:(NSString *)requestID request:(NSDictionary *)request bridge:(PTClaudeBridge *)bridge {
    // These requests originate in Claude Code's selected mode. The host only
    // renders and returns the user's answer; it does not introduce a policy.
    NSDictionary *input = request[@"input"] ?: @{};
    if ([request[@"tool_name"] isEqual:@"AskUserQuestion"]) {
        _protocolQuestions[requestID] = @{@"bridge": bridge, @"sessionID": bridge.sessionID,
            @"toolUseId": request[@"tool_use_id"] ?: @"", @"input": input};
        [_pendingQuestionRequests addObject:@{@"id": requestID, @"questions": input[@"questions"] ?: @[]}];
        [self presentNextQuestionRequestIfIdle];
        return;
    }
    NSString *sessionID = [bridge.sessionID copy];
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Claude Code · %@ · %@", [self sessionWithID:sessionID].title ?: sessionID, request[@"tool_name"] ?: @""];
    alert.informativeText = request[@"decision_reason"] ?: PTL(@"Claude Code 请求执行以下操作", @"Claude Code requests the following action");
    [alert addButtonWithTitle:PTL(@"允许", @"Allow")];
    [alert addButtonWithTitle:PTL(@"拒绝", @"Deny")];
    NSData *json = [NSJSONSerialization dataWithJSONObject:input options:NSJSONWritingPrettyPrinted error:nil];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 460, 220)];
    scroll.hasVerticalScroller = YES;
    NSTextView *details = [[NSTextView alloc] initWithFrame:scroll.bounds];
    details.editable = NO; details.autoresizingMask = NSViewWidthSizable;
    details.textContainer.widthTracksTextView = YES;
    details.string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"";
    scroll.documentView = details; alert.accessoryView = scroll;
    _protocolAlerts[requestID] = alert;
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        [self->_protocolAlerts removeObjectForKey:requestID];
        if (![bridge.sessionID isEqual:sessionID]) return;
        [bridge answerToolRequest:requestID response:result == NSAlertFirstButtonReturn
            ? @{@"behavior": @"allow", @"updatedInput": input}
            : @{@"behavior": @"deny", @"message": @"User declined this action."}];
    }];
}

#pragma mark - ask_via_prettyterm MCP 桥（独立弹窗，不经过 transcript）

- (NSString *)questionRequestDirectory {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".claude/prettyterm-questions"];
}

// 每 0.4s 扫一次目录。只认没处理过、且还没被 MCP 写回答案的 request 文件；
// 处理过的 id 记进内存 set，重启 App 才会重新扫到还留在磁盘上的旧请求。
- (void)pollQuestionRequests:(NSTimer *)timer {
    (void)timer;
    NSString *directory = self.questionRequestDirectory;
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
    if (entries.count == 0) return;
    for (NSString *entry in entries) {
        if (![entry hasSuffix:@".request.json"]) continue;
        NSString *requestID = [entry substringToIndex:entry.length - @".request.json".length];
        if ([_processedQuestionRequestIDs containsObject:requestID]) continue;
        NSString *responsePath = [directory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.response.json", requestID]];
        if ([NSFileManager.defaultManager fileExistsAtPath:responsePath]) continue;
        NSString *requestPath = [directory stringByAppendingPathComponent:entry];
        NSData *data = [NSData dataWithContentsOfFile:requestPath];
        id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *payload = [object isKindOfClass:NSDictionary.class] ? object : nil;
        NSArray *questions = [payload[@"questions"] isKindOfClass:NSArray.class] ? payload[@"questions"] : nil;
        if (questions.count == 0) continue; // 极端情况下文件还没写完整；下一轮轮询再看
        [_processedQuestionRequestIDs addObject:requestID];
        [_pendingQuestionRequests addObject:@{ @"id": requestID, @"questions": questions }];
    }
    [self presentNextQuestionRequestIfIdle];
}

- (void)presentNextQuestionRequestIfIdle {
    if (_questionPanel.visible) return;
    if (_pendingQuestionRequests.count == 0) return;
    NSDictionary *next = _pendingQuestionRequests.firstObject;
    [_pendingQuestionRequests removeObjectAtIndex:0];
    [self presentQuestionRequest:next];
}

- (void)buildQuestionPanelIfNeeded {
    if (_questionPanel) return;
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow |
        NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskFullSizeContentView;
    _questionPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 560)
                                                  styleMask:style
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    _questionPanel.title = PTL(@"Claude 有个问题", @"Claude has a question");
    _questionPanel.level = NSFloatingWindowLevel;
    _questionPanel.floatingPanel = YES;
    _questionPanel.hidesOnDeactivate = NO;
    _questionPanel.becomesKeyOnlyIfNeeded = NO;
    _questionPanel.releasedWhenClosed = NO;
    _questionPanel.titlebarAppearsTransparent = YES;
    _questionPanel.titleVisibility = NSWindowTitleHidden;
    _questionPanel.movableByWindowBackground = YES;
    _questionPanel.opaque = NO;
    _questionPanel.backgroundColor = NSColor.clearColor;
    _questionPanel.hasShadow = YES;
    _questionPanel.minSize = NSMakeSize(420, 360);
    _questionPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    [_questionPanel standardWindowButton:NSWindowCloseButton].hidden = YES;
    [_questionPanel standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [_questionPanel standardWindowButton:NSWindowZoomButton].hidden = YES;

    PTAppearanceSurfaceView *surface = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    surface.surfaceStyle = PTAppearanceSurfaceStyleCard;
    surface.wantsLayer = YES;
    surface.layer.cornerRadius = 24;
    surface.layer.borderWidth = 0.8;
    surface.layer.masksToBounds = YES;
    _questionPanel.contentView = surface;

    NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:header];

    PTAppearanceSurfaceView *mark = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    mark.surfaceStyle = PTAppearanceSurfaceStyleChip;
    mark.wantsLayer = YES;
    mark.layer.cornerRadius = 13;
    NSTextField *markLabel = [self label:@"✦" size:17 weight:NSFontWeightBold color:PTThemeColor(PTThemeRoleAccent)];
    markLabel.alignment = NSTextAlignmentCenter;
    [mark addSubview:markLabel];
    [header addSubview:mark];

    NSTextField *title = [self label:PTL(@"Claude 有个问题", @"Claude has a question")
        size:15 weight:NSFontWeightSemibold color:NSColor.labelColor];
    [header addSubview:title];
    NSTextField *subtitle = [self label:PTL(@"来自 Claude Code", @"From Claude Code")
        size:10.5 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [header addSubview:subtitle];

    PTAnimatedButton *closeButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.title = @"×";
    closeButton.font = [NSFont systemFontOfSize:18 weight:NSFontWeightMedium];
    [closeButton applyTone:PTButtonToneQuiet];
    closeButton.cornerRadius = PTRadiusDefault;
    closeButton.target = self;
    closeButton.action = @selector(closeQuestionPanel:);
    closeButton.toolTip = PTL(@"关闭", @"Close");
    [header addSubview:closeButton];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.scrollerStyle = NSScrollerStyleOverlay;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    [surface addSubview:scroll];

    _questionPanelStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _questionPanelStack.translatesAutoresizingMaskIntoConstraints = NO;
    _questionPanelStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _questionPanelStack.alignment = NSLayoutAttributeLeading;
    _questionPanelStack.spacing = 18;
    _questionPanelStack.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);

    PTFlippedView *document = [[PTFlippedView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:_questionPanelStack];
    scroll.documentView = document;

    _questionPanelStatusLabel = [self label:@"" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];

    PTAnimatedButton *submitButton = PTButtonWithTone(PTL(@"提交回答   ↗", @"Submit answers   ↗"),
        PTButtonTonePrimary, self, @selector(submitQuestionPanel:));
    submitButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    submitButton.cornerRadius = PTRadiusDefault;
    submitButton.keyEquivalent = @"\r";
    [submitButton.widthAnchor constraintGreaterThanOrEqualToConstant:132].active = YES;
    [submitButton.heightAnchor constraintEqualToConstant:42].active = YES;

    NSStackView *footer = [[NSStackView alloc] initWithFrame:NSZeroRect];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.distribution = NSStackViewDistributionEqualSpacing;
    footer.edgeInsets = NSEdgeInsetsMake(11, 20, 18, 20);
    [footer addArrangedSubview:_questionPanelStatusLabel];
    [footer addArrangedSubview:submitButton];
    [surface addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:surface.topAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-16],
        [header.heightAnchor constraintEqualToConstant:58],
        [mark.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [mark.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [mark.widthAnchor constraintEqualToConstant:42],
        [mark.heightAnchor constraintEqualToConstant:42],
        [markLabel.centerXAnchor constraintEqualToAnchor:mark.centerXAnchor],
        [markLabel.centerYAnchor constraintEqualToAnchor:mark.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:mark.trailingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:mark.topAnchor constant:3],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3],
        [closeButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [closeButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [closeButton.widthAnchor constraintEqualToConstant:32],
        [closeButton.heightAnchor constraintEqualToConstant:32],

        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:2],
        [scroll.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor],

        [document.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
        [_questionPanelStack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [_questionPanelStack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [_questionPanelStack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [_questionPanelStack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]
    ]];
}

- (void)closeQuestionPanel:(id)sender {
    if (_protocolQuestions[_questionPanelRequestID]) {
        [self writeQuestionResponseForRequestID:_questionPanelRequestID answers:@{}];
        return;
    }
    (void)sender;
    [_questionPanel orderOut:nil];
}

- (NSButton *)questionOptionButtonWithLabel:(NSString *)label
                                 description:(NSString *)description
                                       index:(NSInteger)index {
    PTQuestionOptionButton *button = [[PTQuestionOptionButton alloc]
        initWithLabel:label description:description index:index];
    button.target = self;
    button.action = @selector(toggleQuestionOption:);
    button.state = NSControlStateValueOff;
    return button;
}

// 每题一个 view：标题 + 纵向自绘选项 + 一个无原生边框的补充输入区。
// 结构信息（question 文本、multiSelect、按钮、自定义输入框）存进
// _questionPanelBlocks，点提交时按顺序读出来拼答案。
- (NSView *)buildQuestionBlockForQuestion:(NSDictionary *)question {
    NSString *questionText = [question[@"question"] isKindOfClass:NSString.class] ? question[@"question"] : @"";
    NSString *header = [question[@"header"] isKindOfClass:NSString.class] ? question[@"header"] : @"";
    BOOL multiSelect = [question[@"multiSelect"] boolValue];
    NSArray *options = [question[@"options"] isKindOfClass:NSArray.class] ? question[@"options"] : @[];

    NSStackView *block = [[NSStackView alloc] initWithFrame:NSZeroRect];
    block.translatesAutoresizingMaskIntoConstraints = NO;
    block.orientation = NSUserInterfaceLayoutOrientationVertical;
    block.alignment = NSLayoutAttributeLeading;
    block.spacing = 10;

    NSStackView *metaRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    metaRow.translatesAutoresizingMaskIntoConstraints = NO;
    metaRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    metaRow.alignment = NSLayoutAttributeCenterY;
    metaRow.spacing = 8;
    if (header.length > 0) {
        NSTextField *headerLabel = [self label:header size:10 weight:NSFontWeightBold color:PTThemeColor(PTThemeRoleMuted)];
        headerLabel.alignment = NSTextAlignmentCenter;
        PTAppearanceSurfaceView *headerChip = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        headerChip.translatesAutoresizingMaskIntoConstraints = NO;
        headerChip.surfaceStyle = PTAppearanceSurfaceStyleChip;
        headerChip.wantsLayer = YES;
        headerChip.layer.cornerRadius = 7;
        [headerChip addSubview:headerLabel];
        [NSLayoutConstraint activateConstraints:@[
            [headerLabel.topAnchor constraintEqualToAnchor:headerChip.topAnchor constant:3],
            [headerLabel.bottomAnchor constraintEqualToAnchor:headerChip.bottomAnchor constant:-3],
            [headerLabel.leadingAnchor constraintEqualToAnchor:headerChip.leadingAnchor constant:8],
            [headerLabel.trailingAnchor constraintEqualToAnchor:headerChip.trailingAnchor constant:-8]
        ]];
        [metaRow addArrangedSubview:headerChip];
    }
    NSTextField *modeLabel = [self label:multiSelect
        ? PTL(@"可多选", @"Choose any") : PTL(@"单选", @"Choose one")
        size:10.5 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [metaRow addArrangedSubview:modeLabel];
    [block addArrangedSubview:metaRow];

    NSTextField *questionLabel = [self label:questionText size:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    questionLabel.lineBreakMode = NSLineBreakByWordWrapping;
    questionLabel.maximumNumberOfLines = 0;
    [block addArrangedSubview:questionLabel];
    [questionLabel.widthAnchor constraintLessThanOrEqualToConstant:400].active = YES;

    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    NSInteger optionIndex = 0;
    for (NSDictionary *option in options) {
        if (![option isKindOfClass:NSDictionary.class]) continue;
        NSString *label = [option[@"label"] isKindOfClass:NSString.class] ? option[@"label"] : @"";
        if (label.length == 0) continue;
        NSString *description = [option[@"description"] isKindOfClass:NSString.class] ? option[@"description"] : @"";
        NSButton *button = [self questionOptionButtonWithLabel:label description:description index:optionIndex++];
        [block addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:block.widthAnchor].active = YES;
        [buttons addObject:button];
    }

    NSTextField *customField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    customField.translatesAutoresizingMaskIntoConstraints = NO;
    customField.placeholderString = PTL(@"没有符合的选项？在这里说明", @"None of these fit? Say what you want here");
    customField.font = [NSFont systemFontOfSize:13];
    customField.bordered = NO;
    customField.bezeled = NO;
    customField.drawsBackground = NO;
    customField.focusRingType = NSFocusRingTypeNone;

    PTAppearanceSurfaceView *inputSurface = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    inputSurface.translatesAutoresizingMaskIntoConstraints = NO;
    inputSurface.surfaceStyle = PTAppearanceSurfaceStyleChip;
    inputSurface.wantsLayer = YES;
    inputSurface.layer.cornerRadius = 14;
    inputSurface.layer.borderWidth = 0.7;
    NSTextField *plus = [self label:@"＋" size:15 weight:NSFontWeightMedium color:PTThemeColor(PTThemeRoleMuted)];
    NSTextField *customLabel = [self label:PTL(@"补充说明", @"Add a note")
        size:11.5 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [inputSurface addSubview:plus];
    [inputSurface addSubview:customLabel];
    [inputSurface addSubview:customField];
    [NSLayoutConstraint activateConstraints:@[
        [inputSurface.heightAnchor constraintEqualToConstant:46],
        [plus.leadingAnchor constraintEqualToAnchor:inputSurface.leadingAnchor constant:13],
        [plus.centerYAnchor constraintEqualToAnchor:inputSurface.centerYAnchor],
        [customLabel.leadingAnchor constraintEqualToAnchor:plus.trailingAnchor constant:6],
        [customLabel.centerYAnchor constraintEqualToAnchor:inputSurface.centerYAnchor],
        [customField.leadingAnchor constraintEqualToAnchor:customLabel.trailingAnchor constant:10],
        [customField.trailingAnchor constraintEqualToAnchor:inputSurface.trailingAnchor constant:-13],
        [customField.centerYAnchor constraintEqualToAnchor:inputSurface.centerYAnchor]
    ]];
    [block addArrangedSubview:inputSurface];
    [inputSurface.widthAnchor constraintEqualToAnchor:block.widthAnchor].active = YES;

    [_questionPanelBlocks addObject:@{
        @"question": questionText,
        @"multiSelect": @(multiSelect),
        @"buttons": buttons,
        @"customField": customField
    }];

    PTAppearanceSurfaceView *card = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.surfaceStyle = PTAppearanceSurfaceStyleCard;
    card.wantsLayer = YES;
    card.layer.cornerRadius = 18;
    card.layer.borderWidth = 0.8;
    [card addSubview:block];
    [NSLayoutConstraint activateConstraints:@[
        [block.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [block.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [block.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [block.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14]
    ]];
    return card;
}

- (void)toggleQuestionOption:(NSButton *)sender {
    NSStackView *block = nil;
    for (NSView *view = sender.superview; view; view = view.superview) {
        if ([view isKindOfClass:NSStackView.class] && view != _questionPanelStack) { block = (NSStackView *)view; break; }
    }
    if (!block) return;
    NSDictionary *info = nil;
    for (NSDictionary *candidate in _questionPanelBlocks) {
        if ([candidate[@"buttons"] containsObject:sender]) { info = candidate; break; }
    }
    if (!info || [info[@"multiSelect"] boolValue]) return;
    // 单选：点了这个就把同一题里其它按钮的选中态清掉。
    for (NSButton *button in info[@"buttons"]) {
        if (button != sender) button.state = NSControlStateValueOff;
    }
}

- (void)presentQuestionRequest:(NSDictionary *)request {
    [self buildQuestionPanelIfNeeded];
    _questionPanelRequestID = request[@"id"];
    _questionPanelStatusLabel.stringValue = @"";
    for (NSView *view in _questionPanelStack.arrangedSubviews.copy) {
        [view removeFromSuperview];
    }
    _questionPanelBlocks = [NSMutableArray array];
    NSArray *questions = request[@"questions"] ?: @[];
    for (NSDictionary *question in questions) {
        if (![question isKindOfClass:NSDictionary.class]) continue;
        NSView *card = [self buildQuestionBlockForQuestion:question];
        [_questionPanelStack addArrangedSubview:card];
        [card.widthAnchor constraintEqualToAnchor:_questionPanelStack.widthAnchor constant:-36].active = YES;
    }
    [_questionPanel center];
    _questionPanel.alphaValue = 0;
    [_questionPanel orderFrontRegardless];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        _questionPanel.animator.alphaValue = 1;
    } completionHandler:nil];
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        CABasicAnimation *arrival = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        arrival.fromValue = @0.975;
        arrival.toValue = @1.0;
        arrival.duration = 0.26;
        arrival.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_questionPanel.contentView.layer addAnimation:arrival forKey:@"question-arrival"];
    }
}

- (void)submitQuestionPanel:(id)sender {
    (void)sender;
    NSMutableDictionary<NSString *, NSString *> *answers = [NSMutableDictionary dictionary];
    for (NSDictionary *info in _questionPanelBlocks) {
        NSString *questionText = info[@"question"];
        NSTextField *customField = info[@"customField"];
        NSString *customValue = [customField.stringValue stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *answer = customValue;
        if (answer.length == 0) {
            NSMutableArray<NSString *> *selected = [NSMutableArray array];
            for (NSButton *button in info[@"buttons"]) {
                if (button.state == NSControlStateValueOn) [selected addObject:button.identifier];
            }
            answer = [selected componentsJoinedByString:@"、"];
        }
        if (answer.length > 0) answers[questionText] = answer;
    }
    if (answers.count == 0) {
        _questionPanelStatusLabel.stringValue = PTL(@"尚未填写回答", @"No answer entered");
        return;
    }
    [self writeQuestionResponseForRequestID:_questionPanelRequestID answers:answers];
}

- (void)writeQuestionResponseForRequestID:(NSString *)requestID answers:(NSDictionary<NSString *, NSString *> *)answers {
    NSDictionary *protocol = _protocolQuestions[requestID];
    if (protocol) {
        NSMutableDictionary *input = [protocol[@"input"] mutableCopy];
        input[@"answers"] = answers;
        [protocol[@"bridge"] answerToolRequest:requestID response:answers.count
            ? @{@"behavior": @"allow", @"updatedInput": input}
            : @{@"behavior": @"deny", @"message": @"User dismissed the question."}];
        [_protocolQuestions removeObjectForKey:requestID];
        NSIndexSet *answeredRequests = [_pendingQuestionRequests indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
            (void)index; (void)stop; return [item[@"id"] isEqual:requestID];
        }];
        [_pendingQuestionRequests removeObjectsAtIndexes:answeredRequests];
        if ([_questionPanelRequestID isEqual:requestID]) {
            [_questionPanel orderOut:nil];
            _questionPanelRequestID = nil;
        }
        [self presentNextQuestionRequestIfIdle];
        return;
    }
    NSString *directory = self.questionRequestDirectory;
    NSString *responsePath = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.response.json", requestID]];
    NSString *tmpPath = [responsePath stringByAppendingPathExtension:@"tmp"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"answers": answers } options:0 error:nil];
    NSError *error = nil;
    BOOL wrote = data && [data writeToFile:tmpPath options:NSDataWritingAtomic error:&error];
    if (wrote) wrote = [NSFileManager.defaultManager moveItemAtPath:tmpPath toPath:responsePath error:&error];
    if (!wrote) {
        _questionPanelStatusLabel.stringValue = [NSString stringWithFormat:
            PTL(@"写回答案失败：%@", @"Failed to write the answer: %@"), error.localizedDescription ?: @"未知错误"];
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.16;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        _questionPanel.animator.alphaValue = 0;
    } completionHandler:^{
        [_questionPanel orderOut:nil];
        _questionPanel.alphaValue = 1;
        [self presentNextQuestionRequestIfIdle];
    }];
}

#pragma mark - LobeHub Frontend Host

static NSString *PTLobeFileLanguageForExtension(NSString *ext) {
    NSString *lower = ext.lowercaseString;
    if (lower.length == 0) return @"text";
    NSDictionary<NSString *, NSString *> *map = @{
        @"m": @"objective-c", @"mm": @"objective-c", @"h": @"c", @"hpp": @"cpp",
        @"c": @"c", @"cpp": @"cpp", @"cc": @"cpp", @"ts": @"typescript",
        @"tsx": @"tsx", @"js": @"javascript", @"jsx": @"jsx", @"mjs": @"javascript",
        @"py": @"python", @"swift": @"swift", @"json": @"json", @"jsonl": @"json",
        @"yml": @"yaml", @"yaml": @"yaml", @"md": @"markdown", @"markdown": @"markdown",
        @"sh": @"bash", @"zsh": @"bash", @"bash": @"bash", @"css": @"css",
        @"scss": @"scss", @"html": @"html", @"xml": @"xml", @"sql": @"sql",
        @"rs": @"rust", @"go": @"go", @"rb": @"ruby", @"java": @"java",
        @"kt": @"kotlin", @"toml": @"toml", @"tex": @"latex"
    };
    return map[lower] ?: lower;
}

static NSArray<NSDictionary *> *PTLobeSerializedFileTreeChildren(NSArray<NSDictionary *> *children) {
    NSMutableArray<NSDictionary *> *serialized = [NSMutableArray arrayWithCapacity:children.count];
    for (NSDictionary *item in children ?: @[]) {
        NSURL *url = [item[@"url"] isKindOfClass:NSURL.class] ? item[@"url"] : nil;
        NSString *path = url.path ?: ([item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : @"");
        if (path.length == 0) continue;
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : path.lastPathComponent;
        BOOL isDirectory = item[@"directory"] ? [item[@"directory"] boolValue] : [item[@"isDirectory"] boolValue];
        [serialized addObject:@{
            @"name": name ?: @"",
            @"path": path,
            @"isDirectory": @(isDirectory)
        }];
    }
    return serialized;
}

static NSDictionary * _Nullable PTLobeSerializedFilePreviewPayload(NSDictionary * _Nullable raw, NSURL *url) {
    if (!raw) return nil;
    NSString *resolvedPath = [raw[@"path"] isKindOfClass:NSString.class] ? raw[@"path"] : (url.path ?: @"");
    NSString *name = [raw[@"title"] isKindOfClass:NSString.class]
        ? raw[@"title"]
        : ([raw[@"name"] isKindOfClass:NSString.class] ? raw[@"name"] : resolvedPath.lastPathComponent);
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"kind"] = [raw[@"kind"] isKindOfClass:NSString.class] ? raw[@"kind"] : @"source";
    out[@"path"] = resolvedPath ?: @"";
    out[@"name"] = name ?: @"";
    out[@"language"] = PTLobeFileLanguageForExtension(url.pathExtension ?: resolvedPath.pathExtension);
    if ([raw[@"text"] isKindOfClass:NSString.class]) out[@"content"] = raw[@"text"];
    if ([raw[@"content"] isKindOfClass:NSString.class]) out[@"content"] = raw[@"content"];
    if ([raw[@"dataURL"] isKindOfClass:NSString.class]) out[@"dataUrl"] = raw[@"dataURL"];
    if ([raw[@"dataUrl"] isKindOfClass:NSString.class]) out[@"dataUrl"] = raw[@"dataUrl"];
    if ([raw[@"html"] isKindOfClass:NSString.class]) out[@"html"] = raw[@"html"];
    return [out copy];
}

static NSArray<NSDictionary *> *PTLobeSanitizeTurnEdits(NSArray<NSDictionary *> *events) {
    NSMutableArray<NSDictionary *> *clean = [NSMutableArray arrayWithCapacity:events.count];
    for (NSDictionary *ev in events ?: @[]) {
        [clean addObject:@{
            @"filePath": [ev[@"filePath"] isKindOfClass:NSString.class] ? ev[@"filePath"] : @"",
            @"oldText": [ev[@"oldText"] isKindOfClass:NSString.class] ? ev[@"oldText"] : @"",
            @"newText": [ev[@"newText"] isKindOfClass:NSString.class] ? ev[@"newText"] : @"",
            @"toolName": [ev[@"toolName"] isKindOfClass:NSString.class] ? ev[@"toolName"] : @""
        }];
    }
    return clean;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context == (__bridge void *)self && [keyPath isEqualToString:@"effectiveAppearance"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self syncLobeFrontendAppearanceAndLanguage];
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (NSString *)resolvedLobeAppearance {
    return PTFrontendBridgeAppearanceString(NSApp.appearance ?: _window.effectiveAppearance ?: NSApp.effectiveAppearance);
}

- (void)attachMainFrontend {
    NSString *appearance = [self resolvedLobeAppearance];
    NSString *language = PTInterfaceLanguageCode();
    if (!_lobeMainWebView) {
        _lobeMainBridge = [[PTFrontendBridge alloc] initWithSurface:@"main" delegate:self];
        WKWebViewConfiguration *mainConfig = [[WKWebViewConfiguration alloc] init];
        [_lobeMainBridge configureWebViewConfiguration:mainConfig
                                     initialAppearance:appearance
                                       initialLanguage:language];
        _lobeMainWebView = [[PTBridgeDropWebView alloc] initWithFrame:NSZeroRect configuration:mainConfig];
        _lobeMainWebView.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(macOS 12.0, *)) _lobeMainWebView.underPageBackgroundColor = NSColor.clearColor;
        __weak typeof(self) weakSelf = self;
        _lobeMainWebView.fileDropHandler = ^BOOL(NSArray<NSURL *> *urls) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return NO;
            BOOL added = [strongSelf addComposerAttachmentURLs:urls floating:NO];
            [strongSelf pushFrontendWorkspace];
            return added;
        };
        [_lobeMainBridge attachWebView:_lobeMainWebView];
        NSView *windowContent = _window.contentView;
        [windowContent addSubview:_lobeMainWebView];
        [NSLayoutConstraint activateConstraints:@[
            [_lobeMainWebView.topAnchor constraintEqualToAnchor:windowContent.topAnchor],
            [_lobeMainWebView.leadingAnchor constraintEqualToAnchor:windowContent.leadingAnchor],
            [_lobeMainWebView.trailingAnchor constraintEqualToAnchor:windowContent.trailingAnchor],
            [_lobeMainWebView.bottomAnchor constraintEqualToAnchor:windowContent.bottomAnchor]
        ]];
        [_lobeMainBridge loadBundledFrontendFromResourceURL:nil error:nil];
    }
}

- (void)positionLobeFloatingPanelNearMainWindow {
    if (!_lobeFloatingPanel) return;
    NSScreen *screen = _window.screen ?: NSScreen.mainScreen;
    NSRect visible = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1440, 900);
    NSRect mainFrame = _window.frame;
    NSRect panelFrame = _lobeFloatingPanel.frame;
    panelFrame.origin.x = MIN(NSMaxX(mainFrame) - panelFrame.size.width - 22.0,
                              NSMaxX(visible) - panelFrame.size.width - 12.0);
    panelFrame.origin.x = MAX(panelFrame.origin.x, NSMinX(visible) + 12.0);
    panelFrame.origin.y = MIN(NSMaxY(mainFrame) - panelFrame.size.height - 22.0,
                              NSMaxY(visible) - panelFrame.size.height - 12.0);
    panelFrame.origin.y = MAX(panelFrame.origin.y, NSMinY(visible) + 12.0);
    [_lobeFloatingPanel setFrame:panelFrame display:NO];
}

- (void)buildLobeFloatingPanelIfNeeded {
    if (_lobeFloatingPanel) return;
    NSString *appearance = [self resolvedLobeAppearance];
    NSString *language = PTInterfaceLanguageCode();
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView |
        NSWindowStyleMaskNonactivatingPanel;
    _lobeFloatingPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 500.0, 660.0)
                                                    styleMask:style
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    _lobeFloatingPanel.title = PTL(@"PrettyTerm 悬浮对话", @"PrettyTerm Floating Conversation");
    _lobeFloatingPanel.titleVisibility = NSWindowTitleHidden;
    _lobeFloatingPanel.titlebarAppearsTransparent = YES;
    _lobeFloatingPanel.floatingPanel = YES;
    _lobeFloatingPanel.level = NSFloatingWindowLevel;
    _lobeFloatingPanel.hidesOnDeactivate = NO;
    _lobeFloatingPanel.becomesKeyOnlyIfNeeded = NO;
    _lobeFloatingPanel.releasedWhenClosed = NO;
    _lobeFloatingPanel.minSize = NSMakeSize(380.0, 420.0);
    _lobeFloatingPanel.backgroundColor = PTThemeColor(PTThemeRoleCanvas);
    _lobeFloatingPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    _lobeFloatingPanel.delegate = self;
    [_lobeFloatingPanel standardWindowButton:NSWindowCloseButton].hidden = YES;
    [_lobeFloatingPanel standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [_lobeFloatingPanel standardWindowButton:NSWindowZoomButton].hidden = YES;

    _lobeFloatingBridge = [[PTFrontendBridge alloc] initWithSurface:@"floating" delegate:self];
    WKWebViewConfiguration *floatConfig = [[WKWebViewConfiguration alloc] init];
    [_lobeFloatingBridge configureWebViewConfiguration:floatConfig
                                     initialAppearance:appearance
                                       initialLanguage:language];
    _lobeFloatingWebView = [[PTBridgeDropWebView alloc] initWithFrame:NSZeroRect configuration:floatConfig];
    _lobeFloatingWebView.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 12.0, *)) _lobeFloatingWebView.underPageBackgroundColor = NSColor.clearColor;
    __weak typeof(self) weakSelf = self;
    _lobeFloatingWebView.fileDropHandler = ^BOOL(NSArray<NSURL *> *urls) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return NO;
        BOOL added = [strongSelf addComposerAttachmentURLs:urls floating:YES];
        [strongSelf pushFrontendWorkspace];
        return added;
    };
    [_lobeFloatingBridge attachWebView:_lobeFloatingWebView];
    NSView *panelContent = _lobeFloatingPanel.contentView;
    [panelContent addSubview:_lobeFloatingWebView];
    [NSLayoutConstraint activateConstraints:@[
        [_lobeFloatingWebView.topAnchor constraintEqualToAnchor:panelContent.topAnchor],
        [_lobeFloatingWebView.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor],
        [_lobeFloatingWebView.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor],
        [_lobeFloatingWebView.bottomAnchor constraintEqualToAnchor:panelContent.bottomAnchor]
    ]];
    [_lobeFloatingBridge loadBundledFrontendFromResourceURL:nil error:nil];
}

- (NSDictionary *)frontendWindowStateSnapshotForSurface:(NSString *)surface {
    BOOL isFloating = [surface isEqual:@"floating"];
    NSString *targetSessionID = isFloating ? (_floatingSessionID ?: @"") : (_selectedSession.sessionID ?: @"");
    PTClaudeBridge *bridge = targetSessionID.length > 0 ? [self bridgeForSessionID:targetSessionID] : nil;

    NSMutableArray *models = [NSMutableArray array];
    for (NSArray<NSString *> *entry in [self composerModelEntries]) {
        if (entry.count < 3) continue;
        [models addObject:@{
            @"label": entry[0],
            @"shortLabel": entry[1],
            @"id": entry[2]
        }];
    }
    NSArray *permissionModes = @[
        @{ @"id": @"plan", @"label": @"Plan", @"wireMode": @"plan" },
        @{ @"id": @"auto", @"label": @"Auto", @"wireMode": @"auto" },
        @{ @"id": @"bypass", @"label": @"Bypass", @"wireMode": @"bypassPermissions" },
        @{ @"id": @"default", @"label": @"Default", @"wireMode": @"default" },
        @{ @"id": @"acceptEdits", @"label": @"Accept edits", @"wireMode": @"acceptEdits" }
    ];
    NSString *selectedModel = [self composerModelForSessionID:targetSessionID] ?: @"";
    NSString *selectedEffort = [self composerEffortForSessionID:targetSessionID] ?: _selectedComposerEffort ?: @"";
    NSString *selectedPermissionMode = bridge.permissionMode ?: @"bypassPermissions";

    NSString *shortVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
    NSString *bundleVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"8";
    NSString *defaultCwd = _homeProjectPath.length > 0
        ? _homeProjectPath
        : (_selectedSession.cwd.length > 0 ? _selectedSession.cwd : NSHomeDirectory());
    NSString *hostName = NSHost.currentHost.localizedName ?: NSProcessInfo.processInfo.hostName ?: @"Mac";

    return @{
        @"appearance": [self resolvedLobeAppearance],
        @"language": PTInterfaceLanguageCode(),
        @"surface": surface ?: @"main",
        @"version": [NSString stringWithFormat:@"%@ (%@)", shortVersion, bundleVersion],
        @"defaultCwd": defaultCwd ?: NSHomeDirectory(),
        @"hostName": hostName,
        @"platformInfo": @"macOS · arm64",
        @"statusBanner": (isFloating ? _floatingStatusText : _statusText) ?: @"",
        @"usage": @{
            @"available": @(_planUsageAvailable),
            @"error": _planUsageError ?: @"",
            @"fiveHourPercent": @(_fiveHourPercent),
            @"fiveHourResetText": PTCountdownDescription(_fiveHourResetAt, NSDate.date) ?: @"",
            @"sevenDayPercent": @(_sevenDayPercent),
            @"sevenDayResetText": PTCountdownDescription(_sevenDayResetAt, NSDate.date) ?: @""
        },
        @"claudeSettings": @{
            @"availableModels": models,
            @"effortLevels": [self composerEffortLevels] ?: @[],
            @"permissionModes": permissionModes,
            @"sessionId": targetSessionID,
            @"selectedModel": selectedModel,
            @"selectedEffort": selectedEffort,
            @"selectedPermissionMode": selectedPermissionMode
        }
    };
}

- (NSArray<NSDictionary *> *)frontendSerializedImages:(NSArray<NSDictionary *> *)images {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:images.count];
    for (NSDictionary *item in images ?: @[]) {
        NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : @"";
        NSString *dataURL = item[@"thumbnail"] ?: @"";
        [out addObject:@{
            @"id": path,
            @"path": path,
            @"name": path.lastPathComponent ?: @"image.png",
            @"temporary": @([item[@"temporary"] boolValue]),
            @"dataUrl": dataURL
        }];
    }
    return out;
}

- (NSDictionary *)frontendWorkspaceSnapshotForSurface:(NSString *)surface {
    BOOL isFloating = [surface isEqual:@"floating"];
    NSMutableArray<NSDictionary *> *tabItems = [NSMutableArray arrayWithCapacity:isFloating ? 0 : _workspaceTabs.count];
    for (PTWorkspaceTab *tab in (isFloating ? @[] : _workspaceTabs)) {
        PTSessionInfo *session = tab.sessionID.length > 0 ? [self sessionWithID:tab.sessionID] : nil;
        BOOL responding = tab.bridge.responding ||
            (tab.sessionID.length > 0 && _awaitingClaudeBaselineBySessionID[tab.sessionID] != nil);
        [tabItems addObject:@{
            @"id": tab.identifier ?: @"",
            @"sessionId": tab.sessionID ?: @"",
            @"title": session.title.length > 0 ? session.title : PTL(@"新标签", @"New tab"),
            @"cwd": session.cwd ?: @"",
            @"status": tab.status ?: @"",
            @"connecting": @(tab.connecting),
            @"running": @(tab.bridge.running),
            @"responding": @(responding),
            @"activeToolPageKind": tab.activeToolPageKind ?: @"",
            @"fileTreeRootPath": tab.fileTreeRootPath ?: @"",
            @"fileToolPageOpen": @(tab.fileToolPageOpen),
            @"reviewToolPageOpen": @(tab.reviewToolPageOpen),
            @"panelExpanded": @(tab.panelExpanded),
            @"overviewExpanded": @(tab.overviewExpanded)
        }];
    }
    return @{
        @"activeTabId": isFloating ? @"" : (_activeWorkspaceTab.identifier ?: @""),
        @"selectedSessionId": _selectedSession.sessionID ?: @"",
        @"floatingSessionId": _floatingSessionID ?: @"",
        @"floatingVisible": @(_lobeFloatingPanel.visible),
        @"tabs": tabItems
    };
}

- (NSDictionary *)frontendComposerSnapshotForSurface:(NSString *)surface {
    BOOL floating = [surface isEqual:@"floating"];
    PTWorkspaceTab *tab = _activeWorkspaceTab;
    return @{
        @"id": floating ? (_floatingSessionID ?: @"") : (tab.identifier ?: @""),
        @"sessionId": floating ? (_floatingSessionID ?: @"") : (tab.sessionID ?: @""),
        @"draft": floating ? (_floatingDraft ?: @"") : (tab.draft ?: @""),
        @"pendingImages": [self frontendSerializedImages:floating ? _floatingPendingImages : tab.pendingImages],
        @"pendingFiles": [(floating ? _floatingPendingFiles : tab.pendingFiles) copy] ?: @[]
    };
}

- (NSArray<NSDictionary *> *)frontendSessionsSnapshot {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:_sessions.count];
    for (PTSessionInfo *session in _sessions ?: @[]) {
        PTClaudeBridge *bridge = [self bridgeForSessionID:session.sessionID];
        BOOL running = bridge != nil && bridge.running;
        BOOL awaiting = _awaitingClaudeBaselineBySessionID[session.sessionID] != nil;
        BOOL responding = (bridge != nil && bridge.responding) || awaiting;
        long long modifiedMs = session.modifiedAt
            ? (long long)llround(session.modifiedAt.timeIntervalSince1970 * 1000.0)
            : 0;
        [out addObject:@{
            @"sessionId": session.sessionID ?: @"",
            @"title": session.title ?: PTL(@"未命名会话", @"Untitled conversation"),
            @"cwd": session.cwd ?: @"",
            @"filePath": session.filePath ?: @"",
            @"model": session.model ?: @"",
            @"effort": session.effort ?: @"",
            @"modifiedAtMs": @(modifiedMs),
            @"projectKey": PTSessionProjectKey(session) ?: @"",
            @"projectTitle": PTSessionProjectTitle(PTSessionProjectKey(session)) ?: @"",
            @"turnCount": @(PTSessionTurnCount(session)),
            @"connected": @(running),
            @"running": @(running),
            @"responding": @(responding),
            @"awaitingReply": @(awaiting),
            @"accessedDirectories": session.accessedDirectories ?: @[],
            @"changedFiles": session.changedFiles ?: @[],
            @"tasks": session.tasks ?: @[],
            @"contextUsed": @(session.contextUsed),
            @"contextWindow": @(session.contextWindow),
            @"contextBreakdown": session.contextBreakdown ?: @[],
            @"apiCostAvailable": @(session.apiCostAvailable),
            @"apiEquivalentCostUSD": @(session.apiEquivalentCostUSD),
            @"modelUsageBreakdown": session.modelUsageBreakdown ?: @{},
            @"codeLinesAdded": @(session.codeLinesAdded),
            @"codeLinesRemoved": @(session.codeLinesRemoved)
        }];
    }
    return out;
}

- (NSDictionary *)frontendCurrentGitStateSnapshot {
    NSMutableDictionary *snapshot = [(_gitReviewShowsTranscriptEdits ? _turnReviewSnapshot : _lobeGitStateSnapshot) mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!snapshot[@"reviewMode"]) snapshot[@"reviewMode"] = _gitReviewShowsTranscriptEdits ? @"turn" : @"git";
    snapshot[@"directories"] = [_gitDirectoryPaths copy] ?: @[];
    snapshot[@"observedDirectory"] = _gitObservedDirectory ?: @"";
    if (!snapshot[@"files"]) snapshot[@"files"] = @[];
    snapshot[@"actionInFlight"] = @(_gitActionInFlight);
    return [snapshot copy];
}

- (void)pushFrontendWindowState {
    [_lobeMainBridge pushWindowState:[self frontendWindowStateSnapshotForSurface:@"main"]];
    if (_lobeFloatingBridge) {
        [_lobeFloatingBridge pushWindowState:[self frontendWindowStateSnapshotForSurface:@"floating"]];
    }
}

- (void)pushFrontendComposer {
    if (_lobeMainBridge.frontendReady) {
        [_lobeMainBridge pushStateMethod:@"setPrettyTermComposer"
                                payload:[self frontendComposerSnapshotForSurface:@"main"]];
    }
    if (_lobeFloatingBridge.frontendReady && _lobeFloatingPanel.visible) {
        [_lobeFloatingBridge pushStateMethod:@"setPrettyTermComposer"
                                    payload:[self frontendComposerSnapshotForSurface:@"floating"]];
    }
}

- (void)pushFrontendWorkspaceState {
    if (_lobeMainBridge.frontendReady) {
        [_lobeMainBridge pushStateMethod:@"setPrettyTermWorkspace"
                                payload:[self frontendWorkspaceSnapshotForSurface:@"main"]];
        [self pushFrontendClaudeTasksTo:_lobeMainBridge sessionID:_selectedSession.sessionID];
    }
    if (_lobeFloatingBridge.frontendReady && _lobeFloatingPanel.visible) {
        [_lobeFloatingBridge pushStateMethod:@"setPrettyTermWorkspace"
                                    payload:[self frontendWorkspaceSnapshotForSurface:@"floating"]];
        [self pushFrontendClaudeTasksTo:_lobeFloatingBridge sessionID:_floatingSessionID];
    }
}

- (void)pushFrontendClaudeTasksTo:(PTFrontendBridge *)frontend sessionID:(NSString *)sessionID {
    if (!frontend.frontendReady) return;
    NSDictionary *tasks = [self bridgeForSessionID:sessionID].tasksPayload;
    [frontend pushStateMethod:@"setPrettyTermClaudeTasks"
                       payload:tasks ?: @{@"sessionId": sessionID ?: @"", @"generation": @"",
                                          @"foreground": @[], @"background": @[]}];
}

- (void)pushFrontendWorkspace {
    [self pushFrontendWorkspaceState];
    [self pushFrontendComposer];
}

- (void)pushFrontendSessions {
    NSArray *sessions = [self frontendSessionsSnapshot];
    [_lobeMainBridge pushStateMethod:@"setPrettyTermSessions" payload:sessions];
    if (_lobeFloatingBridge.frontendReady && _lobeFloatingPanel.visible) {
        for (NSDictionary *session in sessions) {
            if (![session[@"sessionId"] isEqual:_floatingSessionID]) continue;
            [_lobeFloatingBridge pushStateMethod:@"setPrettyTermSessions" payload:@[session]];
            break;
        }
    }
}

- (void)pushFrontendGitState {
    [_lobeMainBridge pushStateMethod:@"setPrettyTermGitState"
                             payload:[self frontendCurrentGitStateSnapshot]];
}

- (void)performGitCommit:(BOOL)commit
                   push:(BOOL)push
        includeUnstaged:(BOOL)includeUnstaged
              directory:(NSString *)directory
                message:(NSString *)message {
    if (directory.length == 0 || _gitActionInFlight) {
        return;
    }
    if (commit && message.length == 0) {
        NSMutableDictionary *nextGit = [_lobeGitStateSnapshot mutableCopy] ?: [NSMutableDictionary dictionary];
        nextGit[@"actionStatus"] = PTL(@"提交信息为空", @"Commit message is empty");
        _lobeGitStateSnapshot = [nextGit copy];
        [self pushFrontendGitState];
        return;
    }
    _gitActionInFlight = YES;
    NSMutableDictionary *busyGit = [_lobeGitStateSnapshot mutableCopy] ?: [NSMutableDictionary dictionary];
    busyGit[@"actionInFlight"] = @YES;
    busyGit[@"actionStatus"] = commit ? PTL(@"正在提交…", @"Committing…") : PTL(@"正在推送…", @"Pushing…");
    _lobeGitStateSnapshot = [busyGit copy];
    [self pushFrontendGitState];
    NSString *dirCopy = [directory copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int status = 0;
        NSString *root = [PTRunGit(dirCopy, @[@"rev-parse", @"--show-toplevel"], &status)
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSMutableArray<NSString *> *outputs = [NSMutableArray array];
        if (status != 0 && root.length) [outputs addObject:root];
        if (status == 0 && commit && includeUnstaged) {
            NSString *out = PTRunGit(root, @[@"add", @"-A", @"--", @"."], &status);
            if (out.length) [outputs addObject:out];
        }
        if (status == 0 && commit) {
            NSString *out = PTRunGit(root, @[@"commit", @"-m", message], &status);
            if (out.length) [outputs addObject:out];
        }
        if (status == 0 && push) {
            NSString *out = PTRunGit(root, @[@"push"], &status);
            if (out.length) [outputs addObject:out];
        }
        NSString *combined = [[outputs componentsJoinedByString:@"\n"]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *success = commit && push
            ? PTL(@"提交并推送完成", @"Commit and push completed")
            : (commit ? PTL(@"提交完成", @"Commit completed") : PTL(@"推送完成", @"Push completed"));
        NSString *result = status == 0 ? success : (combined.length ? combined : PTL(@"Git 操作失败", @"Git operation failed"));
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_gitActionInFlight = NO;
            NSMutableDictionary *doneGit = [self->_lobeGitStateSnapshot mutableCopy] ?: [NSMutableDictionary dictionary];
            doneGit[@"actionInFlight"] = @NO;
            doneGit[@"actionStatus"] = result;
            self->_lobeGitStateSnapshot = [doneGit copy];
            self->_statusText = result;
            [self pushFrontendGitState];
            [self pushFrontendWindowState];
            if (!self->_gitReviewShowsTranscriptEdits && [dirCopy isEqual:self->_gitObservedDirectory]) {
                [self pushFrontendGitDiffForDirectory:dirCopy];
            }
        });
    });
}

- (void)pushFrontendGitDiffForDirectory:(NSString *)directory {
    _gitReviewShowsTranscriptEdits = NO;
    if (!directory.length) {
        _gitReviewQueuedDirectory = nil;
        _gitDiffGeneration++;
        _lobeGitStateSnapshot = @{
            @"reviewMode": @"git", @"files": @[], @"loading": @NO,
            @"error": PTL(@"尚未选择 Git 观察目录。", @"No Git observation directory is selected.")
        };
        [self pushFrontendGitState];
        return;
    }
    if (_gitReviewInFlightDirectory) {
        _gitReviewQueuedDirectory = [directory copy];
        if (![_gitReviewInFlightDirectory isEqual:directory]) _gitDiffGeneration++;
        return;
    }
    _gitReviewInFlightDirectory = [directory copy];
    NSMutableDictionary *loading = [_lobeGitStateSnapshot mutableCopy] ?: [NSMutableDictionary dictionary];
    if (![loading[@"observedDirectory"] isEqual:directory]) [loading removeAllObjects];
    loading[@"reviewMode"] = @"git";
    loading[@"observedDirectory"] = directory;
    loading[@"loading"] = @YES;
    _lobeGitStateSnapshot = loading;
    [self pushFrontendGitState];
    NSUInteger generation = ++_gitDiffGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary<NSString *, NSString *> *snapshot = PTGitReviewSnapshotForDirectory(directory);
        NSArray<NSDictionary *> *files = PTGitReviewStructuredFiles(snapshot ?: @{});
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_gitReviewInFlightDirectory = nil;
            if (generation == self->_gitDiffGeneration && [directory isEqual:self->_gitObservedDirectory]) {
                NSMutableDictionary *next = [self->_lobeGitStateSnapshot mutableCopy];
                next[@"observedDirectory"] = directory;
                next[@"branch"] = snapshot[@"branch"] ?: @"";
                next[@"error"] = snapshot[@"error"] ?: @"";
                next[@"files"] = files ?: @[];
                next[@"loading"] = @NO;
                self->_lobeGitStateSnapshot = next;
                if (!self->_gitReviewShowsTranscriptEdits) [self pushFrontendGitState];
            }
            NSString *queued = self->_gitReviewQueuedDirectory;
            self->_gitReviewQueuedDirectory = nil;
            if (!self->_gitReviewShowsTranscriptEdits && [queued isEqual:self->_gitObservedDirectory]) {
                [self pushFrontendGitDiffForDirectory:queued];
            }
        });
    });
}

- (void)pushFrontendDirectoryListingForPath:(NSString *)path root:(NSString *)root tabID:(NSString *)tabID {
    if (!path.length || !tabID.length) return;
    if (!_directoryReadTargets) _directoryReadTargets = [NSMutableDictionary dictionary];
    NSDictionary *target = @{@"rootPath": root ?: @"", @"tabId": tabID};
    NSMutableArray *targets = _directoryReadTargets[path];
    if (targets) {
        if (![targets containsObject:target]) [targets addObject:target];
        return;
    }
    _directoryReadTargets[path] = [NSMutableArray arrayWithObject:target];
    NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray *children = PTLobeSerializedFileTreeChildren(PTFileTreeChildren(url, &error) ?: @[]);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *receivers = [self->_directoryReadTargets[path] copy];
            [self->_directoryReadTargets removeObjectForKey:path];
            for (NSDictionary *receiver in receivers) {
                NSMutableDictionary *payload = [receiver mutableCopy];
                payload[@"path"] = path;
                payload[@"children"] = children;
                payload[@"error"] = error.localizedDescription ?: @"";
                [self->_lobeMainBridge pushStateMethod:@"setPrettyTermFileTree" payload:payload];
            }
        });
    });
}

- (void)pushFrontendFilePreviewForPath:(NSString *)path sessionID:(NSString *)sessionID tabID:(NSString *)tabID {
    if (!path.length || !tabID.length) return;
    NSURL *url = [NSURL fileURLWithPath:path];
    NSDictionary *request = @{
        @"path": path, @"sessionId": sessionID ?: @"", @"tabId": tabID,
        @"requestId": NSUUID.UUID.UUIDString
    };
    NSMutableDictionary *loading = [request mutableCopy];
    loading[@"loading"] = @YES;
    [_lobeMainBridge pushStateMethod:@"setPrettyTermFilePreview" payload:loading];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *raw = PTFilePreviewPayloadForURL(url, &error);
        NSDictionary *preview = PTLobeSerializedFilePreviewPayload(raw, url);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *result = [request mutableCopy];
            result[@"payload"] = preview ?: NSNull.null;
            result[@"error"] = error.localizedDescription ?: @"";
            [self->_lobeMainBridge pushStateMethod:@"setPrettyTermFilePreview" payload:result];
        });
    });
}

- (void)publishTerminalOutput:(NSString *)text reset:(BOOL)reset {
    if (!_terminalDrawerVisible) return;
    NSDictionary *payload = @{
        @"runId": _terminalRunID ?: @"",
        @"sequence": @(++_terminalSequence),
        @"tabId": _lobeTerminalTabID ?: @"",
        @"cwd": _lobeTerminalCwd ?: NSHomeDirectory(),
        @"command": _lobeTerminalCommand ?: @"",
        @"running": @(_lobeTerminalRunning),
        @"exitCode": _lobeTerminalExitCode ?: NSNull.null,
        @"output": text ?: @"",
        @"reset": @(reset)
    };
    [_lobeMainBridge pushStateMethod:@"setPrettyTermTerminalOutput" payload:payload];
}

- (void)syncLobeFrontendAppearanceAndLanguage {
    [self pushFrontendWindowState];
    if (_lobeFloatingPanel) {
        _lobeFloatingPanel.backgroundColor = PTThemeColor(PTThemeRoleCanvas);
    }
}

- (void)frontendBridge:(PTFrontendBridge *)bridge didRequestLanguage:(NSString *)languageCode {
    (void)bridge;
    NSString *normalized = PTFrontendBridgeNormalizeLanguage(languageCode);
    [NSUserDefaults.standardUserDefaults setObject:normalized forKey:PTInterfaceLanguageDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self syncLobeFrontendAppearanceAndLanguage];
}

- (void)frontendBridge:(PTFrontendBridge *)bridge
       didInvokeAction:(NSString *)action
               payload:(NSDictionary *)payload
                 reply:(PTFrontendActionReply)reply {
    if ([action isEqual:@"ping"]) {
        reply(@{ @"pong": @YES, @"surface": bridge.surface ?: @"main" }, nil);
        return;
    }

    if ([action isEqual:@"windowDrag"]) {
        NSString *surface = [payload[@"surface"] isKindOfClass:NSString.class] ? payload[@"surface"] : bridge.surface;
        NSWindow *targetWindow = [surface isEqual:@"floating"] ? _lobeFloatingPanel : _window;
        NSEvent *ev = NSApp.currentEvent;
        if (targetWindow && ev && ev.window == targetWindow &&
            (ev.type == NSEventTypeLeftMouseDown || ev.type == NSEventTypeLeftMouseDragged)) {
            [targetWindow performWindowDragWithEvent:ev];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"setLanguage"]) {
        NSString *lang = [payload[@"language"] isKindOfClass:NSString.class] ? payload[@"language"] : @"zh-Hans";
        [self frontendBridge:bridge didRequestLanguage:lang];
        reply(@{ @"language": PTInterfaceLanguageCode() }, nil);
        return;
    }

    if ([action isEqual:@"refreshSessions"]) {
        [self refreshClaudeUsage:nil];
        [_store refresh];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"selectSession"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        PTSessionInfo *target = [self sessionWithID:sessionID];
        if (!target) {
            reply(nil, @"Session not found");
            return;
        }
        if ([payload[@"newTab"] boolValue]) {
            PTWorkspaceTab *tab = [self createWorkspaceTab];
            tab.sessionID = target.sessionID ?: @"";
            [self activateWorkspaceTab:tab animated:NO];
        } else if (!_activeWorkspaceTab) {
            PTWorkspaceTab *tab = [self createWorkspaceTab];
            tab.sessionID = target.sessionID ?: @"";
            [self activateWorkspaceTab:tab animated:NO];
        }
            _selectedSession = target;
        _activeWorkspaceTab.sessionID = target.sessionID ?: @"";
        [self showSelectedSession];
        [self updateWorkspaceTabBar];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"newTab"]) {
        PTWorkspaceTab *tab = [self createWorkspaceTab];
        [self activateWorkspaceTab:tab animated:NO];
        reply(@{ @"tabId": tab.identifier ?: @"" }, nil);
        return;
    }

    if ([action isEqual:@"selectTab"]) {
        NSString *tabId = [payload[@"tabId"] isKindOfClass:NSString.class] ? payload[@"tabId"] : @"";
        for (PTWorkspaceTab *tab in _workspaceTabs) {
            if ([tab.identifier isEqual:tabId]) {
                [self activateWorkspaceTab:tab animated:NO];
                break;
            }
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"closeTab"]) {
        NSString *tabId = [payload[@"tabId"] isKindOfClass:NSString.class] ? payload[@"tabId"] : @"";
        [self closeWorkspaceTabWithID:tabId];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"reorderTabs"]) {
        NSArray<NSString *> *orderedIDs = [payload[@"tabIds"] isKindOfClass:NSArray.class] ? payload[@"tabIds"] : @[];
        if (orderedIDs.count > 0 && _workspaceTabs.count > 1) {
            NSMutableDictionary<NSString *, PTWorkspaceTab *> *byId = [NSMutableDictionary dictionary];
            for (PTWorkspaceTab *tab in _workspaceTabs) byId[tab.identifier ?: @""] = tab;
            NSMutableArray<PTWorkspaceTab *> *reordered = [NSMutableArray arrayWithCapacity:_workspaceTabs.count];
            for (id item in orderedIDs) {
                if (![item isKindOfClass:NSString.class]) continue;
                PTWorkspaceTab *tab = byId[item];
                if (tab && ![reordered containsObject:tab]) [reordered addObject:tab];
            }
            for (PTWorkspaceTab *tab in _workspaceTabs) {
                if (![reordered containsObject:tab]) [reordered addObject:tab];
            }
            _workspaceTabs = reordered;
            [self updateWorkspaceTabBar];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"chooseFolderForNewChat"]) {
        NSOpenPanel *panel = NSOpenPanel.openPanel;
        panel.canChooseFiles = NO;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = NO;
        [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK && panel.URL.path.length > 0) {
                self->_homeProjectPath = [panel.URL.path copy];
                reply(@{ @"path": panel.URL.path }, nil);
            } else {
                reply(@{}, nil);
            }
        }];
        return;
    }

    if ([action isEqual:@"startNewConversation"]) {
        NSString *rawCwd = [payload[@"cwd"] isKindOfClass:NSString.class] ? payload[@"cwd"] : @"";
        NSString *cwd = rawCwd.length > 0
            ? rawCwd.stringByExpandingTildeInPath.stringByStandardizingPath
            : @"";
        NSString *prompt = [payload[@"prompt"] isKindOfClass:NSString.class] ? payload[@"prompt"] : @"";
        BOOL isDir = NO;
        if (cwd.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:cwd isDirectory:&isDir] || !isDir) {
            reply(nil, PTL(@"请选择存在的项目目录", @"Please select an existing project folder"));
            return;
        }
        if (_homeStartingBridge) {
            reply(nil, PTL(@"正在创建会话，请稍候…", @"Starting conversation, please wait…"));
            return;
        }
        _homeProjectPath = [cwd copy];
        __weak typeof(self) weakSelf = self;
        if (prompt.length == 0) {
            _homeBlankSessionDirectory = [cwd copy];
            _homeStartingBridge = [self newHomeBridge];
            _homeStartingBridge.statusChanged = ^(NSString *status) { [weakSelf homeLaunchStatusChanged:status]; };
            [_homeStartingBridge startNewSessionInDirectory:_homeBlankSessionDirectory];
        } else {
            PTSessionInfo *session = [PTSessionInfo new];
            session.sessionID = NSUUID.UUID.UUIDString.lowercaseString;
            session.cwd = cwd;
            _homeStartingSessionID = session.sessionID;
            _homeStartingBridge = [self newHomeBridge];
            _homeStartingBridge.statusChanged = ^(NSString *status) { [weakSelf homeLaunchStatusChanged:status]; };
            [_homeStartingBridge startNewSession:session prompt:prompt];
        }
        [self pushFrontendWindowState];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"renameSession"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        NSString *title = [payload[@"title"] isKindOfClass:NSString.class] ? payload[@"title"] : @"";
        PTSessionInfo *session = [self sessionWithID:sessionID];
        if (!session) {
            reply(nil, @"Session not found");
            return;
        }
        [self renameSession:session toTitle:title];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"revealSessionTranscript"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        PTSessionInfo *session = [self sessionWithID:sessionID];
        if (session.filePath.length && [NSFileManager.defaultManager fileExistsAtPath:session.filePath]) {
            [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:session.filePath]]];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"openProjectFolder"]) {
        NSString *rawPath = [payload[@"path"] isKindOfClass:NSString.class] ? payload[@"path"] : @"";
        NSString *path = rawPath.length > 0 ? rawPath.stringByStandardizingPath : @"";
        if (path.length == 0 && [payload[@"sessionId"] isKindOfClass:NSString.class]) {
            path = [self sessionWithID:payload[@"sessionId"]].cwd.stringByStandardizingPath ?: @"";
        }
        BOOL isDir = NO;
        if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path isDirectory:YES]];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"openProjectsRoot"]) {
        NSString *projectsRoot = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/projects"];
        BOOL isDir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:projectsRoot isDirectory:&isDir] && isDir) {
            [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:projectsRoot isDirectory:YES]];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"revealInFinder"]) {
        NSString *path = [payload[@"path"] isKindOfClass:NSString.class] ? payload[@"path"] : @"";
        if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]) {
            [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"openTerminalApp"]) {
        NSString *cwd = [payload[@"cwd"] isKindOfClass:NSString.class] ? payload[@"cwd"] : _selectedSession.cwd;
        NSURL *termURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
        BOOL isDir = NO;
        if (termURL && cwd.length && [NSFileManager.defaultManager fileExistsAtPath:cwd isDirectory:&isDir] && isDir) {
            NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
            [NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:cwd isDirectory:YES]]
                             withApplicationAtURL:termURL
                                    configuration:config
                                completionHandler:nil];
        } else if (termURL) {
            [NSWorkspace.sharedWorkspace openURL:termURL];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"copyText"]) {
        NSString *text = [payload[@"text"] isKindOfClass:NSString.class] ? payload[@"text"] : @"";
        NSString *label = [payload[@"label"] isKindOfClass:NSString.class] ? payload[@"label"] : PTL(@"已拷贝", @"Copied");
        if (text.length) {
            NSPasteboard *pb = NSPasteboard.generalPasteboard;
            [pb clearContents];
            [pb setString:text forType:NSPasteboardTypeString];
            _statusText = label;
            [self pushFrontendWindowState];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"toggleFloatingWindow"]) {
        if ([bridge.surface isEqual:@"floating"]) [_lobeFloatingPanel close];
        else [self toggleFloatingConversation:nil];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"updateDraft"]) {
        NSString *draft = [payload[@"draft"] isKindOfClass:NSString.class] ? payload[@"draft"] : @"";
        NSString *tabId = [payload[@"tabId"] isKindOfClass:NSString.class] ? payload[@"tabId"] : @"";
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        if ([bridge.surface isEqual:@"floating"]) {
            if ([sessionID isEqual:_floatingSessionID]) {
                _floatingDraft = [draft copy];
                _floatingDraftRevision++;
            }
        } else {
            for (PTWorkspaceTab *tab in _workspaceTabs) {
                if (![tab.identifier isEqual:tabId] || ![(tab.sessionID ?: @"") isEqual:sessionID]) continue;
                tab.draft = [draft copy];
                tab.draftRevision++;
                break;
            }
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"savePanelState"]) {
        NSString *tabId = [payload[@"tabId"] isKindOfClass:NSString.class] ? payload[@"tabId"] : @"";
        PTWorkspaceTab *target = _activeWorkspaceTab;
        if (tabId.length) {
            for (PTWorkspaceTab *tab in _workspaceTabs) {
                if ([tab.identifier isEqual:tabId]) { target = tab; break; }
            }
        }
        if (target) {
            if ([payload[@"activeToolPageKind"] isKindOfClass:NSString.class]) {
                target.activeToolPageKind = payload[@"activeToolPageKind"];
            }
            if (payload[@"overviewExpanded"] != nil) {
                target.overviewExpanded = [payload[@"overviewExpanded"] boolValue];
            }
            if (payload[@"panelExpanded"] != nil) {
                target.panelExpanded = [payload[@"panelExpanded"] boolValue];
            }
            target.fileToolPageOpen = [target.activeToolPageKind isEqual:@"file"];
            target.reviewToolPageOpen = [target.activeToolPageKind isEqual:@"review"];
        }
        [self pushFrontendWorkspace];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"pickAttachments"]) {
        BOOL isFloating = [bridge.surface isEqual:@"floating"] || [payload[@"surface"] isEqual:@"floating"];
        NSWindow *hostWin = isFloating && _lobeFloatingPanel ? _lobeFloatingPanel : _window;
        NSOpenPanel *panel = NSOpenPanel.openPanel;
        panel.canChooseFiles = YES;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = YES;
        [panel beginSheetModalForWindow:hostWin completionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK && panel.URLs.count > 0) {
                [self addComposerAttachmentURLs:panel.URLs floating:isFloating];
                [self pushFrontendWorkspace];
            }
            reply(@{}, nil);
        }];
        return;
    }

    if ([action isEqual:@"pasteClipboardImage"]) {
        BOOL isFloating = [bridge.surface isEqual:@"floating"] || [payload[@"surface"] isEqual:@"floating"];
        BOOL pasted = isFloating
            ? [self handleFloatingImagePasteboard:NSPasteboard.generalPasteboard]
            : [self handleImagePasteboard:NSPasteboard.generalPasteboard];
        [self pushFrontendWorkspace];
        reply(@{ @"pasted": @(pasted) }, nil);
        return;
    }

    if ([action isEqual:@"removeAttachment"]) {
        BOOL isFloating = [bridge.surface isEqual:@"floating"] || [payload[@"surface"] isEqual:@"floating"];
        NSString *kind = [payload[@"kind"] isKindOfClass:NSString.class] ? payload[@"kind"] : @"file";
        NSString *path = [payload[@"path"] isKindOfClass:NSString.class] ? payload[@"path"] : @"";
        if ([kind isEqual:@"image"]) {
            NSMutableArray<NSDictionary *> *list = isFloating ? _floatingPendingImages : _pendingImages;
            NSIndexSet *matches = [list indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
                (void)idx; (void)stop;
                return [item[@"path"] isEqual:path];
            }];
            for (NSDictionary *item in [list objectsAtIndexes:matches]) {
                if ([item[@"temporary"] boolValue] && [item[@"path"] isKindOfClass:NSString.class]) {
                    [NSFileManager.defaultManager removeItemAtPath:item[@"path"] error:nil];
                    [_temporaryImagePaths removeObject:item[@"path"]];
                }
            }
            [list removeObjectsAtIndexes:matches];
        } else {
            NSMutableArray<NSString *> *list = isFloating ? _floatingPendingFiles : _pendingFiles;
            [list removeObject:path];
        }
        [self pushFrontendWorkspace];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"querySlashCommands"]) {
        NSString *query = [payload[@"query"] isKindOfClass:NSString.class] ? payload[@"query"] : @"";
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"]
            : _selectedSession.sessionID;
        PTClaudeBridge *sessionBridge = [self bridgeForSessionID:sessionID];
        NSArray *items = [self commandSuggestions:sessionBridge query:query] ?: @[];
        [bridge pushStateMethod:@"setPrettyTermCommandResults" payload:@{
            @"items": items,
            @"query": query
        }];
        if (!sessionBridge && sessionID.length > 0) {
            [self prepareBridgeForSessionID:sessionID completion:^(PTClaudeBridge *connected) {
                if (!connected) return;
                NSArray *nextItems = [self commandSuggestions:connected query:query] ?: @[];
                [bridge pushStateMethod:@"setPrettyTermCommandResults" payload:@{
                    @"items": nextItems,
                    @"query": query
                }];
            }];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"submitMessage"]) {
        BOOL floating = [bridge.surface isEqual:@"floating"];
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        NSString *rawText = [payload[@"text"] isKindOfClass:NSString.class] ? payload[@"text"] : @"";
        PTWorkspaceTab *tab = nil;
        if (!floating) {
            for (PTWorkspaceTab *candidate in _workspaceTabs) {
                if ([candidate.identifier isEqual:payload[@"tabId"]] && [candidate.sessionID isEqual:sessionID]) {
                    tab = candidate;
                    break;
                }
            }
        }
        if (!sessionID.length || (floating ? ![_floatingSessionID isEqual:sessionID] : !tab)) {
            reply(nil, PTL(@"会话已切换", @"The conversation has changed"));
            return;
        }
        NSMutableArray *pendingImages = floating ? _floatingPendingImages : tab.pendingImages;
        NSMutableArray *pendingFiles = floating ? _floatingPendingFiles : tab.pendingFiles;
        NSArray *images = [pendingImages copy];
        NSArray *files = [pendingFiles copy];
        NSMutableArray<NSData *> *pngs = [NSMutableArray arrayWithCapacity:images.count];
        for (NSDictionary *image in images) {
            if ([image[@"pngData"] length]) [pngs addObject:image[@"pngData"]];
        }
        NSUInteger draftRevision = floating ? _floatingDraftRevision : tab.draftRevision;
        NSString *outgoing = PTMessageByAppendingClaudeAttachMarkers(rawText, files);
        [self submitOutgoingMessage:outgoing imagePNGs:pngs forSessionID:sessionID completion:^(NSString *error) {
            if (error) {
                if (floating && [self->_floatingSessionID isEqual:sessionID]) self->_floatingStatusText = error;
                if (!floating && [self->_selectedSession.sessionID isEqual:sessionID]) self->_statusText = error;
                [self pushFrontendWindowState];
                reply(nil, error);
                return;
            }
            if (pngs.count || ![self isConfigurationCommand:outgoing]) [self beginAwaitingClaudeReplyForSessionID:sessionID];
            BOOL clearDraft = floating
                ? [self->_floatingSessionID isEqual:sessionID] && self->_floatingDraftRevision == draftRevision
                : [tab.sessionID isEqual:sessionID] && tab.draftRevision == draftRevision;
            if (clearDraft) {
                if (floating) self->_floatingDraft = @"";
                else tab.draft = @"";
            }
            for (NSString *file in files) {
                NSUInteger index = [pendingFiles indexOfObjectIdenticalTo:file];
                if (index != NSNotFound) [pendingFiles removeObjectAtIndex:index];
            }
            for (NSDictionary *image in images) {
                NSUInteger index = [pendingImages indexOfObjectIdenticalTo:image];
                if (index == NSNotFound) continue;
                [pendingImages removeObjectAtIndex:index];
                NSString *path = image[@"path"];
                if (![image[@"temporary"] boolValue] || !path.length) continue;
                [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                [self->_temporaryImagePaths removeObject:path];
            }
            [self pushFrontendComposer];
            reply(@{ @"accepted": @YES, @"clearedDraft": @(clearDraft) }, nil);
        }];
        return;
    }

    if ([action isEqual:@"interruptOutput"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        BOOL ok = [self interruptClaudeOutputForSessionID:sessionID];
        reply(@{ @"interrupted": @(ok) }, nil);
        return;
    }

    if ([action isEqual:@"backgroundClaudeTask"] || [action isEqual:@"readClaudeTaskOutput"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        PTClaudeBridge *target = [self bridgeForSessionID:sessionID];
        if (!target) {
            reply(nil, PTL(@"Claude 会话未连接", @"Claude session is disconnected"));
            return;
        }
        BOOL background = [action isEqual:@"backgroundClaudeTask"];
        NSString *key = background ? @"toolUseId" : @"taskId";
        NSString *identifier = [payload[key] isKindOfClass:NSString.class] ? payload[key] : @"";
        if (!identifier.length) {
            reply(nil, PTL(@"缺少任务标识", @"Missing task identifier"));
            return;
        }
        if (background) [target backgroundTaskForToolUseID:identifier completion:reply];
        else [target readTaskOutput:identifier completion:reply];
        return;
    }

    if ([action isEqual:@"connectClaude"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        if ([bridge.surface isEqual:@"floating"]) {
            [self prepareBridgeForSessionID:sessionID completion:^(PTClaudeBridge *connected) {
                [self pushFrontendSessions];
                [self pushFrontendWindowState];
                reply(connected ? @{} : nil, connected ? nil : PTL(@"无法连接 Claude Code 会话", @"Could not connect to the Claude Code conversation"));
            }];
            return;
        }
        PTSessionInfo *target = sessionID.length ? [self sessionWithID:sessionID] : _selectedSession;
        if (target && ![_selectedSession.sessionID isEqual:target.sessionID]) {
            _selectedSession = target;
            _activeWorkspaceTab.sessionID = target.sessionID ?: @"";
        }
        if (_selectedSession) [self connectSelectedSession:nil];
        [self pushFrontendWorkspace];
        [self pushFrontendSessions];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"disconnectClaude"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        PTClaudeBridge *targetBridge = [self bridgeForSessionID:sessionID];
        [targetBridge stop];
        if (sessionID.length) [self finishAwaitingClaudeReplyForSessionID:sessionID];
        [self refreshAgentStateAndControls];
        [self updateWorkspaceTabBar];
        [self pushFrontendSessions];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"forceResyncSession"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        PTSessionInfo *target = [self sessionWithID:sessionID];
        if (target.filePath.length) {
            __weak typeof(self) weakSelf = self;
            [_store refreshForcingPath:target.filePath completion:^(PTSessionInfo *session) {
                PTAppDelegate *self = weakSelf;
                if (!self || !session) return;
                NSMutableArray<PTSessionInfo *> *updated = [self->_sessions mutableCopy] ?: [NSMutableArray array];
                NSUInteger idx = [updated indexOfObjectPassingTest:^BOOL(PTSessionInfo *c, NSUInteger i, BOOL *s) {
                    (void)i; (void)s;
                    return [c.sessionID isEqual:session.sessionID];
                }];
                if (idx == NSNotFound) [updated addObject:session];
                else updated[idx] = session;
                self->_manualRefreshSessionID = [session.sessionID copy];
                [self applySessions:updated];
            }];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"sendCompact"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        if (sessionID.length) {
            [self sendOutgoingMessage:@"/compact" imagePNGs:@[] forSessionID:sessionID success:^{
                self->_statusText = PTL(@"已向 Claude Code 发送 /compact", @"Sent /compact to Claude Code");
                [self pushFrontendWindowState];
            } failureResponder:nil];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"toggleRemoteControl"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        if (sessionID.length) {
            [self sendOutgoingMessage:@"/remote-control" imagePNGs:@[] forSessionID:sessionID success:^{
                self->_statusText = PTL(@"已向 Claude Code 发送 /remote-control", @"Sent /remote-control to Claude Code");
                [self pushFrontendWindowState];
            } failureResponder:nil];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"setModel"]) {
        NSString *model = [payload[@"model"] isKindOfClass:NSString.class] ? payload[@"model"] : @"";
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        if (!model.length || !sessionID.length) {
            reply(nil, PTL(@"请选择会话和模型", @"Select a conversation and a model"));
            return;
        }
        [self submitOutgoingMessage:[NSString stringWithFormat:@"/model %@", model]
                           imagePNGs:@[]
                        forSessionID:sessionID
                          completion:^(NSString *error) {
            if (error) { reply(nil, error); return; }
            NSString *confirmedModel = [self composerModelForSessionID:sessionID];
            [self showConfigurationStatus:[NSString stringWithFormat:PTL(@"当前模型：%@", @"Current model: %@"),
                [self composerModelShortTitle:confirmedModel]] forSessionID:sessionID];
            [self pushFrontendWindowState];
            reply(@{@"model": confirmedModel ?: @""}, nil);
        }];
        return;
    }

    if ([action isEqual:@"setEffort"]) {
        NSString *effort = [payload[@"effort"] isKindOfClass:NSString.class] ? payload[@"effort"] : @"";
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        if (effort.length && sessionID.length) {
            _selectedComposerEffort = [effort copy];
            [self sendOutgoingMessage:[NSString stringWithFormat:@"/effort %@", effort]
                            imagePNGs:@[]
                         forSessionID:sessionID
                              success:^{
                [self updateComposerConfigurationButtons];
            } failureResponder:nil];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"setPermissionMode"]) {
        NSString *mode = [payload[@"mode"] isKindOfClass:NSString.class] ? payload[@"mode"] : @"";
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        if (mode.length && sessionID.length) {
            [self sendOutgoingMessage:[NSString stringWithFormat:@"/mode %@", mode]
                            imagePNGs:@[]
                         forSessionID:sessionID
                              success:^{
                [self pushFrontendWindowState];
            } failureResponder:nil];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"answerQuestion"]) {
        NSString *text = [payload[@"text"] isKindOfClass:NSString.class] ? payload[@"text"] : @"";
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class] ? payload[@"sessionId"] : @"";
        NSString *toolUseID = [payload[@"toolUseId"] isKindOfClass:NSString.class] ? payload[@"toolUseId"] : @"";
        NSDictionary *answers = [payload[@"answers"] isKindOfClass:NSDictionary.class] ? payload[@"answers"] : nil;
        if (text.length && sessionID.length) {
            BOOL handledProtocol = NO;
            for (NSString *requestID in _protocolQuestions.allKeys) {
                NSDictionary *request = _protocolQuestions[requestID];
                if ([request[@"sessionID"] isEqual:sessionID] && [request[@"toolUseId"] isEqual:toolUseID]) {
                    [self writeQuestionResponseForRequestID:requestID answers:answers ?: @{}];
                    handledProtocol = YES;
                    break;
                }
            }
            if (!handledProtocol) {
                [self sendOutgoingMessage:text imagePNGs:@[] forSessionID:sessionID success:nil failureResponder:nil];
            }
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"openTranscriptFile"] || [action isEqual:@"previewFile"]) {
        BOOL fromTranscript = [action isEqual:@"openTranscriptFile"];
        BOOL floating = [bridge.surface isEqual:@"floating"];
        id rawPath = payload[fromTranscript ? @"filePath" : @"path"];
        NSString *path = [rawPath isKindOfClass:NSString.class] ? rawPath : @"";
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        PTSessionInfo *session = [self sessionWithID:sessionID];
        if (path.length && !path.isAbsolutePath && session.cwd.length) {
            path = [session.cwd stringByAppendingPathComponent:path];
        }
        PTWorkspaceTab *tab = nil;
        for (PTWorkspaceTab *candidate in _workspaceTabs) {
            if (![(candidate.sessionID ?: @"") isEqual:sessionID ?: @""]) continue;
            if (floating || [candidate.identifier isEqual:payload[@"tabId"]]) { tab = candidate; break; }
        }
        if (floating && fromTranscript && session && [_floatingSessionID isEqual:sessionID]) {
            if (!tab) {
                tab = [self createWorkspaceTab];
                tab.sessionID = sessionID;
            }
            [self activateWorkspaceTab:tab animated:NO];
            [_window makeKeyAndOrderFront:nil];
        }
        if (!tab || !path.length) {
            reply(nil, PTL(@"预览的会话或文件已切换", @"The preview conversation or file has changed"));
            return;
        }
        if (fromTranscript && tab) {
            tab.panelExpanded = YES;
            tab.activeToolPageKind = @"file";
            tab.fileToolPageOpen = YES;
            [self pushFrontendWorkspace];
        }
        [self pushFrontendFilePreviewForPath:path.stringByStandardizingPath
                                  sessionID:tab.sessionID tabID:tab.identifier];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"openTranscriptEditReview"]) {
        NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
            ? payload[@"sessionId"] : _selectedSession.sessionID;
        NSUInteger turnIndex = [payload[@"turnIndex"] unsignedIntegerValue];
        PTSessionInfo *session = [self sessionWithID:sessionID] ?: _selectedSession;
        NSArray<NSDictionary *> *events = PTLobeSanitizeTurnEdits([self transcriptEditEventsForSession:session turnIndex:turnIndex]);
        _gitReviewShowsTranscriptEdits = YES;
        if (_activeWorkspaceTab) {
            _activeWorkspaceTab.panelExpanded = YES;
            _activeWorkspaceTab.activeToolPageKind = @"review";
            _activeWorkspaceTab.reviewToolPageOpen = YES;



            [self pushFrontendWorkspace];
        }
        _turnReviewSnapshot = @{
            @"reviewMode": @"turn",
            @"turnIndex": @(turnIndex),
            @"directories": [_gitDirectoryPaths copy] ?: @[],
            @"observedDirectory": _gitObservedDirectory ?: @"",
            @"editEvents": events ?: @[],
            @"loading": @NO,
            @"actionInFlight": @NO
        };
        [self pushFrontendGitState];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"chooseFileTreeRoot"]) {
        PTWorkspaceTab *tab = _activeWorkspaceTab;
        NSOpenPanel *panel = NSOpenPanel.openPanel;
        panel.canChooseFiles = NO;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = NO;
        [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK && panel.URL) {
                tab.fileTreeRootPath = panel.URL.path ?: @"";
                [self pushFrontendWorkspace];
            }
            reply(@{}, nil);
        }];
        return;
    }

    if ([action isEqual:@"listDirectory"]) {
        NSString *path = [payload[@"path"] isKindOfClass:NSString.class] ? payload[@"path"] : @"";
        NSString *root = [payload[@"rootPath"] isKindOfClass:NSString.class] ? payload[@"rootPath"] : @"";
        NSString *tabID = [payload[@"tabId"] isKindOfClass:NSString.class] ? payload[@"tabId"] : @"";
        [self pushFrontendDirectoryListingForPath:path root:root tabID:tabID];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"refreshGitReview"]) {
        NSString *mode = [payload[@"mode"] isKindOfClass:NSString.class] ? payload[@"mode"] : @"git";
        if ([mode isEqual:@"turn"]) {
            NSString *sessionID = [payload[@"sessionId"] isKindOfClass:NSString.class]
                ? payload[@"sessionId"] : _selectedSession.sessionID;
            NSUInteger turnIndex = [payload[@"turnIndex"] unsignedIntegerValue];
            PTSessionInfo *session = [self sessionWithID:sessionID] ?: _selectedSession;
            NSArray<NSDictionary *> *events = PTLobeSanitizeTurnEdits([self transcriptEditEventsForSession:session turnIndex:turnIndex]);
            _gitReviewShowsTranscriptEdits = YES;
            _turnReviewSnapshot = @{
                @"reviewMode": @"turn",
                @"turnIndex": @(turnIndex),
                @"directories": [_gitDirectoryPaths copy] ?: @[],
                @"observedDirectory": _gitObservedDirectory ?: @"",
                @"editEvents": events ?: @[],
                @"loading": @NO,
                @"actionInFlight": @(_gitActionInFlight)
            };
            [self pushFrontendGitState];
        } else {
            NSString *dir = [payload[@"directory"] isKindOfClass:NSString.class] && [payload[@"directory"] length] > 0
                ? payload[@"directory"]
                : (_gitObservedDirectory.length > 0 ? _gitObservedDirectory : _selectedSession.cwd);
            if (dir.length > 0) _gitObservedDirectory = [dir copy];
            [self pushFrontendGitDiffForDirectory:dir ?: @""];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"setReviewVisible"]) {
        NSString *tabID = payload[@"tabId"];
        if ([payload[@"visible"] boolValue]) {
            PTWorkspaceTab *tab = _activeWorkspaceTab;
            if ([tab.identifier isEqual:tabID] && tab.panelExpanded && [tab.activeToolPageKind isEqual:@"review"] &&
                ![_gitVisibleTabID isEqual:tabID]) {
                _gitVisibleTabID = [tabID copy];
                if (!_gitReviewShowsTranscriptEdits) {
                    NSString *dir = _gitObservedDirectory.length ? _gitObservedDirectory : _selectedSession.cwd;
                    if (dir.length) _gitObservedDirectory = [dir copy];
                    if (![_gitReviewInFlightDirectory isEqual:dir]) [self pushFrontendGitDiffForDirectory:dir];
                }
            }
        } else if ([_gitVisibleTabID isEqual:tabID]) {
            _gitVisibleTabID = nil;
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"selectGitDirectory"]) {
        NSString *dir = [payload[@"directory"] isKindOfClass:NSString.class] ? payload[@"directory"] : @"";
        if (dir.length) {
            _gitObservedDirectory = [dir copy];
            _gitDirectoryManuallySelected = YES;
            [self selectObservedGitDirectory:dir];
            [self pushFrontendGitDiffForDirectory:dir];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"chooseGitDirectory"]) {
        NSOpenPanel *panel = NSOpenPanel.openPanel;
        panel.canChooseFiles = NO;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = NO;
        [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK && panel.URL.path.length > 0) {
                NSString *path = panel.URL.path.stringByStandardizingPath;
                if (!self->_gitDirectoryPaths) self->_gitDirectoryPaths = [NSMutableArray array];
                [self->_suppressedGitDirectoryPaths removeObject:path];
                [NSUserDefaults.standardUserDefaults setObject:
                    [self->_suppressedGitDirectoryPaths.allObjects sortedArrayUsingSelector:@selector(compare:)]
                    forKey:@"PTGitSuppressedDirectories"];
                if (![self->_gitDirectoryPaths containsObject:path]) {
                    [self->_gitDirectoryPaths insertObject:path atIndex:0];
                }
                self->_gitObservedDirectory = [path copy];
                self->_gitDirectoryManuallySelected = YES;
                [NSUserDefaults.standardUserDefaults setObject:self->_gitDirectoryPaths forKey:@"PTGitObservedDirectories"];
                [self selectObservedGitDirectory:path];
                [self pushFrontendGitDiffForDirectory:path];
            }
            reply(@{}, nil);
        }];
        return;
    }

    if ([action isEqual:@"removeGitDirectory"]) {
        NSString *dir = [payload[@"directory"] isKindOfClass:NSString.class] ? payload[@"directory"] : _gitObservedDirectory;
        NSUInteger removedIndex = dir.length ? [_gitDirectoryPaths indexOfObject:dir] : NSNotFound;
        if (removedIndex != NSNotFound) {
            if (!_suppressedGitDirectoryPaths) _suppressedGitDirectoryPaths = [NSMutableSet set];
            [_suppressedGitDirectoryPaths addObject:dir];
            [NSUserDefaults.standardUserDefaults setObject:
                [_suppressedGitDirectoryPaths.allObjects sortedArrayUsingSelector:@selector(compare:)]
                forKey:@"PTGitSuppressedDirectories"];
            [_gitDirectoryPaths removeObjectAtIndex:removedIndex];
            [NSUserDefaults.standardUserDefaults setObject:_gitDirectoryPaths forKey:@"PTGitObservedDirectories"];
            NSString *nextDir = _gitDirectoryPaths.count > 0
                ? _gitDirectoryPaths[MIN(removedIndex, _gitDirectoryPaths.count - 1)]
                : @"";
            _gitObservedDirectory = nextDir.length ? [nextDir copy] : nil;
            _gitDirectoryManuallySelected = nextDir.length > 0;
            [self selectObservedGitDirectory:nextDir];
            [self pushFrontendGitDiffForDirectory:nextDir];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"gitCommitAndPush"]) {
        BOOL commit = [payload[@"commit"] boolValue];
        BOOL push = [payload[@"push"] boolValue];
        BOOL includeUnstaged = payload[@"includeUnstaged"] ? [payload[@"includeUnstaged"] boolValue] : YES;
        NSString *directory = [payload[@"directory"] isKindOfClass:NSString.class] && [payload[@"directory"] length] > 0
            ? payload[@"directory"] : _gitObservedDirectory;
        NSString *message = [payload[@"message"] isKindOfClass:NSString.class]
            ? [payload[@"message"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
            : @"";
        [self performGitCommit:commit push:push includeUnstaged:includeUnstaged directory:directory message:message];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"setTerminalVisible"]) {
        _terminalDrawerVisible = [payload[@"visible"] boolValue];
        if (_terminalDrawerVisible) [self publishTerminalOutput:[_lobeTerminalOutput copy] reset:YES];
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"runTerminalCommand"]) {
        NSString *cmd = [payload[@"command"] isKindOfClass:NSString.class] ? payload[@"command"] : @"";
        NSString *cwd = [payload[@"cwd"] isKindOfClass:NSString.class] && [payload[@"cwd"] length] > 0
            ? payload[@"cwd"] : (_selectedSession.cwd ?: NSHomeDirectory());
        NSString *tabId = [payload[@"tabId"] isKindOfClass:NSString.class] ? payload[@"tabId"] : @"";
        if (cmd.length == 0) {
            reply(@{}, nil);
            return;
        }
        if (_lobeTerminalTask.running) [_lobeTerminalTask terminate];
        if (!_lobeTerminalOutput) _lobeTerminalOutput = [NSMutableString string];
        NSString *prompt = [NSString stringWithFormat:@"\n$ %@\n", cmd];
        [_lobeTerminalOutput appendString:prompt];
        _terminalRunID = NSUUID.UUID.UUIDString;
        _terminalSequence = 0;
        _lobeTerminalCommand = [cmd copy];
        _lobeTerminalCwd = [cwd copy];
        _lobeTerminalTabID = [tabId copy];
        _lobeTerminalRunning = YES;
        _lobeTerminalExitCode = nil;
        [self publishTerminalOutput:prompt reset:NO];

        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
        task.arguments = @[@"-lc", cmd];
        BOOL isDir = NO;
        if (cwd.length && [NSFileManager.defaultManager fileExistsAtPath:cwd isDirectory:&isDir] && isDir) {
            task.currentDirectoryURL = [NSURL fileURLWithPath:cwd isDirectory:YES];
        }
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = pipe;
        _lobeTerminalTask = task;

        NSFileHandle *readHandle = pipe.fileHandleForReading;
        __weak typeof(self) weakSelf = self;
        readHandle.readabilityHandler = ^(NSFileHandle *handle) {
            NSData *chunk = handle.availableData;
            if (chunk.length == 0) {
                handle.readabilityHandler = nil;
                return;
            }
            NSString *text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding]
                ?: [[NSString alloc] initWithData:chunk encoding:NSISOLatin1StringEncoding] ?: @"";
            if (text.length == 0) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) s = weakSelf;
                if (!s || s->_lobeTerminalTask != task) return;
                [s->_lobeTerminalOutput appendString:text];
                [s publishTerminalOutput:text reset:NO];
            });
        };
        task.terminationHandler = ^(NSTask *finished) {
            readHandle.readabilityHandler = nil;
            NSData *remaining = [readHandle readDataToEndOfFile];
            NSString *tail = remaining.length > 0
                ? ([[NSString alloc] initWithData:remaining encoding:NSUTF8StringEncoding] ?: @"")
                : @"";
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) s = weakSelf;
                if (!s || s->_lobeTerminalTask != finished) return;
                if (tail.length > 0) [s->_lobeTerminalOutput appendString:tail];
                s->_lobeTerminalRunning = NO;
                s->_lobeTerminalExitCode = @(finished.terminationStatus);
                [s publishTerminalOutput:tail reset:NO];
            });
        };
        NSError *launchErr = nil;
        if (![task launchAndReturnError:&launchErr]) {
            readHandle.readabilityHandler = nil;
            _lobeTerminalRunning = NO;
            _lobeTerminalExitCode = @1;
            NSString *failure = [NSString stringWithFormat:@"Launch failed: %@\n", launchErr.localizedDescription ?: @"unknown error"];
            [_lobeTerminalOutput appendString:failure];
            [self publishTerminalOutput:failure reset:NO];
        }
        reply(@{}, nil);
        return;
    }

    if ([action isEqual:@"clearTerminalOutput"]) {
        _lobeTerminalOutput = [NSMutableString string];
        _lobeTerminalRunning = NO;
        _lobeTerminalExitCode = nil;
        [self publishTerminalOutput:@"" reset:YES];
        reply(@{}, nil);
        return;
    }

    reply(@{}, nil);
}

- (void)frontendBridgeDidFinishLoad:(PTFrontendBridge *)bridge {
    [bridge pushWindowState:[self frontendWindowStateSnapshotForSurface:bridge.surface]];
    [bridge pushStateMethod:@"setPrettyTermWorkspace" payload:[self frontendWorkspaceSnapshotForSurface:bridge.surface]];
    [bridge pushStateMethod:@"setPrettyTermComposer" payload:[self frontendComposerSnapshotForSurface:bridge.surface]];
    [self pushFrontendClaudeTasksTo:bridge
                         sessionID:bridge == _lobeFloatingBridge ? _floatingSessionID : _selectedSession.sessionID];
    [self pushFrontendSessions];
    if (bridge == _lobeMainBridge) {
        [self pushFrontendGitState];
        _gitVisibleTabID = nil;
        _terminalDrawerVisible = NO;
        _renderInFlight = NO;
        _pendingRenderSession = nil;
        _renderedSessionID = nil;
        _renderedModifiedAt = nil;
        _renderedMessageCount = 0;
        _renderedMessages = nil;
        if (_selectedSession) [self renderSession:_selectedSession];
    } else if (bridge == _lobeFloatingBridge) {
        _floatingRenderInFlight = NO;
        _floatingRenderedSessionID = nil;
        _floatingRenderedModifiedAt = nil;
        _floatingRenderedMessageCount = 0;
        _floatingRenderedMessages = nil;
        [self refreshFloatingConversation];
    }
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        PTAppDelegate *delegate = [[PTAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
