#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <errno.h>
#import <signal.h>
#import <string.h>
#import "PTAgentState.h"
#import "PTFilePreview.h"
#import "PTGitReview.h"
#import "PTLocalization.h"
#import "PTUsageMetrics.h"

static NSColor *PTColor(CGFloat red, CGFloat green, CGFloat blue) {
    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:1.0];
}

static NSColor *PTWarmDynamicColor(
    CGFloat lightRed, CGFloat lightGreen, CGFloat lightBlue,
    CGFloat darkRed, CGFloat darkGreen, CGFloat darkBlue
) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]];
        BOOL dark = [match isEqual:NSAppearanceNameDarkAqua];
        return PTColor(
            dark ? darkRed : lightRed,
            dark ? darkGreen : lightGreen,
            dark ? darkBlue : lightBlue
        );
    }];
}

static NSColor *PTWarmCanvasColor(void) {
    return PTWarmDynamicColor(0.953, 0.922, 0.867, 0.129, 0.098, 0.071);
}

static NSColor *PTWarmCardColor(void) {
    return PTWarmDynamicColor(0.988, 0.969, 0.925, 0.176, 0.129, 0.094);
}

static NSColor *PTWarmChipColor(void) {
    return PTWarmDynamicColor(0.973, 0.937, 0.878, 0.220, 0.153, 0.106);
}

static NSColor *PTWarmBorderColor(void) {
    return PTWarmDynamicColor(0.835, 0.733, 0.608, 0.376, 0.259, 0.173);
}

static NSColor *PTWarmAccentColor(void) {
    return PTWarmDynamicColor(0.639, 0.278, 0.090, 0.910, 0.537, 0.286);
}

typedef NS_ENUM(NSInteger, PTAppearanceSurfaceStyle) {
    PTAppearanceSurfaceStyleCanvas,
    PTAppearanceSurfaceStyleCard,
    PTAppearanceSurfaceStyleChip
};

@interface PTAppearanceSurfaceView : NSView
@property(nonatomic) PTAppearanceSurfaceStyle surfaceStyle;
@end

@interface PTWorkspaceSplitView : NSSplitView
@property(nonatomic) BOOL changingDivider;
@property(nonatomic) NSInteger changingDividerIndex;
@property(nonatomic) BOOL mouseDraggingDivider;
@property(nonatomic) CGFloat trackedDividerPosition;
- (void)setTrackedPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)index;
@end

@interface PTWorkspaceRootView : NSView
@end

@implementation PTWorkspaceRootView
@end

@interface PTInspectorOverlayView : NSView
@property(nonatomic) BOOL floating;
@property(nonatomic, copy) void (^floatingFrameChanged)(NSRect frame);
- (void)constrainFloatingFrame;
@end

@implementation PTInspectorOverlayView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    if (!self.floating) return [super hitTest:point];
    NSPoint local = point;
    BOOL resizeEdge = local.x <= 9.0 || local.x >= NSWidth(self.bounds) - 9.0;
    BOOL dragHeader = local.y >= NSHeight(self.bounds) - 58.0 &&
        local.x < NSWidth(self.bounds) - 96.0;
    return resizeEdge || dragHeader ? self : [super hitTest:point];
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (!self.floating) return;
    [self addCursorRect:NSMakeRect(0, 0, 9, NSHeight(self.bounds))
                 cursor:NSCursor.resizeLeftRightCursor];
    [self addCursorRect:NSMakeRect(NSWidth(self.bounds) - 9, 0, 9, NSHeight(self.bounds))
                 cursor:NSCursor.resizeLeftRightCursor];
}

- (void)constrainFloatingFrame {
    if (!self.floating || !self.superview) return;
    NSRect available = self.superview.bounds;
    CGFloat margin = 12.0;
    CGFloat workspaceTop = NSMaxY(available) - 64.0 - margin;
    CGFloat maximumHeight = MAX(320.0, workspaceTop - NSMinY(available) - margin);
    NSRect frame = self.frame;
    frame.size.width = MIN(520.0, MAX(300.0,
        MIN(frame.size.width, NSWidth(available) - margin * 2.0)));
    frame.size.height = MIN(frame.size.height, maximumHeight);
    frame.origin.x = MIN(MAX(NSMinX(available) + margin, frame.origin.x),
        NSMaxX(available) - margin - frame.size.width);
    frame.origin.y = MIN(MAX(NSMinY(available) + margin, frame.origin.y),
        workspaceTop - frame.size.height);
    self.frame = NSIntegralRect(frame);
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.floating || !self.superview) {
        [super mouseDown:event];
        return;
    }
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL resizeLeft = local.x <= 9.0;
    BOOL resizeRight = local.x >= NSWidth(self.bounds) - 9.0;
    BOOL moving = !resizeLeft && !resizeRight;
    NSRect startingFrame = self.frame;
    NSPoint startingPoint = [self.superview convertPoint:event.locationInWindow fromView:nil];
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:
            NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        if (next.type == NSEventTypeLeftMouseUp) break;
        NSPoint currentPoint = [self.superview convertPoint:next.locationInWindow fromView:nil];
        CGFloat dx = currentPoint.x - startingPoint.x;
        CGFloat dy = currentPoint.y - startingPoint.y;
        NSRect frame = startingFrame;
        if (moving) {
            frame.origin.x += dx;
            frame.origin.y += dy;
        } else if (resizeLeft) {
            CGFloat right = NSMaxX(startingFrame);
            frame.origin.x += dx;
            frame.size.width = right - frame.origin.x;
        } else {
            frame.size.width += dx;
        }
        self.frame = frame;
        [self constrainFloatingFrame];
        if (self.floatingFrameChanged) self.floatingFrameChanged(self.frame);
    }
}

@end

@implementation PTWorkspaceSplitView
- (void)setTrackedPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)index {
    BOOL previous = self.changingDivider;
    NSInteger previousIndex = self.changingDividerIndex;
    self.changingDivider = YES;
    self.changingDividerIndex = index;
    self.trackedDividerPosition = position;
    if ([self.delegate respondsToSelector:@selector(splitViewWillResizeSubviews:)]) {
        [self.delegate splitViewWillResizeSubviews:
            [NSNotification notificationWithName:NSSplitViewWillResizeSubviewsNotification object:self]];
    }
    [super setPosition:position ofDividerAtIndex:index];
    if ([self.delegate respondsToSelector:@selector(splitViewDidResizeSubviews:)]) {
        [self.delegate splitViewDidResizeSubviews:
            [NSNotification notificationWithName:NSSplitViewDidResizeSubviewsNotification object:self]];
    }
    self.changingDivider = previous;
    self.changingDividerIndex = previousIndex;
    self.trackedDividerPosition = 0.0;
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.changingDividerIndex = 0;
    if (self.subviews.count > 1 && point.x > NSMaxX(self.subviews[1].frame) - 5)
        self.changingDividerIndex = 1;
    self.changingDivider = YES;
    self.mouseDraggingDivider = YES;
    [super mouseDown:event];
    self.mouseDraggingDivider = NO;
    if ([self.delegate respondsToSelector:@selector(splitViewDidResizeSubviews:)]) {
        [self.delegate splitViewDidResizeSubviews:
            [NSNotification notificationWithName:NSSplitViewDidResizeSubviewsNotification object:self]];
    }
    self.changingDivider = NO;
}
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
@property(nonatomic) CGFloat cornerRadius;
@end

@interface PTWarmPopUpButton : NSPopUpButton
@end

@interface PTWarmToggleButton : PTAnimatedButton
@end

@interface PTPassthroughTextField : NSTextField
@end

@interface PTQuestionOptionButton : PTAnimatedButton
- (instancetype)initWithLabel:(NSString *)label
                  description:(NSString *)description
                        index:(NSInteger)index;
@end

@interface PTFlippedView : NSView
@end

@interface PTComposerDropSurfaceView : NSView
@property(nonatomic, copy) BOOL (^dropHandler)(NSArray<NSURL *> *urls);
@property(nonatomic) BOOL dropEnabled;
@end

@interface PTEffortSlider : NSControl <NSGestureRecognizerDelegate>
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) NSInteger submittedIndex;
@end

@implementation PTFirstMouseButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}
@end

@implementation PTPassthroughTextField
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
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

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    if (self.image && title.length == 0) {
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.imageHugsTitle = NO;
        self.alignment = NSTextAlignmentCenter;
    }
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
        _hoverFillColor = PTWarmChipColor();
        _pressedFillColor = PTWarmBorderColor();
        _strokeColor = NSColor.clearColor;
        _cornerRadius = 12;
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
    return NSMakeSize(imageOnly ? 28.0 : MAX(32.0, size.width + 20.0), 28.0);
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
        self.layer.borderWidth = self.strokeColor == NSColor.clearColor ? 0 : 0.7;
        self.layer.cornerRadius = self.cornerRadius;
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

@implementation PTWarmPopUpButton {
    NSTrackingArea *_trackingArea;
    BOOL _hovered;
    BOOL _pressed;
}

- (instancetype)initWithFrame:(NSRect)frameRect pullsDown:(BOOL)flag {
    self = [super initWithFrame:frameRect pullsDown:flag];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.bordered = NO;
    self.focusRingType = NSFocusRingTypeNone;
    self.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    NSPopUpButtonCell *cell = (NSPopUpButtonCell *)self.cell;
    cell.arrowPosition = NSPopUpNoArrow;
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
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
    self.layer.transform = CATransform3DMakeScale(0.975, 0.975, 1);
    [CATransaction commit];
    [super mouseDown:event];
    _pressed = NO;
    [self setNeedsDisplay:YES];
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.20];
    self.layer.transform = CATransform3DIdentity;
    [CATransaction commit];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alphaValue = enabled ? 1.0 : 0.42;
    [self setNeedsDisplay:YES];
}

- (NSSize)intrinsicContentSize {
    NSString *title = self.titleOfSelectedItem ?: self.title ?: @"";
    NSFont *font = self.font ?: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    CGFloat width = ceil([title sizeWithAttributes:@{NSFontAttributeName: font}].width) + 42.0;
    return NSMakeSize(MAX(72.0, width), 28.0);
}

- (NSEdgeInsets)alignmentRectInsets {
    return NSEdgeInsetsZero;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
        CGFloat radius = MIN(9.0, NSHeight(bounds) * 0.42);
        NSColor *fill = self->_pressed ? PTWarmBorderColor()
            : (self->_hovered ? PTWarmChipColor() : PTWarmCardColor());
        NSBezierPath *surface = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                               xRadius:radius yRadius:radius];
        [fill setFill];
        [surface fill];
        [PTWarmBorderColor() setStroke];
        surface.lineWidth = 0.75;
        [surface stroke];

        NSString *title = self.titleOfSelectedItem ?: self.title ?: @"";
        NSColor *textColor = self.enabled ? NSColor.labelColor : NSColor.tertiaryLabelColor;
        NSDictionary *attributes = @{
            NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: textColor
        };
        NSRect textRect = NSInsetRect(bounds, 12.0, 0.0);
        textRect.size.width = MAX(0.0, textRect.size.width - 22.0);
        NSSize textSize = [title sizeWithAttributes:attributes];
        textRect.origin.y = NSMidY(bounds) - textSize.height * 0.5;
        textRect.size.height = textSize.height;
        [title drawInRect:textRect withAttributes:attributes];

        CGFloat chevronX = NSMaxX(bounds) - 15.0;
        CGFloat chevronY = NSMidY(bounds);
        CGFloat outerY = self.isFlipped ? chevronY - 2.0 : chevronY + 2.0;
        CGFloat centerY = self.isFlipped ? chevronY + 2.0 : chevronY - 2.0;
        NSBezierPath *chevron = [NSBezierPath bezierPath];
        [chevron moveToPoint:NSMakePoint(chevronX - 4.0, outerY)];
        [chevron lineToPoint:NSMakePoint(chevronX, centerY)];
        [chevron lineToPoint:NSMakePoint(chevronX + 4.0, outerY)];
        chevron.lineWidth = 1.7;
        chevron.lineCapStyle = NSLineCapStyleRound;
        chevron.lineJoinStyle = NSLineJoinStyleRound;
        [textColor setStroke];
        [chevron stroke];
    }];
}
@end

@implementation PTWarmToggleButton
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.buttonType = NSButtonTypePushOnPushOff;
    self.alignment = NSTextAlignmentCenter;
    self.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
    self.fillColor = PTWarmCardColor();
    self.hoverFillColor = PTWarmChipColor();
    self.pressedFillColor = PTWarmBorderColor();
    self.strokeColor = PTWarmBorderColor();
    self.cornerRadius = 8;
    return self;
}

- (void)setState:(NSControlStateValue)state {
    [super setState:state];
    self.title = state == NSControlStateValueOn ? @"✓" : @"";
    self.fillColor = state == NSControlStateValueOn ? PTWarmChipColor() : PTWarmCardColor();
    [self setNeedsDisplay:YES];
}
@end

static PTAnimatedButton *PTWarmButton(NSString *title, id target, SEL action) {
    PTAnimatedButton *button = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = title ?: @"";
    button.target = target;
    button.action = action;
    button.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    button.contentTintColor = NSColor.labelColor;
    button.fillColor = PTWarmCardColor();
    button.hoverFillColor = PTWarmChipColor();
    button.pressedFillColor = PTWarmDynamicColor(0.815, 0.697, 0.550, 0.315, 0.235, 0.180);
    button.strokeColor = [PTWarmBorderColor() colorWithAlphaComponent:0.82];
    button.cornerRadius = 9;
    return button;
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
    self.fillColor = PTWarmCardColor();
    self.hoverFillColor = PTWarmChipColor();
    self.pressedFillColor = PTWarmBorderColor();
    self.strokeColor = PTWarmBorderColor();
    self.cornerRadius = 15;
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
            self.layer.backgroundColor = PTWarmDynamicColor(
                0.956, 0.855, 0.710, 0.286, 0.173, 0.102).CGColor;
            self.layer.borderColor = PTWarmAccentColor().CGColor;
            self.layer.borderWidth = 1.25;
        }
        self->_numberLabel.layer.backgroundColor =
            (selected ? PTWarmAccentColor() : PTWarmChipColor()).CGColor;
        self->_numberLabel.textColor = selected ? NSColor.whiteColor : NSColor.secondaryLabelColor;
        self->_checkLabel.textColor = selected ? PTWarmAccentColor() : NSColor.clearColor;
    }];
}
@end

@implementation PTFlippedView
- (BOOL)isFlipped { return YES; }
@end

@implementation PTComposerDropSurfaceView {
    BOOL _dragActive;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _dropEnabled = NO;
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = PTWarmCardColor().CGColor;
        self.layer.borderColor = (_dragActive ? PTWarmAccentColor() : PTWarmBorderColor()).CGColor;
        self.layer.borderWidth = _dragActive ? 1.8 : 0.8;
        self.layer.cornerRadius = 26;
        self.layer.shadowColor = NSColor.blackColor.CGColor;
        self.layer.shadowOpacity = _dragActive ? 0.18 : 0.09;
        self.layer.shadowRadius = _dragActive ? 18 : 13;
        self.layer.shadowOffset = CGSizeMake(0, -3);
    }];
}

- (NSArray<NSURL *> *)draggedFileURLs:(id<NSDraggingInfo>)sender {
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    return [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:options] ?: @[];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if (!self.dropEnabled || [self draggedFileURLs:sender].count == 0) return NSDragOperationNone;
    _dragActive = YES;
    [self setNeedsDisplay:YES];
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    (void)sender;
    _dragActive = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [self draggedFileURLs:sender];
    _dragActive = NO;
    [self setNeedsDisplay:YES];
    return self.dropEnabled && urls.count > 0 && self.dropHandler && self.dropHandler(urls);
}
@end

@implementation PTEffortSlider {
    CALayer *_trackLayer;
    CALayer *_fillLayer;
    CALayer *_thumbLayer;
    NSArray<CALayer *> *_dotLayers;
    NSInteger _trackingStartIndex;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _selectedIndex = 1;
        _trackLayer = [CALayer layer];
        _fillLayer = [CALayer layer];
        _thumbLayer = [CALayer layer];
        NSMutableArray *dots = [NSMutableArray array];
        [self.layer addSublayer:_trackLayer];
        [self.layer addSublayer:_fillLayer];
        for (NSInteger index = 0; index < 5; index++) {
            CALayer *dot = [CALayer layer];
            [dots addObject:dot];
            [self.layer addSublayer:dot];
        }
        _dotLayers = dots;
        [self.layer addSublayer:_thumbLayer];

        NSPanGestureRecognizer *pan = [[NSPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleEffortPan:)];
        NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleEffortClick:)];
        pan.delegate = self;
        click.delegate = self;
        [self addGestureRecognizer:pan];
        [self addGestureRecognizer:click];
    }
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }

- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer
        shouldRequireFailureOfGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer {
    return [gestureRecognizer isKindOfClass:NSClickGestureRecognizer.class]
        && [otherGestureRecognizer isKindOfClass:NSPanGestureRecognizer.class];
}

- (CGFloat)xForIndex:(NSInteger)index {
    CGFloat left = 19;
    CGFloat right = MAX(left, self.bounds.size.width - 19);
    return left + (right - left) * MIN(4, MAX(0, index)) / 4.0;
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    NSInteger next = MIN(4, MAX(-1, selectedIndex));
    if (_selectedIndex == next) return;
    BOOL animate = _selectedIndex >= 0 && next >= 0;
    CGFloat oldX = [self xForIndex:_selectedIndex];
    _selectedIndex = next;
    [self setNeedsLayout:YES];
    if (animate && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        CGFloat nextX = [self xForIndex:next];
        CABasicAnimation *thumb = [CABasicAnimation animationWithKeyPath:@"position.x"];
        thumb.fromValue = @(oldX);
        thumb.toValue = @(nextX);
        thumb.duration = 0.24;
        thumb.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_thumbLayer addAnimation:thumb forKey:@"effort-thumb"];
    }
}

- (void)layout {
    [super layout];
    CGFloat left = 19;
    CGFloat right = MAX(left, self.bounds.size.width - 19);
    CGFloat centerY = NSMidY(self.bounds);
    CGFloat selectedX = [self xForIndex:self.selectedIndex];
    _thumbLayer.hidden = self.selectedIndex < 0;
    _fillLayer.hidden = self.selectedIndex < 0;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        _trackLayer.backgroundColor = PTWarmChipColor().CGColor;
        _fillLayer.backgroundColor = PTWarmAccentColor().CGColor;
        _thumbLayer.backgroundColor = PTWarmCardColor().CGColor;
        _thumbLayer.borderColor = PTWarmBorderColor().CGColor;
        for (CALayer *dot in _dotLayers) dot.backgroundColor = PTWarmBorderColor().CGColor;
    }];
    _trackLayer.frame = CGRectMake(left, centerY - 4, right - left, 8);
    _trackLayer.cornerRadius = 4;
    _fillLayer.frame = CGRectMake(left, centerY - 4, MAX(0, selectedX - left), 8);
    _fillLayer.cornerRadius = 4;
    for (NSInteger index = 0; index < 5; index++) {
        CALayer *dot = _dotLayers[index];
        dot.frame = CGRectMake([self xForIndex:index] - 3, centerY - 3, 6, 6);
        dot.cornerRadius = 3;
    }
    _thumbLayer.bounds = CGRectMake(0, 0, 34, 34);
    _thumbLayer.position = CGPointMake(selectedX, centerY);
    _thumbLayer.cornerRadius = 17;
    _thumbLayer.borderWidth = 0.7;
    _thumbLayer.shadowColor = NSColor.blackColor.CGColor;
    _thumbLayer.shadowOpacity = 0.12;
    _thumbLayer.shadowRadius = 5;
    _thumbLayer.shadowOffset = CGSizeMake(0, -1);
}

- (void)updateSelectionForPoint:(NSPoint)point {
    CGFloat x = point.x;
    CGFloat left = 19;
    CGFloat width = MAX(1, self.bounds.size.width - 38);
    NSInteger index = lround((x - left) / width * 4.0);
    index = MIN(4, MAX(0, index));
    self.selectedIndex = index;
}

- (void)sendDeferredActionFromIndex:(NSInteger)startIndex {
    (void)startIndex;
    NSInteger requestedIndex = self.selectedIndex;
    if (self.action && self.target) {
        // Capture the gesture value before asynchronous configuration refreshes can move the thumb.
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            PTEffortSlider *self = weakSelf;
            if (self && self.action && self.target) {
                self.submittedIndex = requestedIndex;
                [self sendAction:self.action to:self.target];
            }
        });
    }
}

- (void)handleEffortClick:(NSClickGestureRecognizer *)recognizer {
    if (recognizer.state != NSGestureRecognizerStateEnded) return;
    NSInteger startIndex = self.selectedIndex;
    [self updateSelectionForPoint:[recognizer locationInView:self]];
    [self sendDeferredActionFromIndex:startIndex];
}

- (void)handleEffortPan:(NSPanGestureRecognizer *)recognizer {
    NSPoint point = [recognizer locationInView:self];
    switch (recognizer.state) {
        case NSGestureRecognizerStateBegan:
            _trackingStartIndex = self.selectedIndex;
            [self updateSelectionForPoint:point];
            break;
        case NSGestureRecognizerStateChanged:
            [self updateSelectionForPoint:point];
            break;
        case NSGestureRecognizerStateEnded:
            [self updateSelectionForPoint:point];
            [self sendDeferredActionFromIndex:_trackingStartIndex];
            break;
        case NSGestureRecognizerStateCancelled:
        case NSGestureRecognizerStateFailed:
            self.selectedIndex = _trackingStartIndex;
            break;
        default:
            break;
    }
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsLayout:YES];
}
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
        NSColor *background = PTWarmCanvasColor();
        NSColor *border = NSColor.clearColor;
        if (self.surfaceStyle == PTAppearanceSurfaceStyleCard) {
            background = PTWarmCardColor();
            border = PTWarmBorderColor();
        } else if (self.surfaceStyle == PTAppearanceSurfaceStyleChip) {
            background = PTWarmChipColor();
            border = PTWarmBorderColor();
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
@interface PTMeterView : NSView
@property(nonatomic) CGFloat progress; // 0.0 – 1.0
@property(nonatomic, strong) NSColor *fillColor;
@end

@implementation PTMeterView {
    CALayer *_trackLayer;
    CALayer *_fillLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _trackLayer = [CALayer layer];
        _fillLayer = [CALayer layer];
        [self.layer addSublayer:_trackLayer];
        [self.layer addSublayer:_fillLayer];
        _fillColor = NSColor.controlAccentColor;
    }
    return self;
}

- (void)setProgress:(CGFloat)progress {
    _progress = MIN(1.0, MAX(0.0, progress));
    [self setNeedsLayout:YES];
}

- (void)setFillColor:(NSColor *)fillColor {
    _fillColor = fillColor;
    [self setNeedsLayout:YES];
}

- (void)layout {
    [super layout];
    CGFloat height = self.bounds.size.height;
    CGFloat radius = height / 2.0;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        _trackLayer.backgroundColor = PTWarmChipColor().CGColor;
        _fillLayer.backgroundColor = self.fillColor.CGColor;
    }];
    _trackLayer.frame = self.bounds;
    _trackLayer.cornerRadius = radius;
    CGFloat fillWidth = MAX(height, self.bounds.size.width * self.progress);
    _fillLayer.frame = CGRectMake(0, 0, self.progress > 0 ? fillWidth : 0, height);
    _fillLayer.cornerRadius = radius;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsLayout:YES];
}

@end

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

static NSString *PTCompactTokenCount(NSUInteger tokens) {
    if (tokens >= 999500) return [NSString stringWithFormat:@"%.1fM", tokens / 1000000.0];
    if (tokens >= 1000) return [NSString stringWithFormat:@"%.0fK", tokens / 1000.0];
    return [NSString stringWithFormat:@"%lu", (unsigned long)tokens];
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

static NSString *PTMarkdownQuote(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return nil;
    NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    if ([[normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] == 0) {
        return nil;
    }
    normalized = [normalized stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *quoted = [NSMutableArray array];
    for (NSString *line in [normalized componentsSeparatedByString:@"\n"]) {
        [quoted addObject:[@"> " stringByAppendingString:line]];
    }
    // 末尾不加空的 >，直接用换行符结束
    return [[NSString stringWithFormat:@"> Attached context:\n%@\n\n",
        [quoted componentsJoinedByString:@"\n"]] copy];
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

static NSArray<NSString *> *PTImagesFromMessageContent(id content) {
    if (![content isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *images = [NSMutableArray array];
    for (NSDictionary *block in content) {
        if (![block isKindOfClass:NSDictionary.class] || ![block[@"type"] isEqual:@"image"]) continue;
        NSDictionary *source = block[@"source"];
        if (![source isKindOfClass:NSDictionary.class]) continue;
        if ([source[@"type"] isEqual:@"base64"] && [source[@"data"] isKindOfClass:NSString.class]) {
            [images addObject:[NSString stringWithFormat:@"data:%@;base64,%@",
                source[@"media_type"], source[@"data"]]];
        } else if ([source[@"type"] isEqual:@"url"] && [source[@"url"] isKindOfClass:NSString.class]) {
            [images addObject:source[@"url"]];
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

    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
    NSString *directory = nil;
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
    if (directory.length > 1) [directories addObject:directory.stringByStandardizingPath];
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

static NSString *const PTSessionProjectCollapsedDefaultsKey =
    @"PTCollapsedSessionProjectPaths";
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

static PTSessionInfo *PTParseSessionData(
    NSData *data,
    NSString *filePath,
    NSDate *modifiedAt,
    PTSessionInfo *baseSession,
    BOOL includeMessages
) {
    if (!data) return nil;
    // Claude 还在往这个文件追加写的时候，文件末尾可能截在一个多字节 UTF-8
    // 字符的中间，导致整段 initWithData:encoding: 直接返回 nil，
    // 让这个正在活跃的会话从侧栏"消失"一下又"回来"，一直闪烁。
    // 按行切开后逐行解码，坏掉的只是最后半行，不会拖垮整个 session。
    NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!source) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        NSUInteger lineStart = 0;
        const char *bytes = data.bytes;
        NSUInteger length = data.length;
        for (NSUInteger index = 0; index < length; index++) {
            if (bytes[index] != '\n') continue;
            NSData *lineData = [data subdataWithRange:NSMakeRange(lineStart, index - lineStart)];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line) [lines addObject:line];
            lineStart = index + 1;
        }
        if (lines.count == 0) return nil;
        source = [lines componentsJoinedByString:@"\n"];
    }

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

    for (NSString *line in [source componentsSeparatedByString:@"\n"]) { @autoreleasepool {
        if (line.length < 2) continue;
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
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
            NSString *model = message[@"model"];
            if ([model isEqual:@"<synthetic>"]) continue;
            NSDictionary *usage = message[@"usage"];
            NSString *usageKey = object[@"requestId"] ?: message[@"id"];
            if ([usage isKindOfClass:NSDictionary.class] && usageKey.length > 0 &&
                ![usageMessageKeys containsObject:usageKey]) {
                [usageMessageKeys addObject:usageKey];
                BOOL supported = NO;
                NSDate *pricingDate = PTDateFromClaudeAPIString(object[@"timestamp"]) ?: NSDate.date;
                double cost = PTAPIEquivalentCostForUsage(model ?: @"", usage, pricingDate, &supported);
                if (supported) {
                    session.apiEquivalentCostUSD += cost;
                    session.apiCostAvailable = YES;
                    NSString *modelKey = model.length ? model : @"unknown";
                    NSMutableDictionary *entry = modelBreakdown[modelKey];
                    if (!entry) {
                        entry = [NSMutableDictionary dictionaryWithDictionary:@{
                            @"input": @0, @"output": @0, @"cacheRead": @0, @"cacheWrite": @0, @"cost": @0.0
                        }];
                        modelBreakdown[modelKey] = entry;
                    }
                    entry[@"input"] = @([entry[@"input"] unsignedLongLongValue] + [usage[@"input_tokens"] unsignedLongLongValue]);
                    entry[@"output"] = @([entry[@"output"] unsignedLongLongValue] + [usage[@"output_tokens"] unsignedLongLongValue]);
                    entry[@"cacheRead"] = @([entry[@"cacheRead"] unsignedLongLongValue] + [usage[@"cache_read_input_tokens"] unsignedLongLongValue]);
                    entry[@"cacheWrite"] = @([entry[@"cacheWrite"] unsignedLongLongValue] + [usage[@"cache_creation_input_tokens"] unsignedLongLongValue]);
                    entry[@"cost"] = @([entry[@"cost"] doubleValue] + cost);
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
                    [messages addObject:@{
                        @"messageKey": key,
                        @"text": text,
                        @"timestamp": object[@"timestamp"] ?: @"",
                        @"model": model ?: @"Claude",
                        @"role": @"assistant"
                    }];
                    blockIndex++;
                    continue;
                }

                NSDictionary *event = PTEventFromAssistantBlock(
                    block, key, object[@"timestamp"] ?: @"", model ?: @"Claude");
                if (event) {
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
@property(nonatomic, readonly) BOOL responding;
@property(nonatomic, readonly) NSString *sessionID;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) NSString *lastSendError;
- (void)connectToSession:(PTSessionInfo *)session;
- (void)connectToSession:(PTSessionInfo *)session completion:(void (^)(BOOL))completion;
- (void)refreshUsage;
- (void)refreshSettingsWithCompletion:(void (^)(BOOL))completion;
- (void)startNewSession:(PTSessionInfo *)session prompt:(NSString *)prompt;
- (void)startNewSessionInDirectory:(NSString *)directory;
- (BOOL)sendMessage:(NSString *)message;
- (BOOL)sendMessage:(NSString *)message withImagePNGs:(NSArray<NSData *> *)imagePNGs;
- (void)submitMessage:(NSString *)message withImagePNGs:(NSArray<NSData *> *)imagePNGs
          completion:(void (^)(BOOL))completion;
- (BOOL)sendEscape;
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
    NSString *_streamMessageID;
    NSString *_streamModel;
    NSNumber *_streamBlockIndex;
    BOOL _responding;
    NSMutableSet<NSString *> *_workingMessageIDs;
    NSString *_activeWorkID;
    BOOL _streamNotificationScheduled;
    NSUInteger _streamRevision;
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
        _workingMessageIDs = [NSMutableSet set];
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

- (NSDictionary *)streamPayload {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSString *key in _streamOrder) if (_streamRecords[key]) [messages addObject:_streamRecords[key]];
    return @{@"sessionId": _sessionID ?: @"", @"messages": messages,
        @"questionUpdates": _streamQuestions.allValues,
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
    BOOL changed = NO;
    for (NSDictionary *message in messages) {
        if (message[@"messageKey"]) [keys addObject:message[@"messageKey"]];
        if ([message[@"kind"] isEqual:@"question"] && [message[@"toolUseId"] length]) {
            NSString *toolID = message[@"toolUseId"];
            if (([message[@"answered"] boolValue] || !_streamQuestions[toolID]) && ![message isEqual:_streamQuestions[toolID]]) {
                _streamQuestions[toolID] = [message copy];
                changed = YES;
            }
        }
    }
    _persistedStreamKeys = keys;
    for (NSString *identity in _streamOrder.array) {
        NSDictionary *record = _streamRecords[identity];
        BOOL mergedQuestionResult = ![record[@"kind"] isEqual:@"question"] &&
            [record[@"toolUseId"] length] && _streamQuestions[record[@"toolUseId"]];
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
        NSArray<NSString *> *images = PTImagesFromMessageContent(message[@"content"]);
        if ((text.length || images.count) && ![frame[@"isMeta"] boolValue] && !_submittedCommands[uuid]) {
            NSString *key = [uuid stringByAppendingString:@":user"];
            [self putStreamRecord:@{@"role": @"user", @"text": text, @"images": images, @"messageKey": key} identity:key];
        }
        if ([message[@"content"] isKindOfClass:NSArray.class]) {
            [message[@"content"] enumerateObjectsUsingBlock:^(NSDictionary *block, NSUInteger index, BOOL *stop) {
                (void)stop;
                if (![block[@"type"] isEqual:@"tool_result"]) return;
                NSString *toolID = block[@"tool_use_id"];
                NSMutableDictionary *question = [self->_streamQuestions[toolID ?: @""] mutableCopy];
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

- (void)refreshSettings {
    [self refreshSettingsWithCompletion:nil];
}

- (void)refreshSettingsWithCompletion:(void (^)(BOOL))completion {
    __weak typeof(self) weakSelf = self;
    [self queryControl:@{@"subtype": @"get_settings"} completion:^(NSDictionary *body, NSString *error) {
        PTClaudeBridge *self = weakSelf;
        if (!self) return;
        NSDictionary *applied = [body[@"applied"] isKindOfClass:NSDictionary.class] ? body[@"applied"] : nil;
        BOOL received = !error && [applied[@"model"] isKindOfClass:NSString.class] &&
            ([applied[@"effort"] isKindOfClass:NSString.class] || applied[@"effort"] == NSNull.null);
        self->_currentModel = received ? applied[@"model"] : nil;
        // An explicit null means Claude has no named effective effort, not the previously selected level.
        self->_currentEffort = received ? ([applied[@"effort"] isKindOfClass:NSString.class] ? applied[@"effort"] : @"") : nil;
        if (!received) [self reportError:error ?: PTL(@"未读取到 Claude 当前配置", @"Could not read Claude's current settings")];
        if (self.modelChanged) self.modelChanged();
        if (completion) completion(received);
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
        if ([model isKindOfClass:NSString.class] && model.length) {
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
            [self startProcessInDirectory:cwd resume:resume];
        });
    });
}

- (void)startProcessInDirectory:(NSString *)cwd resume:(BOOL)resume {
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
    _task.arguments = @[@"-lic", @"export TZ=UTC\nexec \"$(whence -p claude)\" \"$@\"",
        @"PrettyTerm", @"--allow-dangerously-skip-permissions", @"--permission-mode", launchMode,
        @"--permission-prompt-tool", @"stdio", @"--print",
        @"--input-format", @"stream-json", @"--output-format", @"stream-json",
        @"--verbose", @"--replay-user-messages", @"--include-partial-messages",
        resume ? @"--resume" : @"--session-id", _sessionID];
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
            } else if (control[@"model"] || control[@"settings"][@"effortLevel"]) {
                [self refreshSettingsWithCompletion:^(BOOL received) {
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
    _persistedStreamKeys = nil;
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

@interface PTSessionCellView : NSTableCellView
@property(nonatomic, strong) NSView *activityDot;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
@property(nonatomic, strong) NSTextField *timeLabel;
- (void)configure:(PTSessionInfo *)session;
@end

@interface PTSessionProjectCellView : NSTableCellView
@property(nonatomic, strong) PTAnimatedButton *clickTarget;
@property(nonatomic, strong) NSImageView *folderImageView;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *countLabel;
@property(nonatomic, strong) NSImageView *disclosureImageView;
- (void)configureWithProjectKey:(NSString *)projectKey
                          title:(NSString *)title
                   sessionCount:(NSUInteger)sessionCount
                      collapsed:(BOOL)collapsed
                         target:(id)target
                         action:(SEL)action;
@end

@interface PTSessionRowView : NSTableRowView
@end

@implementation PTSessionRowView
- (void)drawSelectionInRect:(NSRect)dirtyRect {
    if (!self.selected) return;
    NSRect selectionRect = NSInsetRect(self.bounds, 5, 2);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:11 yRadius:11];
    [[NSColor colorWithSRGBRed:0.16 green:0.62 blue:0.66 alpha:0.14] setFill];
    [path fill];
    [[NSColor colorWithSRGBRed:0.16 green:0.62 blue:0.66 alpha:0.24] setStroke];
    path.lineWidth = 1;
    [path stroke];
}
@end

@implementation PTSessionProjectCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    self.clickTarget = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    self.clickTarget.translatesAutoresizingMaskIntoConstraints = NO;
    self.clickTarget.title = @"";
    self.clickTarget.cornerRadius = 10;
    self.clickTarget.fillColor = NSColor.clearColor;
    self.clickTarget.hoverFillColor = PTWarmChipColor();
    self.clickTarget.pressedFillColor = PTWarmBorderColor();
    [self addSubview:self.clickTarget];

    self.folderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.folderImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderImageView.imageScaling = NSImageScaleProportionallyDown;
    self.folderImageView.contentTintColor = NSColor.secondaryLabelColor;
    [self addSubview:self.folderImageView];

    self.titleLabel = [NSTextField labelWithString:@""];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self addSubview:self.titleLabel];

    self.countLabel = [NSTextField labelWithString:@""];
    self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.countLabel.font = [NSFont monospacedDigitSystemFontOfSize:9.5
                                                           weight:NSFontWeightMedium];
    self.countLabel.textColor = NSColor.tertiaryLabelColor;
    self.countLabel.alignment = NSTextAlignmentRight;
    [self addSubview:self.countLabel];

    self.disclosureImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.disclosureImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.disclosureImageView.imageScaling = NSImageScaleProportionallyDown;
    self.disclosureImageView.contentTintColor = PTWarmAccentColor();
    [self addSubview:self.disclosureImageView];

    [NSLayoutConstraint activateConstraints:@[
        [self.clickTarget.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
        [self.clickTarget.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
        [self.clickTarget.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
        [self.clickTarget.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
        [self.folderImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.folderImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.folderImageView.widthAnchor constraintEqualToConstant:17],
        [self.folderImageView.heightAnchor constraintEqualToConstant:17],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.folderImageView.trailingAnchor constant:8],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.countLabel.leadingAnchor constant:-6],
        [self.disclosureImageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-13],
        [self.disclosureImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.disclosureImageView.widthAnchor constraintEqualToConstant:11],
        [self.disclosureImageView.heightAnchor constraintEqualToConstant:11],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:self.disclosureImageView.leadingAnchor constant:-6],
        [self.countLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.countLabel.widthAnchor constraintGreaterThanOrEqualToConstant:18]
    ]];
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    return NSPointInRect(point, self.bounds) ? self.clickTarget : nil;
}

- (void)configureWithProjectKey:(NSString *)projectKey
                          title:(NSString *)title
                   sessionCount:(NSUInteger)sessionCount
                      collapsed:(BOOL)collapsed
                         target:(id)target
                         action:(SEL)action {
    self.titleLabel.stringValue = title ?: @"";
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)sessionCount];
    self.clickTarget.target = target;
    self.clickTarget.action = action;
    self.clickTarget.identifier = projectKey;
    self.clickTarget.toolTip = collapsed
        ? PTL(@"展开项目会话", @"Expand project conversations")
        : PTL(@"折叠项目会话", @"Collapse project conversations");
    self.folderImageView.image = [NSImage imageWithSystemSymbolName:@"folder"
                                          accessibilityDescription:nil];
    self.disclosureImageView.image = [NSImage
        imageWithSystemSymbolName:(collapsed ? @"chevron.right" : @"chevron.down")
        accessibilityDescription:nil];
}
@end

@implementation PTSessionCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.activityDot = [[NSView alloc] initWithFrame:NSZeroRect];
        self.activityDot.translatesAutoresizingMaskIntoConstraints = NO;
        self.activityDot.wantsLayer = YES;
        self.activityDot.layer.cornerRadius = 4.5;
        [self addSubview:self.activityDot];

        self.titleLabel = [NSTextField labelWithString:@""];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:self.titleLabel];

        self.detailLabel = [NSTextField labelWithString:@""];
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
        self.detailLabel.textColor = NSColor.secondaryLabelColor;
        self.detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:self.detailLabel];

        self.timeLabel = [NSTextField labelWithString:@""];
        self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.timeLabel.font = [NSFont monospacedDigitSystemFontOfSize:9.5 weight:NSFontWeightRegular];
        self.timeLabel.textColor = NSColor.tertiaryLabelColor;
        self.timeLabel.alignment = NSTextAlignmentRight;
        [self addSubview:self.timeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.activityDot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [self.activityDot.topAnchor constraintEqualToAnchor:self.topAnchor constant:17],
            [self.activityDot.widthAnchor constraintEqualToConstant:9],
            [self.activityDot.heightAnchor constraintEqualToConstant:9],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.activityDot.trailingAnchor constant:9],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.timeLabel.leadingAnchor constant:-6],
            [self.timeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.timeLabel.widthAnchor constraintLessThanOrEqualToConstant:58],
            [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:5]
        ]];
    }
    return self;
}

- (void)configure:(PTSessionInfo *)session {
    self.titleLabel.stringValue = session.title ?: PTL(@"未命名会话", @"Untitled conversation");
    NSString *folder = session.cwd.lastPathComponent.length ? session.cwd.lastPathComponent : session.cwd;
    // folder 为 @"" 时不是 nil，?: 不会生效，得显式判断 length 才能落到"未知目录"
    self.detailLabel.stringValue = [NSString stringWithFormat:PTL(@"%@ · %lu 轮对话", @"%@ · %lu turns"),
        folder.length ? folder : PTL(@"未知目录", @"Unknown directory"),
        (unsigned long)PTSessionTurnCount(session)];
    NSTimeInterval age = -session.modifiedAt.timeIntervalSinceNow;
    BOOL active = age < 600;
    self.activityDot.layer.backgroundColor =
        (active ? PTColor(0.16, 0.76, 0.48) : PTColor(0.58, 0.61, 0.66)).CGColor;
    self.activityDot.layer.shadowColor = active ? PTColor(0.16, 0.76, 0.48).CGColor : nil;
    self.activityDot.layer.shadowOpacity = active ? 0.28 : 0;
    self.activityDot.layer.shadowRadius = active ? 4 : 0;
    self.activityDot.layer.shadowOffset = CGSizeZero;
    if (age < 60) self.timeLabel.stringValue = PTL(@"刚刚", @"now");
    else if (age < 3600) self.timeLabel.stringValue = [NSString stringWithFormat:PTL(@"%ld分", @"%ldm"), (long)(age / 60)];
    else if (age < 86400) self.timeLabel.stringValue = [NSString stringWithFormat:PTL(@"%ld时", @"%ldh"), (long)(age / 3600)];
    else self.timeLabel.stringValue = [NSString stringWithFormat:PTL(@"%ld天", @"%ldd"), (long)(age / 86400)];
}
@end

// An in-window completion list keeps the editor focused while the query changes.
@interface PTCommandRowView : NSView
@property(nonatomic, copy) NSDictionary *command;
@property(nonatomic) BOOL highlighted;
@end

@implementation PTCommandRowView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (_highlighted) {
        [NSColor.quaternaryLabelColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 3, 2) xRadius:11 yRadius:11] fill];
    }
    NSImage *icon = [NSImage imageWithSystemSymbolName:_command[@"icon"] accessibilityDescription:nil];
    icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.secondaryLabelColor]]];
    [icon drawInRect:NSMakeRect(14, 12, 18, 18) fromRect:NSZeroRect
        operation:NSCompositingOperationSourceOver fraction:0.65 respectFlipped:YES hints:nil];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *titleStyle = @{NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.labelColor, NSParagraphStyleAttributeName: style};
    NSString *title = _command[@"title"];
    CGFloat titleWidth = MIN([title sizeWithAttributes:titleStyle].width + 2, MAX(80, self.bounds.size.width * 0.40));
    [title drawInRect:NSMakeRect(43, 11, titleWidth, 22) withAttributes:titleStyle];
    CGFloat descriptionX = 43 + titleWidth + 12;
    [_command[@"detail"] drawInRect:NSMakeRect(descriptionX, 12, MAX(0, self.bounds.size.width - descriptionX - 14), 21)
        withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor, NSParagraphStyleAttributeName: style}];
}
@end

@interface PTCommandPaletteView : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *commands;
@property(nonatomic, copy) void (^chooseCommand)(NSDictionary *command);
- (void)moveSelection:(NSInteger)offset;
- (BOOL)chooseSelection;
@end

@implementation PTCommandPaletteView {
    NSScrollView *_scroll;
    NSTableView *_table;
    NSTextField *_emptyLabel;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 18;
        self.layer.borderWidth = 1;
        self.layer.masksToBounds = YES;
        _scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _scroll.drawsBackground = NO;
        _scroll.hasVerticalScroller = YES;
        _scroll.autohidesScrollers = YES;
        _table = [[NSTableView alloc] initWithFrame:NSZeroRect];
        _table.autoresizingMask = NSViewWidthSizable;
        _table.headerView = nil;
        _table.backgroundColor = NSColor.clearColor;
        _table.rowHeight = 42;
        _table.intercellSpacing = NSZeroSize;
        _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
        _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"command"];
        column.minWidth = 0;
        [_table addTableColumn:column];
        _table.dataSource = self;
        _table.delegate = self;
        _table.target = self;
        _table.action = @selector(chooseSelection);
        _scroll.documentView = _table;
        [self addSubview:_scroll];
        _emptyLabel = [NSTextField labelWithString:PTL(@"没有匹配的指令", @"No matching commands")];
        _emptyLabel.textColor = NSColor.secondaryLabelColor;
        _emptyLabel.alignment = NSTextAlignmentCenter;
        [self addSubview:_emptyLabel];
        [self updateLayer];
    }
    return self;
}
- (void)updateLayer {
    self.layer.backgroundColor = PTWarmCardColor().CGColor;
    self.layer.borderColor = PTWarmBorderColor().CGColor;
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self updateLayer]; [_table reloadData]; }
- (void)layout {
    [super layout];
    _scroll.frame = NSInsetRect(self.bounds, 6, 6);
    _table.frame = NSMakeRect(0, 0, _scroll.contentSize.width, MAX(_scroll.contentSize.height, _commands.count * 42));
    _table.tableColumns.firstObject.width = _scroll.contentSize.width;
    _emptyLabel.frame = NSMakeRect(12, MAX(0, (self.bounds.size.height - 20) / 2), MAX(0, self.bounds.size.width - 24), 20);
}
- (void)setCommands:(NSArray<NSDictionary *> *)commands {
    _commands = [commands copy];
    [_table reloadData];
    _emptyLabel.hidden = commands.count != 0;
    if (commands.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [_table scrollRowToVisible:0];
    }
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return _commands.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    PTCommandRowView *view = [tableView makeViewWithIdentifier:@"commandRow" owner:self];
    if (!view) { view = [PTCommandRowView new]; view.identifier = @"commandRow"; }
    view.command = _commands[row];
    view.highlighted = tableView.selectedRow == row;
    view.toolTip = [NSString stringWithFormat:@"/%@\n%@", view.command[@"name"], view.command[@"detail"]];
    [view setNeedsDisplay:YES];
    return view;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSRange rows = [_table rowsInRect:_table.visibleRect];
    if (rows.location == NSNotFound) return;
    for (NSUInteger row = rows.location; row < NSMaxRange(rows); row++) {
        PTCommandRowView *view = [_table viewAtColumn:0 row:row makeIfNecessary:NO];
        view.highlighted = _table.selectedRow == (NSInteger)row;
        [view setNeedsDisplay:YES];
    }
}
- (void)moveSelection:(NSInteger)offset {
    if (!_commands.count) return;
    NSInteger row = (_table.selectedRow + offset + (NSInteger)_commands.count) % (NSInteger)_commands.count;
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_table scrollRowToVisible:row];
}
- (BOOL)chooseSelection {
    NSInteger row = _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_commands.count) return NO;
    if (_chooseCommand) _chooseCommand(_commands[row]);
    return YES;
}
@end

@interface PTComposerTextView : NSTextView
@property(nonatomic, copy) dispatch_block_t submitHandler;
@property(nonatomic, copy) dispatch_block_t commandMenuHandler;
@property(nonatomic, copy) BOOL (^commandKeyHandler)(NSEvent *event);
@property(nonatomic, copy) BOOL (^imagePasteHandler)(NSPasteboard *pasteboard);
@property(nonatomic, copy) BOOL (^fileDropHandler)(NSArray<NSURL *> *urls);
@property(nonatomic, copy) NSString *placeholderText;
- (void)clearAfterSuccessfulSubmissionMatchingText:(NSString *)submittedText;
@end

@implementation PTComposerTextView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    return self;
}

- (void)setPlaceholderText:(NSString *)placeholderText {
    _placeholderText = [placeholderText copy];
    [self setNeedsDisplay:YES];
}

- (void)setString:(NSString *)string {
    [super setString:string];
    [self setNeedsDisplay:YES];
}

- (void)didChangeText {
    [super didChangeText];
    [self setNeedsDisplay:YES];
    if (!self.hasMarkedText && self.commandMenuHandler) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            PTComposerTextView *self = weakSelf;
            if (self && !self.hasMarkedText && self.commandMenuHandler) self.commandMenuHandler();
        });
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (self.string.length > 0 || self.placeholderText.length == 0) return;
    NSDictionary *attributes = @{
        NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:14],
        NSForegroundColorAttributeName: NSColor.placeholderTextColor
    };
    NSPoint point = NSMakePoint(self.textContainerInset.width + 1,
        self.textContainerInset.height + 1);
    [self.placeholderText drawAtPoint:point withAttributes:attributes];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    BOOL commandPaste =
        (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) ==
            NSEventModifierFlagCommand &&
        (event.keyCode == 9 ||
         [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"v"]);
    if (commandPaste) {
        // performKeyEquivalent: 会沿整个视图树探测；若不核对 firstResponder，
        // 即使老师正在检查器路径框里粘贴，消息编辑器也会抢先吞掉 ⌘V。
        if (self.window.firstResponder != self) return NO;
        [self paste:self];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    if (!self.hasMarkedText && self.commandKeyHandler && self.commandKeyHandler(event)) return;
    BOOL commandPaste =
        (event.modifierFlags & NSEventModifierFlagCommand) != 0 &&
        (event.keyCode == 9 ||
         [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"v"]);
    if (commandPaste) {
        [self paste:self];
        return;
    }
    PTComposerKeyAction action = PTComposerActionForKey(
        event.keyCode,
        (event.modifierFlags & NSEventModifierFlagCommand) != 0,
        (event.modifierFlags & NSEventModifierFlagShift) != 0,
        self.hasMarkedText
    );
    if (action == PTComposerKeyActionSubmit && self.submitHandler) {
        self.submitHandler();
        return;
    }
    if (action == PTComposerKeyActionInsertNewline) {
        [self insertNewline:nil];
        return;
    }
    [super keyDown:event];
}

- (void)paste:(id)sender {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    if (self.imagePasteHandler && self.imagePasteHandler(pasteboard)) return;
    [super paste:sender];
}

- (NSArray<NSURL *> *)draggedFileURLs:(id<NSDraggingInfo>)sender {
    NSDictionary *options = @{NSPasteboardURLReadingFileURLsOnlyKey: @YES};
    return [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:options] ?: @[];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return self.editable && self.fileDropHandler && [self draggedFileURLs:sender].count > 0
        ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [self draggedFileURLs:sender];
    return self.editable && urls.count > 0 && self.fileDropHandler && self.fileDropHandler(urls);
}

- (void)clearAfterSuccessfulSubmissionMatchingText:(NSString *)submittedText {
    // NSTextView 的 string setter 在 keyDown: 尚未退出时偶尔会被输入系统的同一轮
    // 编辑事务覆盖回来。走 shouldChange/textStorage/didChangeText 的正式编辑链，
    // 并只清除仍与已发送快照一致的内容，保留老师紧接着输入的新文字。
    if (![self.string isEqualToString:submittedText ?: @""]) return;
    NSRange wholeRange = NSMakeRange(0, self.string.length);
    if (![self shouldChangeTextInRange:wholeRange replacementString:@""]) return;
    [self.textStorage beginEditing];
    [self.textStorage replaceCharactersInRange:wholeRange withString:@""];
    [self.textStorage endEditing];
    [self setSelectedRange:NSMakeRange(0, 0)];
    [self didChangeText];
    [self setNeedsDisplay:YES];
}
@end

@interface PTWorkspaceTab : NSObject
@property(nonatomic, copy) NSString *commandOutput;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy) NSString *draft;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, strong) PTClaudeBridge *bridge;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *pendingImages;
@property(nonatomic, strong) NSMutableArray<NSString *> *pendingFiles;
@property(nonatomic) BOOL connecting;
@end

@implementation PTWorkspaceTab
@end

@interface PTAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSplitViewDelegate, NSMenuDelegate, NSTextFieldDelegate>
- (void)updateWorkspaceTabBar;
- (void)syncFullSessionIDs;
- (PTSessionInfo *)sessionWithID:(NSString *)sessionID;
- (CGFloat)adaptiveInspectorWidth;
- (void)applyAdaptiveInspectorWidth;
- (void)updateWindowMaximumSize;
- (BOOL)shouldFloatInspector;
- (void)updateInspectorPresentation;
- (void)dockInspector;
- (void)floatInspector;
@end

@implementation PTAppDelegate {
    NSWindow *_window;
    PTSessionStore *_store;
    PTClaudeBridge *_bridge;
    NSMutableArray<PTWorkspaceTab *> *_workspaceTabs;
    PTWorkspaceTab *_activeWorkspaceTab;
    NSView *_homeView;
    NSTextField *_homeTitleLabel;
    NSTextField *_homeStatusLabel;
    PTWarmPopUpButton *_homeProjectPicker;
    PTComposerTextView *_homePromptTextView;
    NSString *_homeProjectPath;
    BOOL _homeVisible;
    BOOL _applyingSessions;
    PTClaudeBridge *_homeStartingBridge;
    NSString *_homeBlankSessionDirectory;
    NSMutableDictionary<NSString *, PTSessionInfo *> *_newSessionsAwaitingTranscript;
    NSMutableDictionary<NSString *, PTClaudeBridge *> *_renameConnections;
    NSMutableDictionary<NSString *, NSString *> *_pendingRenameTitles;
    NSString *_homeStartingSessionID;
    NSString *_homeSubmittedPrompt;
    NSScrollView *_workspaceTabScroll;
    NSStackView *_workspaceTabStack;
    NSArray<PTSessionInfo *> *_sessions;
    NSArray<NSDictionary *> *_sessionSidebarRows;
    NSMutableSet<NSString *> *_collapsedSessionProjectPaths;
    PTSessionInfo *_selectedSession;
    NSTableView *_sessionTable;
    WKWebView *_conversationView;
    NSTextField *_conversationTitle;
    NSTextField *_conversationDetail;
    NSTextField *_statusLabel;
    NSTextField *_contextLabel;
    NSTextField *_quotaLabel;
    NSPopUpButton *_languagePicker;
    NSProgressIndicator *_contextBar;
    NSPopUpButton *_modelPicker;
    PTComposerDropSurfaceView *_composerSurface;
    PTAnimatedButton *_composerModelButton;
    PTAnimatedButton *_composerEffortButton;
    NSPopover *_composerOptionsPopover;
    NSStackView *_composerOptionsStack;
    PTEffortSlider *_composerEffortSlider;
    NSTextField *_composerEffortPopoverTitle;
    NSString *_selectedComposerModelID;
    NSString *_selectedComposerEffort;
    NSString *_composerConfigurationPage;
    PTComposerTextView *_composerTextView;
    NSTextField *_composerTargetLabel;
    NSButton *_imageButton;
    NSScrollView *_imagePreviewScroll;
    NSStackView *_imagePreviewStack;
    NSLayoutConstraint *_composerHeightConstraint;
    NSLayoutConstraint *_imagePreviewHeightConstraint;
    NSMutableArray<NSDictionary *> *_pendingImages;
    NSMutableArray<NSString *> *_pendingFiles;
    NSMutableSet<NSString *> *_temporaryImagePaths;
    NSButton *_connectButton;
    NSButton *_floatingButton;
    NSMenuItem *_floatingMenuItem;
    NSButton *_remoteButton;
    NSButton *_compactButton;
    NSButton *_sendButton;
    NSButton *_refreshButton;
    NSTimer *_refreshTimer;
    NSTimer *_usageRefreshTimer;
    NSString *_planUsageSessionID;
    BOOL _planUsageAvailable;
    double _fiveHourPercent;
    double _sevenDayPercent;
    NSDate *_fiveHourResetAt;
    NSDate *_sevenDayResetAt;
    NSString *_planUsageError;
    BOOL _webReady;
    NSPanel *_floatingPanel;
    WKWebView *_floatingConversationView;
    PTComposerDropSurfaceView *_floatingComposerSurface;
    PTComposerTextView *_floatingComposerTextView;
    NSTextField *_floatingComposerLabel;
    NSButton *_floatingImageButton;
    NSScrollView *_floatingImagePreviewScroll;
    NSStackView *_floatingImagePreviewStack;
    NSLayoutConstraint *_floatingComposerHeightConstraint;
    NSLayoutConstraint *_floatingImagePreviewHeightConstraint;
    NSMutableArray<NSDictionary *> *_floatingPendingImages;
    NSMutableArray<NSString *> *_floatingPendingFiles;
    PTAnimatedButton *_floatingEffortButton;
    NSButton *_floatingSendButton;
    NSString *_floatingSessionID;
    BOOL _floatingWebReady;
    BOOL _floatingRenderInFlight;
    PTSessionInfo *_pendingFloatingSession;
    NSString *_floatingRenderedSessionID;
    NSDate *_floatingRenderedModifiedAt;
    NSUInteger _floatingRenderedMessageCount;
    NSUInteger _floatingRenderGeneration;
    NSString *_sessionListSignature;
    NSString *_manualRefreshSessionID;
    NSString *_renderedSessionID;
    NSUInteger _renderedMessageCount;
    NSDate *_renderedModifiedAt;
    BOOL _renderInFlight;
    PTSessionInfo *_pendingRenderSession;
    NSSplitView *_splitView;
    NSSplitView *_workspaceSplitView;
    NSView *_conversationPane;
    NSView *_toolWorkspaceView;
    NSView *_toolContentView;
    NSSplitView *_toolContentSplitView;
    NSView *_toolPageContainerView;
    NSStackView *_toolTabStack;
    NSButton *_toolReviewRefreshButton;
    NSButton *_fileTreeToggleButton;
    NSLayoutConstraint *_toolWorkspaceWidthConstraint;
    CGFloat _toolWorkspaceWidthBeforeCollapse;
    NSUInteger _toolWorkspaceAnimationGeneration;
    NSView *_fileTreeView;
    NSOutlineView *_fileOutlineView;
    NSSearchField *_fileTreeSearchField;
    NSButton *_fileTreeRootButton;
    NSLayoutConstraint *_fileTreeWidthConstraint;
    CGFloat _fileTreeWidthBeforeCollapse;
    NSUInteger _fileTreeAnimationGeneration;
    BOOL _fileTreeExpanded;
    NSURL *_fileTreeRootURL;
    BOOL _fileTreeRootManuallySelected;
    NSString *_fileTreeRootSessionID;
    NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *_fileTreeChildrenByPath;
    WKWebView *_filePreviewWebView;
    BOOL _filePreviewWebReady;
    NSDictionary<NSString *, NSString *> *_activeFilePreviewPayload;
    NSString *_activeToolPageKind;
    BOOL _reviewToolPageOpen;
    BOOL _fileToolPageOpen;
    NSButton *_fileWorkspaceButton;
    NSView *_inspectorView;
    NSView *_inspectorCard;
    NSButton *_sidePanelToggleButton;
    BOOL _restoreInspectorAfterTools;
    BOOL _inspectorExpanded;
    BOOL _inspectorFloating;
    BOOL _updatingInspectorPresentation;
    NSView *_workspaceRootView;
    NSRect _inspectorFloatingFrame;
    BOOL _hasInspectorFloatingFrame;
    NSLayoutConstraint *_sidebarWidthConstraint;
    NSLayoutConstraint *_inspectorWidthConstraint;
    CGFloat _inspectorWidthBeforeCollapse;
    NSUInteger _inspectorAnimationGeneration;
    BOOL _committingSplitWidths;
    NSStackView *_changedFilesStack;
    NSArray<NSDictionary *> *_renderedChangedFiles;
    NSDictionary<NSString *, PTAnimatedButton *> *_changedFileButtonsByPath;
    NSTextField *_inspectorConnectionLabel;
    NSTextField *_inspectorContextLabel;
    NSTextField *_inspectorContextPercentLabel;
    PTMeterView *_inspectorContextMeter;
    NSStackView *_inspectorContextDetailStack;
    NSButton *_contextDisclosureButton;
    BOOL _contextDetailExpanded;
    NSTextField *_inspectorFiveHourPercentLabel;
    PTMeterView *_inspectorFiveHourMeter;
    NSTextField *_inspectorFiveHourCaption;
    NSTextField *_inspectorSevenDayPercentLabel;
    PTMeterView *_inspectorSevenDayMeter;
    NSTextField *_inspectorSevenDayCaption;
    NSTextField *_inspectorCostHeadline;
    NSTextField *_inspectorCostChangesPill;
    NSStackView *_inspectorCostDetailStack;
    NSButton *_costDisclosureButton;
    BOOL _costDetailExpanded;
    NSPopUpButton *_gitDirectoryPicker;
    NSButton *_removeGitDirectoryButton;
    NSTextField *_gitDirectoryInput;
    NSTextField *_gitDirectoryHintLabel;
    NSButton *_gitDiffToggleButton;
    NSButton *_gitDiffRefreshButton;
    NSButton *_gitPublishButton;
    NSProgressIndicator *_gitDiffProgress;
    NSScrollView *_gitDiffScroll;
    NSTextView *_gitDiffTextView;
    NSMutableArray<NSString *> *_gitDirectoryPaths;
    NSMutableSet<NSString *> *_suppressedGitDirectoryPaths;
    NSString *_gitObservedDirectory;
    BOOL _gitDiffExpanded;
    BOOL _gitReviewShowsTranscriptEdits;
    NSArray<NSDictionary *> *_transcriptEditReviewEvents;
    BOOL _gitDirectoryManuallySelected;
    NSUInteger _gitDiffGeneration;
    NSPopover *_gitActionPopover;
    NSTextField *_gitActionBranchLabel;
    NSTextField *_gitCommitMessageField;
    NSButton *_gitIncludeUnstagedButton;
    NSButton *_gitCommitButton;
    NSButton *_gitCommitAndPushButton;
    NSButton *_gitPushButton;
    NSTextField *_gitActionStatusLabel;
    NSProgressIndicator *_gitActionProgress;
    BOOL _gitActionInFlight;
    NSTextField *_bottomStatusLabel;
    NSButton *_inspectorToggleButton;
    NSStackView *_tasksStack;
    NSArray<NSDictionary *> *_renderedTasks;
    NSArray<NSDictionary *> *_renderedContextBreakdown;
    NSDictionary<NSString *, NSDictionary *> *_renderedCostBreakdown;
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
    NSPopover *_commandResultPopover;
    PTComposerTextView *_commandMenuComposer;
    PTCommandPaletteView *_commandPalette;
    id _commandDismissMonitor;
    id _commandLayoutObserver;
    NSString *_configurationSessionID;
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
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [(PTWorkspaceSplitView *)_splitView setTrackedPosition:270 ofDividerAtIndex:0];
    [_store refresh];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(refreshSessions:) userInfo:nil repeats:YES];
    _usageRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(refreshClaudeUsage:) userInfo:nil repeats:YES];
    _questionPollTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(pollQuestionRequests:) userInfo:nil repeats:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)changeInterfaceLanguage:(NSPopUpButton *)sender {
    NSString *language = [sender.selectedItem.representedObject isKindOfClass:NSString.class]
        ? sender.selectedItem.representedObject : @"zh-Hans";
    NSString *stored = PTInterfaceLanguageCode();
    if ([language isEqualToString:stored]) return;
    [self dismissCommandPalette];

    [NSUserDefaults.standardUserDefaults setObject:language
        forKey:PTInterfaceLanguageDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    // Rebuild only PrettyTerm's presentation tree. The session store, Terminal bridge,
    // selected Claude session, pending attachments, and unsent draft remain untouched.
    NSString *draft = _composerTextView.string ?: @"";
    NSRect previousFrame = _window.frame;
    CGFloat sidebarWidth = _splitView.subviews.count >= 2
        ? NSWidth(_splitView.subviews[0].frame) : 270.0;
    CGFloat inspectorWidth = NSWidth(_inspectorView.frame);
    if (inspectorWidth <= 0.0) inspectorWidth = 340.0;
    BOOL inspectorWasHidden = !_inspectorExpanded;
    BOOL toolWasExpanded = !_toolWorkspaceView.hidden;
    CGFloat toolWidth = NSWidth(_toolWorkspaceView.frame) > 0.0
        ? NSWidth(_toolWorkspaceView.frame) : _toolWorkspaceWidthBeforeCollapse;
    BOOL reviewToolPageWasOpen = _reviewToolPageOpen;
    BOOL fileToolPageWasOpen = _fileToolPageOpen;
    NSString *activeToolPageKind = [_activeToolPageKind copy];
    NSAttributedString *reviewDocument = [_gitDiffTextView.attributedString copy];
    BOOL reviewShowedTranscriptEdits = _gitReviewShowsTranscriptEdits;
    NSArray<NSDictionary *> *transcriptReviewEvents = [_transcriptEditReviewEvents copy];
    NSDictionary<NSString *, NSString *> *filePreviewPayload = [_activeFilePreviewPayload copy];
    NSURL *fileTreeRootURL = _fileTreeRootURL;
    BOOL fileTreeRootManuallySelected = _fileTreeRootManuallySelected;
    NSString *fileTreeRootSessionID = [_fileTreeRootSessionID copy];
    BOOL fileTreeWasExpanded = _fileTreeExpanded && !_fileTreeView.hidden;
    CGFloat fileTreeWidth = NSWidth(_fileTreeView.frame) > 0.0
        ? NSWidth(_fileTreeView.frame) : _fileTreeWidthBeforeCollapse;
    NSWindow *previousWindow = _window;
    [_conversationView.configuration.userContentController
        removeScriptMessageHandlerForName:@"quoteSelection"];
    [_conversationView.configuration.userContentController
        removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
    [_conversationView.configuration.userContentController
        removeScriptMessageHandlerForName:@"answerQuestion"];
    [_conversationView.configuration.userContentController
        removeScriptMessageHandlerForName:@"copyAssistantOutput"];
    if (_floatingConversationView) {
        [_floatingConversationView.configuration.userContentController
            removeScriptMessageHandlerForName:@"quoteSelection"];
        [_floatingConversationView.configuration.userContentController
            removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
        [_floatingConversationView.configuration.userContentController
            removeScriptMessageHandlerForName:@"answerQuestion"];
        [_floatingConversationView.configuration.userContentController
            removeScriptMessageHandlerForName:@"copyAssistantOutput"];
    }
    [_floatingPanel orderOut:nil];
    [_composerOptionsPopover close];
    _composerOptionsPopover = nil;
    _composerOptionsStack = nil;
    _composerEffortSlider = nil;
    _floatingPanel = nil;
    _floatingConversationView = nil;
    _floatingWebReady = NO;
    _workspaceRootView = nil;
    _inspectorFloating = NO;
    [previousWindow orderOut:nil];

    _webReady = NO;
    _renderInFlight = NO;
    _renderedSessionID = nil;
    _renderedModifiedAt = nil;
    _renderedMessageCount = 0;
    _gitDiffExpanded = NO;
    _gitReviewShowsTranscriptEdits = NO;
    _transcriptEditReviewEvents = nil;
    [self buildMainMenu];
    [self buildWindow];
    [_window setFrame:previousFrame display:NO];
    [(PTWorkspaceSplitView *)_splitView setTrackedPosition:sidebarWidth ofDividerAtIndex:0];
    _inspectorWidthBeforeCollapse = MAX(210.0, inspectorWidth);
    [self setInspectorExpanded:!inspectorWasHidden animated:NO];
    _reviewToolPageOpen = reviewToolPageWasOpen;
    _fileToolPageOpen = fileToolPageWasOpen;
    _gitDiffExpanded = reviewToolPageWasOpen;
    _gitReviewShowsTranscriptEdits = reviewShowedTranscriptEdits;
    _transcriptEditReviewEvents = transcriptReviewEvents;
    _activeFilePreviewPayload = filePreviewPayload;
    _fileTreeRootManuallySelected = fileTreeRootManuallySelected;
    _fileTreeRootSessionID = fileTreeRootSessionID;
    if (fileTreeRootURL) [self setFileTreeRootURL:fileTreeRootURL];
    if (reviewDocument) [_gitDiffTextView.textStorage setAttributedString:reviewDocument];
    _toolWorkspaceWidthBeforeCollapse = MAX(360.0, toolWidth);
    _fileTreeWidthBeforeCollapse = fileTreeWidth;
    if (reviewToolPageWasOpen) {
        _gitDiffToggleButton.title = reviewShowedTranscriptEdits
            ? PTL(@"关闭本轮审查  ‹", @"Close Turn Review  ‹")
            : PTL(@"关闭 Git 审查  ‹", @"Close Git Review  ‹");
        _gitDiffRefreshButton.hidden = reviewShowedTranscriptEdits;
    }
    if (toolWasExpanded && activeToolPageKind.length > 0) {
        [self showToolPageKind:activeToolPageKind animated:NO];
        [self setToolWorkspaceExpanded:YES animated:NO];
        [self setFileTreeExpanded:fileTreeWasExpanded animated:NO];
    } else {
        [self rebuildToolTabBar];
    }
    _composerTextView.string = draft;
    [self updateImagePreviews];
    [self rebuildSessionSidebarRows];
    [_sessionTable reloadData];
    NSInteger selectedSidebarRow = [self sidebarRowForSessionID:_selectedSession.sessionID];
    if (selectedSidebarRow != NSNotFound) {
        [_sessionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedSidebarRow]
                     byExtendingSelection:NO];
    }
    if (_selectedSession) {
        [self updateInspectorForSession:_selectedSession];
        [self updateContextAndModelForSession:_selectedSession];
    }
    [self refreshAgentStateAndControls];
    [self updateConnectButtonTitle];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

// 之前没建 mainMenu，输入框粘不了字（Cmd+V）、Cmd+Q 也退不出去。
// 补一个最小够用的 App 菜单 + Edit 菜单，标准 selector 会自动接到 NSTextField 的响应链上。
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
    [_refreshTimer invalidate];
    [_questionPollTimer invalidate];
    [_conversationView.configuration.userContentController removeScriptMessageHandlerForName:@"quoteSelection"];
    [_conversationView.configuration.userContentController removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
    [_conversationView.configuration.userContentController removeScriptMessageHandlerForName:@"openTranscriptFile"];
    [_conversationView.configuration.userContentController removeScriptMessageHandlerForName:@"answerQuestion"];
    [_conversationView.configuration.userContentController removeScriptMessageHandlerForName:@"copyAssistantOutput"];
    [_floatingConversationView.configuration.userContentController removeScriptMessageHandlerForName:@"quoteSelection"];
    [_floatingConversationView.configuration.userContentController removeScriptMessageHandlerForName:@"openTranscriptEditReview"];
    [_floatingConversationView.configuration.userContentController removeScriptMessageHandlerForName:@"openTranscriptFile"];
    [_floatingConversationView.configuration.userContentController removeScriptMessageHandlerForName:@"answerQuestion"];
    [_floatingConversationView.configuration.userContentController removeScriptMessageHandlerForName:@"copyAssistantOutput"];
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
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 760)
                                         styleMask:style
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _window.title = visibleAppVersion;
    _window.titleVisibility = NSWindowTitleHidden;
    _window.titlebarAppearsTransparent = YES;
    _window.backgroundColor = PTWarmCanvasColor();
    _window.delegate = self;
    [_window center];
    [self updateWindowMaximumSize];

    NSView *windowContent = _window.contentView;
    PTWorkspaceRootView *root = [[PTWorkspaceRootView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [windowContent addSubview:root];
    _workspaceRootView = root;
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:windowContent.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:windowContent.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:windowContent.trailingAnchor],
        [root.bottomAnchor constraintEqualToAnchor:windowContent.bottomAnchor]
    ]];
    root.wantsLayer = YES;
    root.layer.backgroundColor = NSColor.clearColor.CGColor;

    PTAppearanceSurfaceView *topBar = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    topBar.surfaceStyle = PTAppearanceSurfaceStyleChip;
    [root addSubview:topBar];

    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.image = [NSImage imageNamed:@"PrettyTermLogo"];
    logo.imageScaling = NSImageScaleProportionallyUpOrDown;
    [topBar addSubview:logo];

    NSTextField *title = [self label:visibleAppVersion size:17 weight:NSFontWeightBold color:NSColor.labelColor];
    title.toolTip = [NSString stringWithFormat:PTL(@"当前运行版本：v%@，构建 %@", @"Running version: v%@, build %@"),
        shortVersion, buildVersion];
    [topBar addSubview:title];
    NSTextField *subtitle = [self label:PTL(@"Claude Code 终端伴生 Agent", @"Claude Code terminal companion") size:10.5 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [topBar addSubview:subtitle];

    _statusLabel = [self label:PTL(@"正在读取本地会话…", @"Reading local conversations…") size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    _statusLabel.alignment = NSTextAlignmentRight;
    [topBar addSubview:_statusLabel];

    _contextLabel = [self label:@"ctx —" size:10 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    _contextLabel.alignment = NSTextAlignmentRight;
    [topBar addSubview:_contextLabel];

    _quotaLabel = [self label:@"5h — · 7d —" size:10 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    _quotaLabel.alignment = NSTextAlignmentRight;
    _quotaLabel.toolTip = PTL(@"正在读取 Claude 套餐额度", @"Reading Claude plan limits");
    [topBar addSubview:_quotaLabel];

    _languagePicker = [[PTWarmPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _languagePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [_languagePicker addItemWithTitle:@"中文"];
    _languagePicker.lastItem.representedObject = @"zh-Hans";
    [_languagePicker addItemWithTitle:@"English"];
    _languagePicker.lastItem.representedObject = @"en";
    [_languagePicker selectItemAtIndex:PTInterfaceLanguageIsEnglish() ? 1 : 0];
    _languagePicker.target = self;
    _languagePicker.action = @selector(changeInterfaceLanguage:);
    _languagePicker.toolTip = PTL(@"界面语言", @"Interface language");
    [topBar addSubview:_languagePicker];

    _contextBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _contextBar.translatesAutoresizingMaskIntoConstraints = NO;
    _contextBar.indeterminate = NO;
    _contextBar.minValue = 0;
    _contextBar.maxValue = 1;
    _contextBar.doubleValue = 0;
    _contextBar.style = NSProgressIndicatorStyleBar;
    _contextBar.controlSize = NSControlSizeSmall;
    [topBar addSubview:_contextBar];

    PTWorkspaceSplitView *split = [[PTWorkspaceSplitView alloc] initWithFrame:NSZeroRect];
    split.translatesAutoresizingMaskIntoConstraints = NO;
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.delegate = self;
    [root addSubview:split];
    _splitView = split;

    NSView *sidebar = [self buildSidebar];
    NSView *conversation = [self buildConversation];
    NSView *inspector = [self buildInspector];
    [split addArrangedSubview:sidebar];
    [split addArrangedSubview:conversation];
    [split addArrangedSubview:inspector];
    _inspectorExpanded = YES;
    _inspectorFloating = NO;
    if (_inspectorWidthBeforeCollapse <= 0.0) _inspectorWidthBeforeCollapse = 340.0;
    CGFloat inspectorWidth = [self adaptiveInspectorWidth];
    _inspectorWidthConstraint = [inspector.widthAnchor constraintEqualToConstant:inspectorWidth];
    _inspectorWidthConstraint.priority = 999;
    _inspectorWidthConstraint.active = YES;
    _sidebarWidthConstraint = [sidebar.widthAnchor constraintEqualToConstant:270.0];
    _sidebarWidthConstraint.priority = 999;
    _sidebarWidthConstraint.active = YES;
    [split setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
    [split setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];
    [split setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:2];

    [_inspectorToggleButton removeFromSuperview];
    [topBar addSubview:_inspectorToggleButton];
    _sidePanelToggleButton = PTWarmButton(@"", self, @selector(toggleSidePanel:));
    _sidePanelToggleButton.image = [NSImage imageWithSystemSymbolName:@"sidebar.right" accessibilityDescription:PTL(@"侧边页面", @"Side pages")];
    _sidePanelToggleButton.toolTip = PTL(@"显示或隐藏文件与审查页面", @"Show or hide file and review pages");
    [topBar addSubview:_sidePanelToggleButton];

    for (NSView *view in @[title, subtitle, _statusLabel, _contextLabel,
                           _contextBar, _quotaLabel, _languagePicker]) {
        [view setContentHuggingPriority:100
                         forOrientation:NSLayoutConstraintOrientationHorizontal];
        [view setContentCompressionResistancePriority:100
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    for (NSView *view in @[_contextLabel, _contextBar, _quotaLabel, _languagePicker]) {
        [view setContentCompressionResistancePriority:NSLayoutPriorityFittingSizeCompression - 2.0
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    NSArray<NSLayoutConstraint *> *idealTopBarWidths = @[
        [_contextLabel.widthAnchor constraintEqualToConstant:96],
        [_contextBar.widthAnchor constraintEqualToConstant:92],
        [_quotaLabel.widthAnchor constraintEqualToConstant:114],
        [_languagePicker.widthAnchor constraintEqualToConstant:84]
    ];
    for (NSLayoutConstraint *constraint in idealTopBarWidths) {
        constraint.priority = NSLayoutPriorityFittingSizeCompression - 1.0;
        constraint.active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:64],
        [split.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [split.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [split.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [split.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [logo.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:76],
        [logo.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor constant:9],
        [logo.widthAnchor constraintEqualToConstant:40],
        [logo.heightAnchor constraintEqualToConstant:40],
        [title.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:11],
        [title.topAnchor constraintEqualToAnchor:logo.topAnchor constant:1],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],
        [_sidePanelToggleButton.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-12],
        [_sidePanelToggleButton.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_sidePanelToggleButton.widthAnchor constraintEqualToConstant:30],
        [_inspectorToggleButton.trailingAnchor constraintEqualToAnchor:_sidePanelToggleButton.leadingAnchor constant:-6],
        [_inspectorToggleButton.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_inspectorToggleButton.widthAnchor constraintEqualToConstant:30],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_inspectorToggleButton.leadingAnchor constant:-12],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:topBar.bottomAnchor constant:-3],
        [_statusLabel.widthAnchor constraintLessThanOrEqualToConstant:260],
        [_contextLabel.trailingAnchor constraintEqualToAnchor:_inspectorToggleButton.leadingAnchor constant:-12],
        [_contextLabel.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_contextBar.trailingAnchor constraintEqualToAnchor:_contextLabel.leadingAnchor constant:-8],
        [_contextBar.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_contextBar.heightAnchor constraintEqualToConstant:7],
        [_quotaLabel.trailingAnchor constraintEqualToAnchor:_contextBar.leadingAnchor constant:-10],
        [_quotaLabel.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_languagePicker.trailingAnchor constraintEqualToAnchor:_quotaLabel.leadingAnchor constant:-8],
        [_languagePicker.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [_languagePicker.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:20]
    ]];
}

- (CGFloat)adaptiveInspectorWidth {
    CGFloat preferred = MIN(520.0, MAX(260.0,
        _inspectorWidthBeforeCollapse > 0.0 ? _inspectorWidthBeforeCollapse : 340.0));
    CGFloat available = NSWidth(_window.contentView.bounds);
    if (available <= 0.0) return preferred;
    CGFloat sidebarWidth = _splitView.subviews.count > 0
        ? NSWidth(_splitView.subviews[0].frame) : _sidebarWidthConstraint.constant;
    CGFloat maximum = available - MAX(0.0, sidebarWidth) - 520.0 -
        (2.0 * _splitView.dividerThickness);
    return MIN(preferred, MAX(260.0, maximum));
}

- (void)applyAdaptiveInspectorWidth {
    if (_inspectorFloating) {
        [(PTInspectorOverlayView *)_inspectorView constrainFloatingFrame];
        _inspectorFloatingFrame = _inspectorView.frame;
        return;
    }
    if (_inspectorWidthConstraint) _inspectorWidthConstraint.constant = [self adaptiveInspectorWidth];
}

- (BOOL)shouldFloatInspector {
    CGFloat available = NSWidth(_window.contentView.bounds);
    CGFloat sidebarWidth = _splitView.subviews.count > 0
        ? NSWidth(_splitView.subviews[0].frame) : _sidebarWidthConstraint.constant;
    return available < MAX(0.0, sidebarWidth) + 520.0 + 260.0 +
        (2.0 * _splitView.dividerThickness);
}

- (void)floatInspector {
    if (_inspectorFloating || !_inspectorView) return;
    CGFloat dockedWidth = NSWidth(_inspectorView.frame);
    if (dockedWidth > 0.0) _inspectorWidthBeforeCollapse = dockedWidth;
    _inspectorWidthConstraint.active = NO;
    _inspectorWidthConstraint = nil;
    [_splitView removeArrangedSubview:_inspectorView];
    [_inspectorView removeFromSuperview];
    _inspectorView.translatesAutoresizingMaskIntoConstraints = YES;
    [_workspaceRootView addSubview:_inspectorView positioned:NSWindowAbove relativeTo:_splitView];
    NSRect available = _workspaceRootView.bounds;
    CGFloat workspaceHeight = MAX(320.0, NSHeight(available) - 88.0);
    CGFloat width = MIN(420.0, MAX(320.0, _inspectorWidthBeforeCollapse));
    CGFloat height = MIN(640.0, MAX(360.0, workspaceHeight * 0.78));
    NSRect frame = _hasInspectorFloatingFrame ? _inspectorFloatingFrame : NSMakeRect(
        NSMaxX(available) - width - 12.0,
        NSMaxY(available) - 64.0 - 12.0 - height,
        width,
        height
    );
    _inspectorView.frame = frame;
    _inspectorFloating = YES;
    PTInspectorOverlayView *overlay = (PTInspectorOverlayView *)_inspectorView;
    overlay.floating = YES;
    __weak typeof(self) weakSelf = self;
    overlay.floatingFrameChanged = ^(NSRect changedFrame) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        self->_inspectorFloatingFrame = changedFrame;
        self->_hasInspectorFloatingFrame = YES;
        self->_inspectorWidthBeforeCollapse = NSWidth(changedFrame);
    };
    [overlay constrainFloatingFrame];
    _inspectorFloatingFrame = overlay.frame;
    _hasInspectorFloatingFrame = YES;
    _inspectorView.hidden = !_inspectorExpanded;
    [_window.contentView layoutSubtreeIfNeeded];
}

- (void)dockInspector {
    if (!_inspectorFloating || !_inspectorView) return;
    CGFloat floatingWidth = NSWidth(_inspectorView.frame);
    if (floatingWidth > 0.0) _inspectorWidthBeforeCollapse = floatingWidth;
    _inspectorFloatingFrame = _inspectorView.frame;
    _hasInspectorFloatingFrame = YES;
    PTInspectorOverlayView *overlay = (PTInspectorOverlayView *)_inspectorView;
    overlay.floating = NO;
    overlay.floatingFrameChanged = nil;
    [_inspectorView removeFromSuperview];
    _inspectorView.translatesAutoresizingMaskIntoConstraints = NO;
    [_splitView addArrangedSubview:_inspectorView];
    _inspectorWidthConstraint = [_inspectorView.widthAnchor
        constraintEqualToConstant:[self adaptiveInspectorWidth]];
    _inspectorWidthConstraint.priority = 999;
    _inspectorWidthConstraint.active = YES;
    [_splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:2];
    _inspectorView.hidden = !_inspectorExpanded;
    _inspectorFloating = NO;
    [_window.contentView layoutSubtreeIfNeeded];
}

- (void)updateInspectorPresentation {
    if (_updatingInspectorPresentation || !_inspectorView) return;
    _updatingInspectorPresentation = YES;
    if ([self shouldFloatInspector]) [self floatInspector];
    else [self dockInspector];
    [self applyAdaptiveInspectorWidth];
    _updatingInspectorPresentation = NO;
}

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutCommandPalette];
    if (notification.object == _window) {
        [self updateInspectorPresentation];
    }
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
    if (notification.object != _window) return;
    [self updateWindowMaximumSize];
    [self updateInspectorPresentation];
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

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainSplitPosition:(CGFloat)proposedPosition
           ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == _splitView && dividerIndex == 1 && !_inspectorFloating &&
        splitView.subviews.count >= 3) {
        CGFloat total = NSWidth(splitView.bounds);
        CGFloat sidebarWidth = NSWidth(splitView.subviews[0].frame);
        CGFloat maximum = MAX(260.0, total - sidebarWidth - 420.0 -
            (2.0 * splitView.dividerThickness));
        CGFloat inspectorWidth = total - proposedPosition - splitView.dividerThickness;
        inspectorWidth = MIN(MIN(520.0, maximum), MAX(260.0, inspectorWidth));
        return total - inspectorWidth - splitView.dividerThickness;
    }
    return proposedPosition;
}

- (NSRect)splitView:(NSSplitView *)splitView
       effectiveRect:(NSRect)proposedEffectiveRect
        forDrawnRect:(NSRect)drawnRect
    ofDividerAtIndex:(NSInteger)dividerIndex {
    (void)splitView;
    (void)drawnRect;
    (void)dividerIndex;
    // 细分隔条视觉上仍保持 1px，但左右各扩充命中范围，移动窗口后也容易抓住。
    return NSInsetRect(proposedEffectiveRect, -5.0, 0.0);
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    NSSplitView *splitView = notification.object;
    if (splitView == _workspaceSplitView && splitView.subviews.count >= 2 &&
        !_committingSplitWidths &&
        [(PTWorkspaceSplitView *)splitView mouseDraggingDivider]) {
        _committingSplitWidths = YES;
        CGFloat toolWidth = NSWidth(splitView.subviews[1].frame);
        if (toolWidth > 0.0 && !_toolWorkspaceView.hidden) {
            _toolWorkspaceWidthBeforeCollapse = toolWidth;
            _toolWorkspaceWidthConstraint.constant = toolWidth;
            _toolWorkspaceWidthConstraint.active = YES;
        }
        _committingSplitWidths = NO;
        return;
    }
    if (splitView == _toolContentSplitView && splitView.subviews.count >= 2 &&
        !_committingSplitWidths &&
        [(PTWorkspaceSplitView *)splitView mouseDraggingDivider]) {
        _committingSplitWidths = YES;
        CGFloat treeWidth = NSWidth(splitView.subviews[1].frame);
        if (treeWidth > 0.0 && !_fileTreeView.hidden) {
            _fileTreeWidthBeforeCollapse = treeWidth;
            _fileTreeWidthConstraint.constant = _fileTreeWidthBeforeCollapse;
            _fileTreeWidthConstraint.active = YES;
        }
        _committingSplitWidths = NO;
        return;
    }
    if (splitView != _splitView || splitView.subviews.count < 2 || _committingSplitWidths ||
        ![(PTWorkspaceSplitView *)splitView changingDivider]) return;
    _committingSplitWidths = YES;
    CGFloat sidebarWidth = NSWidth(splitView.subviews[0].frame);
    NSInteger divider = [(PTWorkspaceSplitView *)splitView changingDividerIndex];
    if (divider == 0 && ![(PTWorkspaceSplitView *)splitView mouseDraggingDivider] &&
        [(PTWorkspaceSplitView *)splitView trackedDividerPosition] > 0.0) {
        sidebarWidth = [(PTWorkspaceSplitView *)splitView trackedDividerPosition];
    }
    if (divider == 0 && sidebarWidth > 0.0) {
        _sidebarWidthConstraint.constant = sidebarWidth;
    } else if (divider == 1 && !_inspectorFloating && splitView.subviews.count >= 3) {
        CGFloat inspectorWidth = NSWidth(splitView.subviews[2].frame);
        if (inspectorWidth > 0.0) {
            _inspectorWidthBeforeCollapse = MIN(520.0, MAX(260.0, inspectorWidth));
            _inspectorWidthConstraint.constant = _inspectorWidthBeforeCollapse;
        }
    }
    BOOL dragging = [(PTWorkspaceSplitView *)splitView mouseDraggingDivider];
    if (!dragging) {
        _sidebarWidthConstraint.active = YES;
        if (!_inspectorFloating) _inspectorWidthConstraint.active = YES;
        [self updateInspectorPresentation];
    }
    _committingSplitWidths = NO;
}

- (void)splitViewWillResizeSubviews:(NSNotification *)notification {
    if (notification.object == _workspaceSplitView && !_committingSplitWidths &&
        [(PTWorkspaceSplitView *)_workspaceSplitView mouseDraggingDivider]) {
        _toolWorkspaceWidthConstraint.active = NO;
        return;
    }
    if (notification.object == _toolContentSplitView && !_committingSplitWidths &&
        [(PTWorkspaceSplitView *)_toolContentSplitView mouseDraggingDivider]) {
        _fileTreeWidthConstraint.active = NO;
        return;
    }
    if (notification.object != _splitView || _committingSplitWidths ||
        ![(PTWorkspaceSplitView *)_splitView changingDivider]) return;
    NSInteger divider = [(PTWorkspaceSplitView *)_splitView changingDividerIndex];
    if (divider == 0) {
        _sidebarWidthConstraint.active = NO;
    } else if (divider == 1 && !_inspectorFloating) {
        _inspectorWidthConstraint.active = NO;
    }
}

- (NSView *)buildSidebar {
    PTAppearanceSurfaceView *sidebar = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.surfaceStyle = PTAppearanceSurfaceStyleChip;

    NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [sidebar addSubview:header];
    NSTextField *heading = [self label:PTL(@"会话", @"Conversations") size:14 weight:NSFontWeightBold color:NSColor.labelColor];
    [header addSubview:heading];
    _refreshButton = PTWarmButton(@"↻", self, @selector(refreshSessions:));
    _refreshButton.font = [NSFont systemFontOfSize:17 weight:NSFontWeightMedium];
    _refreshButton.contentTintColor = PTWarmAccentColor();
    _refreshButton.toolTip = PTL(@"刷新本地会话", @"Refresh local conversations");
    [header addSubview:_refreshButton];

    PTAnimatedButton *homeButton = PTWarmButton(PTL(@"主页", @"Home"), self, @selector(showHome:));
    homeButton.image = [NSImage imageWithSystemSymbolName:@"house" accessibilityDescription:nil];
    homeButton.imagePosition = NSImageLeft;
    [header addSubview:homeButton];
    _fileWorkspaceButton = PTWarmButton(@"", self, @selector(openFileWorkspace:));
    _fileWorkspaceButton.image = [NSImage imageWithSystemSymbolName:@"folder"
        accessibilityDescription:PTL(@"文件", @"Files")];
    _fileWorkspaceButton.toolTip = PTL(@"打开文件工作区", @"Open file workspace");
    [header addSubview:_fileWorkspaceButton];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    _sessionTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _sessionTable.headerView = nil;
    _sessionTable.backgroundColor = NSColor.clearColor;
    _sessionTable.rowHeight = 66;
    _sessionTable.intercellSpacing = NSMakeSize(0, 2);
    _sessionTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _sessionTable.dataSource = self;
    _sessionTable.delegate = self;
    // 右键菜单的条目在 menuNeedsUpdate: 里按 clickedRow 现场重建，所以这里只挂一个空壳。
    // autoenablesItems 关掉，否则 AppKit 会忽略我们自己算出来的 enabled（文件已被删时要变灰）。
    NSMenu *sessionMenu = [[NSMenu alloc] init];
    sessionMenu.delegate = self;
    sessionMenu.autoenablesItems = NO;
    _sessionTable.menu = sessionMenu;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"session"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_sessionTable addTableColumn:column];
    scroll.documentView = _sessionTable;
    [sidebar addSubview:scroll];

    NSTextField *privacy = [self label:PTL(@"仅在本机读取 ~/.claude/projects", @"Reads ~/.claude/projects locally only") size:9.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    privacy.alignment = NSTextAlignmentCenter;
    [sidebar addSubview:privacy];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:48],
        [heading.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:14],
        [heading.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_refreshButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [_refreshButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_fileWorkspaceButton.trailingAnchor constraintEqualToAnchor:_refreshButton.leadingAnchor constant:-7],
        [_fileWorkspaceButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_fileWorkspaceButton.widthAnchor constraintEqualToConstant:32],
        [_fileWorkspaceButton.heightAnchor constraintEqualToConstant:28],
        [homeButton.trailingAnchor constraintEqualToAnchor:_fileWorkspaceButton.leadingAnchor constant:-7],
        [homeButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [homeButton.widthAnchor constraintEqualToConstant:70],
        [privacy.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:8],
        [privacy.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-8],
        [privacy.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-9],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:5],
        [scroll.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-5],
        [scroll.bottomAnchor constraintEqualToAnchor:privacy.topAnchor constant:-8]
    ]];
    return sidebar;
}

- (NSView *)buildInspector {
    PTInspectorOverlayView *shell = [[PTInspectorOverlayView alloc] initWithFrame:NSZeroRect];
    shell.translatesAutoresizingMaskIntoConstraints = NO;
    shell.wantsLayer = YES;
    shell.layer.backgroundColor = NSColor.clearColor.CGColor;
    shell.layer.masksToBounds = NO;
    PTAppearanceSurfaceView *inspector = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    inspector.translatesAutoresizingMaskIntoConstraints = NO;
    inspector.surfaceStyle = PTAppearanceSurfaceStyleCard;
    inspector.layer.cornerRadius = 20;
    inspector.layer.borderWidth = 0.5;
    inspector.shadow = [NSShadow new];
    inspector.layer.shadowOpacity = 0.09;
    inspector.layer.shadowRadius = 9;
    inspector.layer.shadowOffset = CGSizeMake(0, -2);
    [shell addSubview:inspector];
    _inspectorCard = inspector;
    [NSLayoutConstraint activateConstraints:@[
        [inspector.topAnchor constraintEqualToAnchor:shell.topAnchor constant:14],
        [inspector.leadingAnchor constraintEqualToAnchor:shell.leadingAnchor constant:10],
        [inspector.heightAnchor constraintLessThanOrEqualToAnchor:shell.heightAnchor constant:-32]
    ]];
    [inspector.trailingAnchor constraintEqualToAnchor:shell.trailingAnchor constant:-16].active = YES;
    [inspector.bottomAnchor constraintEqualToAnchor:shell.bottomAnchor constant:-18].active = YES;
    [inspector setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    _inspectorView = shell;

    NSTextField *title = [self label:PTL(@"检查器", @"Inspector") size:13 weight:NSFontWeightBold color:NSColor.labelColor];
    [inspector addSubview:title];
    PTAnimatedButton *collapse = PTWarmButton(PTL(@"收起 ›", @"Collapse ›"), self, @selector(toggleInspector:));
    collapse.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    [inspector addSubview:collapse];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    [inspector addSubview:scroll];

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(2, 10, 18, 10);
    scroll.documentView = stack;

    NSView* (^makeCard)(NSString *, NSTextField **) = ^NSView *(NSString *heading, NSTextField **valueOut) {
        PTAppearanceSurfaceView *card = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.surfaceStyle = PTAppearanceSurfaceStyleCard;
        card.layer.cornerRadius = 14;
        card.layer.borderWidth = 0.6;
        NSTextField *headingLabel = [self label:heading size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
        NSTextField *value = [self label:@"—" size:12 weight:NSFontWeightMedium color:NSColor.labelColor];
        value.lineBreakMode = NSLineBreakByWordWrapping;
        value.maximumNumberOfLines = 3;
        [card addSubview:headingLabel];
        [card addSubview:value];
        [NSLayoutConstraint activateConstraints:@[
            [headingLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:11],
            [headingLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
            [headingLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
            [value.topAnchor constraintEqualToAnchor:headingLabel.bottomAnchor constant:6],
            [value.leadingAnchor constraintEqualToAnchor:headingLabel.leadingAnchor],
            [value.trailingAnchor constraintEqualToAnchor:headingLabel.trailingAnchor],
            [value.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]
        ]];
        if (valueOut) *valueOut = value;
        return card;
    };

    NSTextField *connectionValue = nil;
    NSView *connectionCard = makeCard(PTL(@"CLAUDE CODE 连接", @"CLAUDE CODE CONNECTION"), &connectionValue);
    _inspectorConnectionLabel = connectionValue;

    // 上下文卡片与成本卡片保持同一层级：总占用和状态条永远可见，只有
    // /context 提供的真实分类明细参与展开折叠。
    PTAppearanceSurfaceView *contextCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    contextCard.translatesAutoresizingMaskIntoConstraints = NO;
    contextCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    contextCard.layer.cornerRadius = 14;
    contextCard.layer.borderWidth = 0.6;

    NSTextField *contextHeading = [self label:PTL(@"上下文使用", @"CONTEXT USAGE")
                                           size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [contextCard addSubview:contextHeading];
    PTAnimatedButton *contextDisclosure = PTWarmButton(PTL(@"详情 ›", @"Details ›"),
        self, @selector(toggleContextDetail:));
    contextDisclosure.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    contextDisclosure.toolTip = PTL(@"展开已记录的上下文分类明细，不向 Claude Code 发送命令",
                                    @"Expand recorded context categories without sending a Claude Code command");
    [contextCard addSubview:contextDisclosure];
    _contextDisclosureButton = contextDisclosure;

    NSStackView *contextBodyStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    contextBodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    contextBodyStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    contextBodyStack.alignment = NSLayoutAttributeLeading;
    contextBodyStack.spacing = 7;
    [contextCard addSubview:contextBodyStack];

    NSView *contextHeadlineRow = [[NSView alloc] initWithFrame:NSZeroRect];
    contextHeadlineRow.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *contextValue = [self label:@"—" size:13 weight:NSFontWeightBold color:NSColor.labelColor];
    NSTextField *contextPercent = [self label:@"—" size:12 weight:NSFontWeightBold color:PTWarmAccentColor()];
    [contextHeadlineRow addSubview:contextValue];
    [contextHeadlineRow addSubview:contextPercent];
    [NSLayoutConstraint activateConstraints:@[
        [contextValue.leadingAnchor constraintEqualToAnchor:contextHeadlineRow.leadingAnchor],
        [contextValue.topAnchor constraintEqualToAnchor:contextHeadlineRow.topAnchor],
        [contextValue.bottomAnchor constraintEqualToAnchor:contextHeadlineRow.bottomAnchor],
        [contextPercent.firstBaselineAnchor constraintEqualToAnchor:contextValue.firstBaselineAnchor],
        [contextPercent.trailingAnchor constraintEqualToAnchor:contextHeadlineRow.trailingAnchor],
        [contextPercent.leadingAnchor constraintGreaterThanOrEqualToAnchor:contextValue.trailingAnchor constant:6]
    ]];
    [contextBodyStack addArrangedSubview:contextHeadlineRow];
    [contextHeadlineRow.widthAnchor constraintEqualToAnchor:contextBodyStack.widthAnchor].active = YES;

    PTMeterView *contextMeter = [[PTMeterView alloc] initWithFrame:NSZeroRect];
    contextMeter.translatesAutoresizingMaskIntoConstraints = NO;
    contextMeter.fillColor = PTWarmAccentColor();
    [contextBodyStack addArrangedSubview:contextMeter];
    [contextMeter.widthAnchor constraintEqualToAnchor:contextBodyStack.widthAnchor].active = YES;
    [contextMeter.heightAnchor constraintEqualToConstant:7].active = YES;

    NSStackView *contextDetailStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    contextDetailStack.translatesAutoresizingMaskIntoConstraints = NO;
    contextDetailStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    contextDetailStack.alignment = NSLayoutAttributeLeading;
    contextDetailStack.spacing = 7;
    contextDetailStack.hidden = YES;
    [contextBodyStack addArrangedSubview:contextDetailStack];
    [contextDetailStack.widthAnchor constraintEqualToAnchor:contextBodyStack.widthAnchor].active = YES;

    _inspectorContextLabel = contextValue;
    _inspectorContextPercentLabel = contextPercent;
    _inspectorContextMeter = contextMeter;
    _inspectorContextDetailStack = contextDetailStack;

    [NSLayoutConstraint activateConstraints:@[
        [contextHeading.topAnchor constraintEqualToAnchor:contextCard.topAnchor constant:11],
        [contextHeading.leadingAnchor constraintEqualToAnchor:contextCard.leadingAnchor constant:12],
        [contextDisclosure.centerYAnchor constraintEqualToAnchor:contextHeading.centerYAnchor],
        [contextDisclosure.trailingAnchor constraintEqualToAnchor:contextCard.trailingAnchor constant:-8],
        [contextDisclosure.leadingAnchor constraintGreaterThanOrEqualToAnchor:contextHeading.trailingAnchor constant:6],
        [contextBodyStack.topAnchor constraintEqualToAnchor:contextHeading.bottomAnchor constant:8],
        [contextBodyStack.leadingAnchor constraintEqualToAnchor:contextCard.leadingAnchor constant:12],
        [contextBodyStack.trailingAnchor constraintEqualToAnchor:contextCard.trailingAnchor constant:-12],
        [contextBodyStack.bottomAnchor constraintEqualToAnchor:contextCard.bottomAnchor constant:-12]
    ]];

    // 套餐额度卡片：每个窗口一行「名称＋百分比」+ 一条圆角进度条 + 重置倒计时，
    // 用条形长度直接看占比，不用每次心算文字里的数字。
    PTAppearanceSurfaceView *quotaCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    quotaCard.translatesAutoresizingMaskIntoConstraints = NO;
    quotaCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    quotaCard.layer.cornerRadius = 14;
    quotaCard.layer.borderWidth = 0.6;

    NSTextField *quotaHeading = [self label:PTL(@"CLAUDE 套餐额度", @"CLAUDE PLAN LIMITS")
                                         size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [quotaCard addSubview:quotaHeading];

    NSStackView *quotaBodyStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    quotaBodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    quotaBodyStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    quotaBodyStack.alignment = NSLayoutAttributeLeading;
    quotaBodyStack.spacing = 10;
    [quotaCard addSubview:quotaBodyStack];

    NSView* (^makeMeterRow)(NSString *, NSTextField **, PTMeterView **, NSTextField **) =
        ^NSView *(NSString *rowLabel, NSTextField **percentOut, PTMeterView **meterOut, NSTextField **captionOut) {
        NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
        row.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField *nameLabel = [self label:rowLabel size:11 weight:NSFontWeightMedium color:NSColor.labelColor];
        NSTextField *percentLabel = [self label:@"—" size:12 weight:NSFontWeightBold color:NSColor.labelColor];

        PTMeterView *meter = [[PTMeterView alloc] initWithFrame:NSZeroRect];
        meter.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField *caption = [self label:@"" size:10 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];

        [row addSubview:nameLabel];
        [row addSubview:percentLabel];
        [row addSubview:meter];
        [row addSubview:caption];

        [NSLayoutConstraint activateConstraints:@[
            [nameLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
            [nameLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [percentLabel.firstBaselineAnchor constraintEqualToAnchor:nameLabel.firstBaselineAnchor],
            [percentLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [percentLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:nameLabel.trailingAnchor constant:6],
            [meter.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:5],
            [meter.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [meter.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [meter.heightAnchor constraintEqualToConstant:6],
            [caption.topAnchor constraintEqualToAnchor:meter.bottomAnchor constant:4],
            [caption.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [caption.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [caption.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
        ]];

        if (percentOut) *percentOut = percentLabel;
        if (meterOut) *meterOut = meter;
        if (captionOut) *captionOut = caption;
        return row;
    };

    NSTextField *fiveHourPercentLabel = nil;
    PTMeterView *fiveHourMeter = nil;
    NSTextField *fiveHourCaption = nil;
    NSView *fiveHourRow = makeMeterRow(PTL(@"5 小时", @"5 hours"),
        &fiveHourPercentLabel, &fiveHourMeter, &fiveHourCaption);
    _inspectorFiveHourPercentLabel = fiveHourPercentLabel;
    _inspectorFiveHourMeter = fiveHourMeter;
    _inspectorFiveHourCaption = fiveHourCaption;

    NSTextField *sevenDayPercentLabel = nil;
    PTMeterView *sevenDayMeter = nil;
    NSTextField *sevenDayCaption = nil;
    NSView *sevenDayRow = makeMeterRow(PTL(@"7 天", @"7 days"),
        &sevenDayPercentLabel, &sevenDayMeter, &sevenDayCaption);
    _inspectorSevenDayPercentLabel = sevenDayPercentLabel;
    _inspectorSevenDayMeter = sevenDayMeter;
    _inspectorSevenDayCaption = sevenDayCaption;
    [quotaBodyStack addArrangedSubview:fiveHourRow];
    [quotaBodyStack addArrangedSubview:sevenDayRow];
    [fiveHourRow.widthAnchor constraintEqualToAnchor:quotaBodyStack.widthAnchor].active = YES;
    [sevenDayRow.widthAnchor constraintEqualToAnchor:quotaBodyStack.widthAnchor].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [quotaHeading.topAnchor constraintEqualToAnchor:quotaCard.topAnchor constant:11],
        [quotaHeading.leadingAnchor constraintEqualToAnchor:quotaCard.leadingAnchor constant:12],
        [quotaHeading.trailingAnchor constraintEqualToAnchor:quotaCard.trailingAnchor constant:-12],
        [quotaBodyStack.topAnchor constraintEqualToAnchor:quotaHeading.bottomAnchor constant:9],
        [quotaBodyStack.leadingAnchor constraintEqualToAnchor:quotaCard.leadingAnchor constant:12],
        [quotaBodyStack.trailingAnchor constraintEqualToAnchor:quotaCard.trailingAnchor constant:-12],
        [quotaBodyStack.bottomAnchor constraintEqualToAnchor:quotaCard.bottomAnchor constant:-12]
    ]];

    // 成本卡片：大号金额当标题，代码改动用一个红绿双色胶囊，「详情」展开后
    // 在下面动态铺开按模型拆分的行——每行也带一条按成本占比换算长度的进度条。
    PTAppearanceSurfaceView *costCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    costCard.translatesAutoresizingMaskIntoConstraints = NO;
    costCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    costCard.layer.cornerRadius = 14;
    costCard.layer.borderWidth = 0.6;

    NSTextField *costHeading = [self label:PTL(@"本会话 API 等价成本", @"API-EQUIVALENT SESSION COST")
                                        size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [costCard addSubview:costHeading];

    PTAnimatedButton *costDisclosure = PTWarmButton(PTL(@"详情 ›", @"Details ›"),
        self, @selector(toggleCostDetail:));
    costDisclosure.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    [costCard addSubview:costDisclosure];
    _costDisclosureButton = costDisclosure;

    NSStackView *costBodyStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    costBodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    costBodyStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    costBodyStack.alignment = NSLayoutAttributeLeading;
    costBodyStack.spacing = 8;
    [costCard addSubview:costBodyStack];

    NSView *costHeadlineRow = [[NSView alloc] initWithFrame:NSZeroRect];
    costHeadlineRow.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *costHeadline = [self label:@"—" size:20 weight:NSFontWeightBold color:NSColor.labelColor];
    NSTextField *costChangesPill = [self label:@"" size:10.5 weight:NSFontWeightSemibold color:NSColor.labelColor];
    costChangesPill.alignment = NSTextAlignmentCenter;
    costChangesPill.wantsLayer = YES;
    costChangesPill.layer.cornerRadius = 8;
    costChangesPill.layer.backgroundColor = PTWarmChipColor().CGColor;
    [costHeadlineRow addSubview:costHeadline];
    [costHeadlineRow addSubview:costChangesPill];
    [NSLayoutConstraint activateConstraints:@[
        [costHeadline.leadingAnchor constraintEqualToAnchor:costHeadlineRow.leadingAnchor],
        [costHeadline.topAnchor constraintEqualToAnchor:costHeadlineRow.topAnchor],
        [costHeadline.bottomAnchor constraintEqualToAnchor:costHeadlineRow.bottomAnchor],
        [costChangesPill.centerYAnchor constraintEqualToAnchor:costHeadline.centerYAnchor],
        [costChangesPill.leadingAnchor constraintGreaterThanOrEqualToAnchor:costHeadline.trailingAnchor constant:8],
        [costChangesPill.trailingAnchor constraintLessThanOrEqualToAnchor:costHeadlineRow.trailingAnchor],
        [costChangesPill.heightAnchor constraintEqualToConstant:18]
    ]];
    _inspectorCostHeadline = costHeadline;
    _inspectorCostChangesPill = costChangesPill;
    [costBodyStack addArrangedSubview:costHeadlineRow];
    [costHeadlineRow.widthAnchor constraintEqualToAnchor:costBodyStack.widthAnchor].active = YES;

    NSTextField *costCaption = [self label:PTL(@"按官方 API 单价估算 · 非订阅实际扣款", @"Estimated at official API rates · not the actual subscription charge")
                                        size:10.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    [costBodyStack addArrangedSubview:costCaption];

    NSStackView *costDetailStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    costDetailStack.translatesAutoresizingMaskIntoConstraints = NO;
    costDetailStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    costDetailStack.alignment = NSLayoutAttributeLeading;
    costDetailStack.spacing = 10;
    costDetailStack.hidden = YES;
    [costBodyStack addArrangedSubview:costDetailStack];
    [costDetailStack.widthAnchor constraintEqualToAnchor:costBodyStack.widthAnchor].active = YES;
    _inspectorCostDetailStack = costDetailStack;

    [NSLayoutConstraint activateConstraints:@[
        [costHeading.topAnchor constraintEqualToAnchor:costCard.topAnchor constant:11],
        [costHeading.leadingAnchor constraintEqualToAnchor:costCard.leadingAnchor constant:12],
        [costDisclosure.centerYAnchor constraintEqualToAnchor:costHeading.centerYAnchor],
        [costDisclosure.trailingAnchor constraintEqualToAnchor:costCard.trailingAnchor constant:-8],
        [costDisclosure.leadingAnchor constraintGreaterThanOrEqualToAnchor:costHeading.trailingAnchor constant:6],
        [costBodyStack.topAnchor constraintEqualToAnchor:costHeading.bottomAnchor constant:8],
        [costBodyStack.leadingAnchor constraintEqualToAnchor:costCard.leadingAnchor constant:12],
        [costBodyStack.trailingAnchor constraintEqualToAnchor:costCard.trailingAnchor constant:-12],
        [costBodyStack.bottomAnchor constraintEqualToAnchor:costCard.bottomAnchor constant:-12]
    ]];
    [stack addArrangedSubview:connectionCard];
    [stack addArrangedSubview:contextCard];
    [stack addArrangedSubview:quotaCard];
    [stack addArrangedSubview:costCard];
    [connectionCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [contextCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [quotaCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [costCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;

    PTAppearanceSurfaceView *gitCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    gitCard.translatesAutoresizingMaskIntoConstraints = NO;
    gitCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    gitCard.layer.cornerRadius = 14;
    gitCard.layer.borderWidth = 0.6;
    NSStackView *gitStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    gitStack.translatesAutoresizingMaskIntoConstraints = NO;
    gitStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    gitStack.alignment = NSLayoutAttributeLeading;
    gitStack.spacing = 7;
    [gitStack setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    [gitCard addSubview:gitStack];

    NSTextField *gitTitle = [self label:PTL(@"GIT 观察目录", @"GIT OBSERVED DIRECTORY") size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [gitStack addArrangedSubview:gitTitle];
    _gitDirectoryPicker = [[PTWarmPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _gitDirectoryPicker.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDirectoryPicker.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _gitDirectoryPicker.target = self;
    _gitDirectoryPicker.action = @selector(gitDirectorySelectionChanged:);
    [_gitDirectoryPicker addItemWithTitle:PTL(@"等待会话目录…", @"Waiting for conversation directory…")];
    _gitDirectoryPicker.enabled = NO;
    NSStackView *directoryRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    directoryRow.translatesAutoresizingMaskIntoConstraints = NO;
    directoryRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    directoryRow.alignment = NSLayoutAttributeCenterY;
    directoryRow.spacing = 6;
    _removeGitDirectoryButton = PTWarmButton(PTL(@"删除", @"Remove"),
        self, @selector(removeSelectedGitDirectory:));
    _removeGitDirectoryButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _removeGitDirectoryButton.toolTip = PTL(@"从 PrettyTerm 记忆中删除当前目录", @"Remove the current directory from PrettyTerm memory");
    _removeGitDirectoryButton.enabled = NO;
    [directoryRow addArrangedSubview:_gitDirectoryPicker];
    [directoryRow addArrangedSubview:_removeGitDirectoryButton];
    [_removeGitDirectoryButton.widthAnchor constraintEqualToConstant:48].active = YES;
    [gitStack addArrangedSubview:directoryRow];

    NSStackView *manualRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    manualRow.translatesAutoresizingMaskIntoConstraints = NO;
    manualRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    manualRow.alignment = NSLayoutAttributeCenterY;
    manualRow.spacing = 6;
    _gitDirectoryInput = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _gitDirectoryInput.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDirectoryInput.placeholderString = PTL(@"手动输入文件夹路径", @"Enter a folder path manually");
    _gitDirectoryInput.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    PTAnimatedButton *addDirectoryButton = PTWarmButton(PTL(@"添加", @"Add"),
        self, @selector(addManualGitDirectory:));
    addDirectoryButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    [manualRow addArrangedSubview:_gitDirectoryInput];
    [manualRow addArrangedSubview:addDirectoryButton];
    [_gitDirectoryInput.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;
    [_gitDirectoryInput.heightAnchor constraintEqualToConstant:28].active = YES;
    [addDirectoryButton.widthAnchor constraintEqualToConstant:48].active = YES;
    [gitStack addArrangedSubview:manualRow];

    _gitDirectoryHintLabel = [self label:PTL(@"这里只切换 PrettyTerm 的 Git diff 探测目录，不会改变 Claude Code。要让 Claude 访问新目录，请在 Claude Code 执行 /add-dir <路径>。", @"This only changes PrettyTerm's Git diff probe; it does not change Claude Code. Run /add-dir <path> in Claude Code to grant Claude access.") size:9.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    _gitDirectoryHintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _gitDirectoryHintLabel.maximumNumberOfLines = 0;
    [_gitDirectoryHintLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    [gitStack addArrangedSubview:_gitDirectoryHintLabel];

    NSStackView *gitActionRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    gitActionRow.translatesAutoresizingMaskIntoConstraints = NO;
    gitActionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    gitActionRow.alignment = NSLayoutAttributeCenterY;
    gitActionRow.spacing = 6;
    _gitDiffToggleButton = PTWarmButton(PTL(@"展开 Git 审阅  ›", @"Expand Git Review  ›"),
        self, @selector(toggleGitDiff:));
    _gitDiffToggleButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    _gitDiffRefreshButton = PTWarmButton(PTL(@"刷新", @"Refresh"), self, @selector(refreshGitDiff:));
    _gitDiffRefreshButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _gitDiffRefreshButton.hidden = YES;
    _gitPublishButton = PTWarmButton(PTL(@"提交或推送…", @"Commit or Push…"),
        self, @selector(showGitActions:));
    _gitPublishButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    _gitPublishButton.contentTintColor = PTWarmAccentColor();
    _gitPublishButton.toolTip = PTL(@"提交当前改动，或推送已有提交", @"Commit current changes or push existing commits");
    _gitPublishButton.enabled = NO;
    _gitDiffProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _gitDiffProgress.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDiffProgress.style = NSProgressIndicatorStyleSpinning;
    _gitDiffProgress.controlSize = NSControlSizeSmall;
    _gitDiffProgress.displayedWhenStopped = NO;
    _gitDiffProgress.hidden = YES;
    [gitActionRow addArrangedSubview:_gitDiffToggleButton];
    [gitActionRow addArrangedSubview:_gitDiffRefreshButton];
    [gitActionRow addArrangedSubview:_gitPublishButton];
    [gitActionRow addArrangedSubview:_gitDiffProgress];
    [_gitDiffProgress.widthAnchor constraintEqualToConstant:14].active = YES;
    [_gitDiffProgress.heightAnchor constraintEqualToConstant:14].active = YES;
    [gitStack addArrangedSubview:gitActionRow];

    [stack addArrangedSubview:gitCard];
    [gitCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [gitStack.topAnchor constraintEqualToAnchor:gitCard.topAnchor constant:11],
        [gitStack.leadingAnchor constraintEqualToAnchor:gitCard.leadingAnchor constant:12],
        [gitStack.trailingAnchor constraintEqualToAnchor:gitCard.trailingAnchor constant:-12],
        [gitStack.bottomAnchor constraintEqualToAnchor:gitCard.bottomAnchor constant:-12],
        [directoryRow.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor],
        [manualRow.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor],
        [_gitDirectoryHintLabel.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor],
        [gitActionRow.widthAnchor constraintEqualToAnchor:gitStack.widthAnchor]
    ]];

    PTAppearanceSurfaceView *changesCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    changesCard.translatesAutoresizingMaskIntoConstraints = NO;
    changesCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    changesCard.layer.cornerRadius = 14;
    changesCard.layer.borderWidth = 0.6;
    NSTextField *changesTitle = [self label:PTL(@"本轮改动", @"CURRENT CHANGES") size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [changesCard addSubview:changesTitle];
    _changedFilesStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _changedFilesStack.translatesAutoresizingMaskIntoConstraints = NO;
    _changedFilesStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _changedFilesStack.alignment = NSLayoutAttributeLeading;
    _changedFilesStack.spacing = 4;
    [changesCard addSubview:_changedFilesStack];
    [stack addArrangedSubview:changesCard];

    PTAppearanceSurfaceView *tasksCard = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    tasksCard.translatesAutoresizingMaskIntoConstraints = NO;
    tasksCard.surfaceStyle = PTAppearanceSurfaceStyleCard;
    tasksCard.layer.cornerRadius = 14;
    tasksCard.layer.borderWidth = 0.6;
    NSTextField *tasksTitle = [self label:PTL(@"任务列表", @"TASKS") size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    [tasksCard addSubview:tasksTitle];
    _tasksStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _tasksStack.translatesAutoresizingMaskIntoConstraints = NO;
    _tasksStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _tasksStack.alignment = NSLayoutAttributeLeading;
    _tasksStack.spacing = 4;
    [tasksCard addSubview:_tasksStack];
    [stack addArrangedSubview:tasksCard];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:inspector.topAnchor constant:17],
        [title.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:14],
        [collapse.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-10],
        [collapse.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [scroll.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:inspector.bottomAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentView.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [changesCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20],
        [changesTitle.topAnchor constraintEqualToAnchor:changesCard.topAnchor constant:11],
        [changesTitle.leadingAnchor constraintEqualToAnchor:changesCard.leadingAnchor constant:12],
        [changesTitle.trailingAnchor constraintEqualToAnchor:changesCard.trailingAnchor constant:-12],
        [_changedFilesStack.topAnchor constraintEqualToAnchor:changesTitle.bottomAnchor constant:8],
        [_changedFilesStack.leadingAnchor constraintEqualToAnchor:changesCard.leadingAnchor constant:8],
        [_changedFilesStack.trailingAnchor constraintEqualToAnchor:changesCard.trailingAnchor constant:-8],
        [_changedFilesStack.bottomAnchor constraintEqualToAnchor:changesCard.bottomAnchor constant:-8],
        [tasksCard.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-20],
        [tasksTitle.topAnchor constraintEqualToAnchor:tasksCard.topAnchor constant:11],
        [tasksTitle.leadingAnchor constraintEqualToAnchor:tasksCard.leadingAnchor constant:12],
        [tasksTitle.trailingAnchor constraintEqualToAnchor:tasksCard.trailingAnchor constant:-12],
        [_tasksStack.topAnchor constraintEqualToAnchor:tasksTitle.bottomAnchor constant:8],
        [_tasksStack.leadingAnchor constraintEqualToAnchor:tasksCard.leadingAnchor constant:8],
        [_tasksStack.trailingAnchor constraintEqualToAnchor:tasksCard.trailingAnchor constant:-8],
        [_tasksStack.bottomAnchor constraintEqualToAnchor:tasksCard.bottomAnchor constant:-8]
    ]];
    // One inset summary surface; sections share its background and use hairlines.
    for (NSView *section in stack.arrangedSubviews) {
        section.layer.cornerRadius = 0;
        section.layer.borderWidth = 0;
        NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
        separator.boxType = NSBoxSeparator;
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        [section addSubview:separator];
        [NSLayoutConstraint activateConstraints:@[
            [separator.leadingAnchor constraintEqualToAnchor:section.leadingAnchor constant:12],
            [separator.trailingAnchor constraintEqualToAnchor:section.trailingAnchor constant:-12],
            [separator.bottomAnchor constraintEqualToAnchor:section.bottomAnchor]
        ]];
    }
    // Inspector contents wrap to the width chosen by the user. Their intrinsic
    // text/control widths must never become a hidden minimum-window constraint.
    NSMutableArray<NSView *> *flexibleViews = [NSMutableArray arrayWithObject:inspector];
    while (flexibleViews.count > 0) {
        NSView *view = flexibleViews.lastObject;
        [flexibleViews removeLastObject];
        [view setContentHuggingPriority:100 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [view setContentCompressionResistancePriority:100 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [flexibleViews addObjectsFromArray:view.subviews];
    }
    return shell;
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
            self->_statusLabel.stringValue = strongTab.status;
            self->_agentState.sendInFlight = NO;
            [self refreshAgentStateAndControls];
            [self updateConnectButtonTitle];
        }
        [self updateWorkspaceTabBar];
    };
    tab.bridge.outputObserved = ^(NSString *chunk) {
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab || self->_activeWorkspaceTab != strongTab) return;
        if ([chunk containsString:@"Remote Control"] && [chunk containsString:@"http"]) {
            self->_statusLabel.stringValue = PTL(@"官方 Remote Control 已启用", @"Official Remote Control is enabled");
        }
    };
    tab.bridge.turnCompleted = ^{
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab) return;
        [self finishAwaitingClaudeReplyForSessionID:strongTab.bridge.sessionID];
        [self->_store refresh];
    };
    tab.bridge.streamChanged = ^{
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (self && strongTab) {
            [self presentClaudeStreamForBridge:strongTab.bridge];
            [self refreshAgentStateAndControls];
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
        session.model = strongTab.bridge.currentModel;
        session.effort = strongTab.bridge.currentEffort;
        [self updateComposerConfigurationButtons];
        [self refreshComposerConfigurationPopoverForSessionID:strongTab.bridge.sessionID];
        if ([session.sessionID isEqual:self->_selectedSession.sessionID]) [self showSelectedSession];
    };
    tab.bridge.commandOutputChanged = ^(NSString *text) {
        PTAppDelegate *self = weakSelf;
        PTWorkspaceTab *strongTab = weakTab;
        if (!self || !strongTab) return;
        strongTab.commandOutput = text;
        strongTab.status = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject;
        if (self->_activeWorkspaceTab == strongTab) {
            self->_statusLabel.stringValue = strongTab.status;
            self->_statusLabel.toolTip = text;
        }
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
    tab.pendingImages = [NSMutableArray array];
    tab.pendingFiles = [NSMutableArray array];
    tab.bridge = [[PTClaudeBridge alloc] init];
    [self configureBridgeCallbacksForWorkspaceTab:tab];
    [_workspaceTabs addObject:tab];
    return tab;
}

- (void)saveActiveWorkspaceTabState {
    if (!_activeWorkspaceTab) return;
    _activeWorkspaceTab.sessionID = _selectedSession.sessionID ?: @"";
    _activeWorkspaceTab.draft = _composerTextView.string ?: @"";
    _activeWorkspaceTab.connecting = _connecting;
}

- (void)showEmptyWorkspaceTab {
    _selectedSession = nil;
    [_sessionTable deselectAll:nil];
    [_transcriptWatcher stopWatching];
    _watchedTranscriptPath = nil;
    _conversationTitle.stringValue = PTL(@"新标签", @"New tab");
    _conversationDetail.stringValue = PTL(@"从左侧选择会话", @"Choose a conversation from the sidebar");
    _connectButton.enabled = NO;
    _renderedSessionID = nil;
    _renderedModifiedAt = nil;
    _renderedMessageCount = 0;
    if (_webReady) {
        NSString *script = [NSString stringWithFormat:
            @"window.setClaudeSession({sessionId:'',title:'',messages:[],interfaceLanguage:'%@'}); null;",
            PTInterfaceLanguageCode()];
        [_conversationView evaluateJavaScript:script completionHandler:nil];
    }
    _statusLabel.stringValue = _activeWorkspaceTab.status ?: @"";
    [self refreshAgentStateAndControls];
    [self updateConnectButtonTitle];
    [self updateFloatingControls];
}

- (void)activateWorkspaceTab:(PTWorkspaceTab *)tab animated:(BOOL)animated {
    if (!tab || _activeWorkspaceTab == tab) return;
    [self dismissCommandPalette];
    [self saveActiveWorkspaceTabState];
    _activeWorkspaceTab = tab;
    _bridge = tab.bridge;
    _connecting = tab.connecting;
    _pendingImages = tab.pendingImages;
    _pendingFiles = tab.pendingFiles;
    _composerTextView.string = tab.draft ?: @"";
    [self updateImagePreviews];

    _renderedSessionID = nil;
    _renderedModifiedAt = nil;
    _renderedMessageCount = 0;
    _pendingRenderSession = nil;
    PTSessionInfo *session = [self sessionWithID:tab.sessionID];
    if (session) {
        _selectedSession = session;
        NSInteger row = [self sidebarRowForSessionID:session.sessionID];
        if (row == NSNotFound) [_sessionTable deselectAll:nil];
        else [_sessionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                         byExtendingSelection:NO];
        [self showSelectedSession];
        _statusLabel.stringValue = tab.status.length ? tab.status :
            PTL(@"标签已切换", @"Tab switched");
    } else {
        [self showEmptyWorkspaceTab];
    }
    [self updateWorkspaceTabBar];
    if (animated && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _conversationView.alphaValue = 0.72;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.16;
            self->_conversationView.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }
}

- (void)selectWorkspaceTab:(PTAnimatedButton *)sender {
    NSString *identifier = sender.identifier ?: @"";
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        if ([tab.identifier isEqual:identifier]) {
            [self activateWorkspaceTab:tab animated:YES];
            return;
        }
    }
}

- (void)addWorkspaceTab:(id)sender {
    (void)sender;
    PTWorkspaceTab *tab = [self createWorkspaceTab];
    [self activateWorkspaceTab:tab animated:YES];
}

- (void)closeWorkspaceTab:(PTAnimatedButton *)sender {
    NSString *identifier = sender.identifier ?: @"";
    NSUInteger index = [_workspaceTabs indexOfObjectPassingTest:
        ^BOOL(PTWorkspaceTab *tab, NSUInteger tabIndex, BOOL *stop) {
            (void)tabIndex;
            (void)stop;
            return [tab.identifier isEqual:identifier];
        }];
    if (index == NSNotFound) return;

    PTWorkspaceTab *closingTab = _workspaceTabs[index];
    BOOL closingActiveTab = closingTab == _activeWorkspaceTab;
    if (closingActiveTab) [self saveActiveWorkspaceTabState];
    NSString *closingSessionID = closingTab.bridge.sessionID ?: closingTab.sessionID;
    [closingTab.bridge stop];
    if (closingSessionID.length > 0) {
        [self finishAwaitingClaudeReplyForSessionID:closingSessionID];
    }
    [_workspaceTabs removeObjectAtIndex:index];

    if (!closingActiveTab) {
        [self syncFullSessionIDs];
        [self updateWorkspaceTabBar];
        [self updateFloatingComposerState];
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
        _composerTextView.string = @"";
        [self updateImagePreviews];
        [self showEmptyWorkspaceTab];
        [self updateWorkspaceTabBar];
    }
    [self syncFullSessionIDs];
}

- (void)updateWorkspaceTabBar {
    if (!_workspaceTabStack) return;
    for (NSView *view in _workspaceTabStack.arrangedSubviews.copy) {
        [_workspaceTabStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        PTSessionInfo *session = [self sessionWithID:tab.sessionID];
        NSString *name = session.title.length ? session.title : PTL(@"新标签", @"New tab");
        NSString *dot = tab.bridge.running ? @"●" : @"○";
        NSView *item = [[NSView alloc] initWithFrame:NSZeroRect];
        item.translatesAutoresizingMaskIntoConstraints = NO;

        PTAnimatedButton *selectButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
        selectButton.translatesAutoresizingMaskIntoConstraints = NO;
        selectButton.title = @"";
        selectButton.identifier = tab.identifier;
        selectButton.target = self;
        selectButton.action = @selector(selectWorkspaceTab:);
        selectButton.fillColor = _activeWorkspaceTab == tab ? PTWarmChipColor() : NSColor.clearColor;
        selectButton.hoverFillColor = PTWarmChipColor();
        selectButton.pressedFillColor = PTWarmBorderColor();
        selectButton.strokeColor = _activeWorkspaceTab == tab ? PTWarmBorderColor() : NSColor.clearColor;
        selectButton.cornerRadius = 11;
        selectButton.toolTip = tab.bridge.running
            ? [NSString stringWithFormat:PTL(@"已连接 Claude · %@", @"Terminal synced · %@"), name]
            : name;
        [selectButton setAccessibilityLabel:name];

        PTPassthroughTextField *titleLabel = [[PTPassthroughTextField alloc] initWithFrame:NSZeroRect];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.stringValue = [NSString stringWithFormat:@"%@  %@", dot, name];
        titleLabel.font = [NSFont systemFontOfSize:11.5 weight:
            (_activeWorkspaceTab == tab ? NSFontWeightSemibold : NSFontWeightMedium)];
        titleLabel.textColor = _activeWorkspaceTab == tab ? PTWarmAccentColor() : NSColor.secondaryLabelColor;
        titleLabel.bezeled = NO;
        titleLabel.bordered = NO;
        titleLabel.drawsBackground = NO;
        titleLabel.editable = NO;
        titleLabel.selectable = NO;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        PTAnimatedButton *closeButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        closeButton.title = @"×";
        closeButton.identifier = tab.identifier;
        closeButton.target = self;
        closeButton.action = @selector(closeWorkspaceTab:);
        closeButton.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        closeButton.contentTintColor = NSColor.secondaryLabelColor;
        closeButton.fillColor = NSColor.clearColor;
        closeButton.hoverFillColor = PTWarmBorderColor();
        closeButton.pressedFillColor = PTWarmAccentColor();
        closeButton.cornerRadius = 10;
        closeButton.toolTip = PTL(@"关闭标签", @"Close tab");
        [closeButton setAccessibilityLabel:closeButton.toolTip];

        [item addSubview:selectButton];
        [item addSubview:titleLabel];
        [item addSubview:closeButton];
        [NSLayoutConstraint activateConstraints:@[
            [selectButton.leadingAnchor constraintEqualToAnchor:item.leadingAnchor],
            [selectButton.trailingAnchor constraintEqualToAnchor:item.trailingAnchor],
            [selectButton.topAnchor constraintEqualToAnchor:item.topAnchor],
            [selectButton.bottomAnchor constraintEqualToAnchor:item.bottomAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:item.leadingAnchor constant:14],
            [titleLabel.centerYAnchor constraintEqualToAnchor:item.centerYAnchor],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeButton.leadingAnchor constant:-7],
            [closeButton.trailingAnchor constraintEqualToAnchor:item.trailingAnchor constant:-6],
            [closeButton.centerYAnchor constraintEqualToAnchor:item.centerYAnchor],
            [closeButton.widthAnchor constraintEqualToConstant:22],
            [closeButton.heightAnchor constraintEqualToConstant:22]
        ]];
        [_workspaceTabStack addArrangedSubview:item];
        [item.widthAnchor constraintEqualToConstant:184].active = YES;
        [item.heightAnchor constraintEqualToConstant:32].active = YES;
    }

    PTAnimatedButton *add = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    add.translatesAutoresizingMaskIntoConstraints = NO;
    add.title = PTL(@"＋  新标签", @"＋  New tab");
    add.target = self;
    add.action = @selector(addWorkspaceTab:);
    add.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    add.contentTintColor = NSColor.secondaryLabelColor;
    add.fillColor = NSColor.clearColor;
    add.hoverFillColor = PTWarmChipColor();
    add.pressedFillColor = PTWarmBorderColor();
    add.cornerRadius = 11;
    [_workspaceTabStack addArrangedSubview:add];
    [add.widthAnchor constraintEqualToConstant:100].active = YES;
    [add.heightAnchor constraintEqualToConstant:32].active = YES;
}

- (NSView *)buildToolWorkspace {
    PTAppearanceSurfaceView *tool = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    tool.translatesAutoresizingMaskIntoConstraints = NO;
    tool.surfaceStyle = PTAppearanceSurfaceStyleCanvas;
    [tool setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    _toolWorkspaceView = tool;

    NSVisualEffectView *header = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.material = NSVisualEffectMaterialHeaderView;
    header.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    header.state = NSVisualEffectStateActive;
    [tool addSubview:header];

    _toolTabStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _toolTabStack.translatesAutoresizingMaskIntoConstraints = NO;
    _toolTabStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _toolTabStack.alignment = NSLayoutAttributeCenterY;
    _toolTabStack.spacing = 6;
    [header addSubview:_toolTabStack];

    _toolReviewRefreshButton = PTWarmButton(PTL(@"刷新", @"Refresh"),
        self, @selector(refreshGitDiff:));
    _toolReviewRefreshButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    [header addSubview:_toolReviewRefreshButton];
    _fileTreeToggleButton = PTWarmButton(@"", self, @selector(toggleFileTree:));
    _fileTreeToggleButton.image = [NSImage imageWithSystemSymbolName:@"folder"
        accessibilityDescription:PTL(@"显示文件", @"Show files")];
    _fileTreeToggleButton.toolTip = PTL(@"显示或隐藏文件树", @"Show or hide the file tree");
    [header addSubview:_fileTreeToggleButton];

    _toolContentView = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    _toolContentView.translatesAutoresizingMaskIntoConstraints = NO;
    ((PTAppearanceSurfaceView *)_toolContentView).surfaceStyle = PTAppearanceSurfaceStyleCard;
    [tool addSubview:_toolContentView];

    _toolContentSplitView = [[PTWorkspaceSplitView alloc] initWithFrame:NSZeroRect];
    _toolContentSplitView.translatesAutoresizingMaskIntoConstraints = NO;
    _toolContentSplitView.vertical = YES;
    _toolContentSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    _toolContentSplitView.delegate = self;
    [_toolContentView addSubview:_toolContentSplitView];

    _toolPageContainerView = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    _toolPageContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    ((PTAppearanceSurfaceView *)_toolPageContainerView).surfaceStyle = PTAppearanceSurfaceStyleCard;
    [_toolContentSplitView addArrangedSubview:_toolPageContainerView];

    _gitDiffScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _gitDiffScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _gitDiffScroll.hasVerticalScroller = YES;
    _gitDiffScroll.hasHorizontalScroller = YES;
    _gitDiffScroll.autohidesScrollers = YES;
    _gitDiffScroll.borderType = NSNoBorder;
    _gitDiffScroll.drawsBackground = YES;
    _gitDiffScroll.backgroundColor = PTWarmCardColor();
    _gitDiffScroll.hidden = YES;
    [_toolPageContainerView addSubview:_gitDiffScroll];

    _gitDiffTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 0, 640)];
    _gitDiffTextView.editable = NO;
    _gitDiffTextView.selectable = YES;
    _gitDiffTextView.richText = YES;
    _gitDiffTextView.drawsBackground = NO;
    _gitDiffTextView.usesFindBar = YES;
    _gitDiffTextView.usesAdaptiveColorMappingForDarkAppearance = YES;
    _gitDiffTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _gitDiffTextView.textContainerInset = NSMakeSize(18, 18);
    _gitDiffTextView.horizontallyResizable = YES;
    _gitDiffTextView.verticallyResizable = YES;
    _gitDiffTextView.minSize = NSMakeSize(0, 0);
    _gitDiffTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _gitDiffTextView.textContainer.widthTracksTextView = NO;
    _gitDiffTextView.string = PTL(@"选择 Git 观察目录后打开审查。",
        @"Select a Git observation directory, then open Review.");
    _gitDiffScroll.documentView = _gitDiffTextView;

    WKWebViewConfiguration *fileConfiguration = [[WKWebViewConfiguration alloc] init];
    fileConfiguration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    _filePreviewWebView = [[WKWebView alloc] initWithFrame:NSZeroRect
                                             configuration:fileConfiguration];
    _filePreviewWebView.translatesAutoresizingMaskIntoConstraints = NO;
    _filePreviewWebView.navigationDelegate = self;
    _filePreviewWebView.hidden = YES;
    if (@available(macOS 12.0, *)) _filePreviewWebView.underPageBackgroundColor = NSColor.clearColor;
    [_toolPageContainerView addSubview:_filePreviewWebView];
    NSURL *fileHTMLURL = [NSBundle.mainBundle URLForResource:@"index" withExtension:@"html"];
    if (fileHTMLURL) {
        [_filePreviewWebView loadFileURL:fileHTMLURL
                   allowingReadAccessToURL:NSBundle.mainBundle.resourceURL];
    }

    NSVisualEffectView *fileTree = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    fileTree.translatesAutoresizingMaskIntoConstraints = NO;
    fileTree.material = NSVisualEffectMaterialSidebar;
    fileTree.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    fileTree.state = NSVisualEffectStateActive;
    fileTree.hidden = YES;
    _fileTreeView = fileTree;
    [_toolContentSplitView addArrangedSubview:fileTree];

    _fileTreeRootButton = PTWarmButton(PTL(@"选择文件夹", @"Choose folder"),
        self, @selector(chooseFileTreeRoot:));
    _fileTreeRootButton.image = [NSImage imageWithSystemSymbolName:@"folder"
        accessibilityDescription:nil];
    _fileTreeRootButton.imagePosition = NSImageLeft;
    _fileTreeRootButton.alignment = NSTextAlignmentLeft;
    [fileTree addSubview:_fileTreeRootButton];

    _fileTreeSearchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _fileTreeSearchField.translatesAutoresizingMaskIntoConstraints = NO;
    _fileTreeSearchField.placeholderString = PTL(@"筛选文件…", @"Filter files…");
    _fileTreeSearchField.target = self;
    _fileTreeSearchField.action = @selector(filterFileTree:);
    [fileTree addSubview:_fileTreeSearchField];

    NSScrollView *fileTreeScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    fileTreeScroll.translatesAutoresizingMaskIntoConstraints = NO;
    fileTreeScroll.hasVerticalScroller = YES;
    fileTreeScroll.autohidesScrollers = YES;
    fileTreeScroll.drawsBackground = NO;
    [fileTree addSubview:fileTreeScroll];
    _fileOutlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _fileOutlineView.headerView = nil;
    _fileOutlineView.backgroundColor = NSColor.clearColor;
    _fileOutlineView.rowHeight = 28.0;
    _fileOutlineView.indentationPerLevel = 14.0;
    _fileOutlineView.dataSource = self;
    _fileOutlineView.delegate = self;
    NSTableColumn *fileColumn = [[NSTableColumn alloc] initWithIdentifier:@"file"];
    fileColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_fileOutlineView addTableColumn:fileColumn];
    _fileOutlineView.outlineTableColumn = fileColumn;
    fileTreeScroll.documentView = _fileOutlineView;
    _fileTreeChildrenByPath = [NSMutableDictionary dictionary];
    _fileTreeWidthBeforeCollapse = 260.0;
    _fileTreeWidthConstraint = [fileTree.widthAnchor constraintEqualToConstant:0.0];
    _fileTreeWidthConstraint.priority = 999;
    _fileTreeWidthConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:tool.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:tool.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:tool.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:44],
        [_toolTabStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10],
        [_toolTabStack.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_fileTreeToggleButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [_fileTreeToggleButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_fileTreeToggleButton.widthAnchor constraintEqualToConstant:34],
        [_fileTreeToggleButton.heightAnchor constraintEqualToConstant:28],
        [_toolReviewRefreshButton.trailingAnchor constraintEqualToAnchor:_fileTreeToggleButton.leadingAnchor constant:-7],
        [_toolReviewRefreshButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_toolReviewRefreshButton.widthAnchor constraintEqualToConstant:54],
        [_toolReviewRefreshButton.heightAnchor constraintEqualToConstant:28],
        [_toolContentView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [_toolContentView.leadingAnchor constraintEqualToAnchor:tool.leadingAnchor],
        [_toolContentView.trailingAnchor constraintEqualToAnchor:tool.trailingAnchor],
        [_toolContentView.bottomAnchor constraintEqualToAnchor:tool.bottomAnchor],
        [_toolContentSplitView.topAnchor constraintEqualToAnchor:_toolContentView.topAnchor],
        [_toolContentSplitView.leadingAnchor constraintEqualToAnchor:_toolContentView.leadingAnchor],
        [_toolContentSplitView.trailingAnchor constraintEqualToAnchor:_toolContentView.trailingAnchor],
        [_toolContentSplitView.bottomAnchor constraintEqualToAnchor:_toolContentView.bottomAnchor],
        [_gitDiffScroll.topAnchor constraintEqualToAnchor:_toolPageContainerView.topAnchor],
        [_gitDiffScroll.leadingAnchor constraintEqualToAnchor:_toolPageContainerView.leadingAnchor],
        [_gitDiffScroll.trailingAnchor constraintEqualToAnchor:_toolPageContainerView.trailingAnchor],
        [_gitDiffScroll.bottomAnchor constraintEqualToAnchor:_toolPageContainerView.bottomAnchor],
        [_filePreviewWebView.topAnchor constraintEqualToAnchor:_toolPageContainerView.topAnchor],
        [_filePreviewWebView.leadingAnchor constraintEqualToAnchor:_toolPageContainerView.leadingAnchor],
        [_filePreviewWebView.trailingAnchor constraintEqualToAnchor:_toolPageContainerView.trailingAnchor],
        [_filePreviewWebView.bottomAnchor constraintEqualToAnchor:_toolPageContainerView.bottomAnchor],
        [_fileTreeRootButton.topAnchor constraintEqualToAnchor:fileTree.topAnchor constant:10],
        [_fileTreeRootButton.leadingAnchor constraintEqualToAnchor:fileTree.leadingAnchor constant:10],
        [_fileTreeRootButton.trailingAnchor constraintEqualToAnchor:fileTree.trailingAnchor constant:-10],
        [_fileTreeRootButton.heightAnchor constraintEqualToConstant:30],
        [_fileTreeSearchField.topAnchor constraintEqualToAnchor:_fileTreeRootButton.bottomAnchor constant:8],
        [_fileTreeSearchField.leadingAnchor constraintEqualToAnchor:fileTree.leadingAnchor constant:10],
        [_fileTreeSearchField.trailingAnchor constraintEqualToAnchor:fileTree.trailingAnchor constant:-10],
        [fileTreeScroll.topAnchor constraintEqualToAnchor:_fileTreeSearchField.bottomAnchor constant:8],
        [fileTreeScroll.leadingAnchor constraintEqualToAnchor:fileTree.leadingAnchor],
        [fileTreeScroll.trailingAnchor constraintEqualToAnchor:fileTree.trailingAnchor],
        [fileTreeScroll.bottomAnchor constraintEqualToAnchor:fileTree.bottomAnchor]
    ]];
    _reviewToolPageOpen = NO;
    _fileToolPageOpen = NO;
    _activeToolPageKind = nil;
    [self rebuildToolTabBar];
    return tool;
}

- (NSView *)toolTabItemWithKind:(NSString *)kind title:(NSString *)title {
    NSView *item = [[NSView alloc] initWithFrame:NSZeroRect];
    item.translatesAutoresizingMaskIntoConstraints = NO;
    PTAnimatedButton *select = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    select.translatesAutoresizingMaskIntoConstraints = NO;
    select.title = @"";
    select.identifier = kind;
    select.target = self;
    select.action = @selector(selectToolPage:);
    select.fillColor = [_activeToolPageKind isEqual:kind] ? PTWarmChipColor() : NSColor.clearColor;
    select.hoverFillColor = PTWarmChipColor();
    select.pressedFillColor = PTWarmBorderColor();
    select.strokeColor = [_activeToolPageKind isEqual:kind] ? PTWarmBorderColor() : NSColor.clearColor;
    select.cornerRadius = 10.0;
    [item addSubview:select];

    NSTextField *label = [self label:title size:11.5 weight:NSFontWeightSemibold
        color:[_activeToolPageKind isEqual:kind] ? NSColor.labelColor : NSColor.secondaryLabelColor];
    [item addSubview:label];
    PTAnimatedButton *close = PTWarmButton(@"×", self, @selector(closeToolPage:));
    close.identifier = kind;
    close.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    close.toolTip = PTL(@"关闭页面", @"Close page");
    [item addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [select.topAnchor constraintEqualToAnchor:item.topAnchor],
        [select.leadingAnchor constraintEqualToAnchor:item.leadingAnchor],
        [select.trailingAnchor constraintEqualToAnchor:item.trailingAnchor],
        [select.bottomAnchor constraintEqualToAnchor:item.bottomAnchor],
        [label.leadingAnchor constraintEqualToAnchor:item.leadingAnchor constant:12],
        [label.centerYAnchor constraintEqualToAnchor:item.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-7],
        [close.trailingAnchor constraintEqualToAnchor:item.trailingAnchor constant:-5],
        [close.centerYAnchor constraintEqualToAnchor:item.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:22],
        [close.heightAnchor constraintEqualToConstant:22]
    ]];
    return item;
}

- (void)rebuildToolTabBar {
    for (NSView *view in _toolTabStack.arrangedSubviews.copy) {
        [_toolTabStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (_reviewToolPageOpen) {
        NSView *review = [self toolTabItemWithKind:@"review"
            title:PTL(@"▣  审查", @"▣  Review")];
        [_toolTabStack addArrangedSubview:review];
        [review.widthAnchor constraintEqualToConstant:148].active = YES;
        [review.heightAnchor constraintEqualToConstant:32].active = YES;
    }
    if (_fileToolPageOpen) {
        NSString *title = _activeFilePreviewPayload[@"title"] ?: PTL(@"打开文件", @"Open File");
        NSView *file = [self toolTabItemWithKind:@"file"
            title:[NSString stringWithFormat:@"▤  %@", title]];
        [_toolTabStack addArrangedSubview:file];
        [file.widthAnchor constraintEqualToConstant:184].active = YES;
        [file.heightAnchor constraintEqualToConstant:32].active = YES;
    }
    BOOL reviewActive = [_activeToolPageKind isEqual:@"review"];
    _toolReviewRefreshButton.hidden = !reviewActive || _gitReviewShowsTranscriptEdits;
}

- (void)showToolPageKind:(NSString *)kind animated:(BOOL)animated {
    if (![kind isEqual:@"review"] && ![kind isEqual:@"file"]) return;
    NSView *incoming = [kind isEqual:@"review"] ? _gitDiffScroll : _filePreviewWebView;
    NSView *outgoing = [_activeToolPageKind isEqual:@"review"] ? _gitDiffScroll :
        ([_activeToolPageKind isEqual:@"file"] ? _filePreviewWebView : nil);
    _activeToolPageKind = [kind copy];
    incoming.hidden = NO;
    if (outgoing == incoming || !outgoing || !animated ||
        NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        if (outgoing != incoming) outgoing.hidden = YES;
        incoming.alphaValue = 1.0;
        [self rebuildToolTabBar];
        return;
    }
    incoming.alphaValue = 0.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        context.timingFunction = [CAMediaTimingFunction functionWithName:
            kCAMediaTimingFunctionEaseInEaseOut];
        outgoing.animator.alphaValue = 0.0;
        incoming.animator.alphaValue = 1.0;
    } completionHandler:^{
        if (![self->_activeToolPageKind isEqual:kind]) return;
        outgoing.hidden = YES;
        outgoing.alphaValue = 1.0;
    }];
    [self rebuildToolTabBar];
}

- (void)selectToolPage:(NSButton *)sender {
    [self showToolPageKind:sender.identifier animated:YES];
}

- (void)closeToolPage:(NSButton *)sender {
    NSString *kind = sender.identifier ?: @"";
    if ([kind isEqual:@"review"]) {
        _reviewToolPageOpen = NO;
        _gitDiffExpanded = NO;
        _gitReviewShowsTranscriptEdits = NO;
        _transcriptEditReviewEvents = nil;
        _gitDiffGeneration++;
        [_gitDiffProgress stopAnimation:nil];
        _gitDiffProgress.hidden = YES;
        _gitDiffRefreshButton.hidden = YES;
        _gitDiffToggleButton.title = PTL(@"打开 Git 审查  ›", @"Open Git Review  ›");
    } else if ([kind isEqual:@"file"]) {
        _fileToolPageOpen = NO;
        _activeFilePreviewPayload = nil;
    }
    if (_reviewToolPageOpen) [self showToolPageKind:@"review" animated:YES];
    else if (_fileToolPageOpen) [self showToolPageKind:@"file" animated:YES];
    else {
        _activeToolPageKind = nil;
        [self rebuildToolTabBar];
        [self setToolWorkspaceExpanded:NO animated:YES];
    }
}

- (void)setFileTreeRootURL:(NSURL *)rootURL {
    if (!rootURL.isFileURL) return;
    BOOL directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:rootURL.path isDirectory:&directory] ||
        !directory) return;
    _fileTreeRootURL = rootURL.URLByStandardizingPath;
    [_fileTreeChildrenByPath removeAllObjects];
    _fileTreeRootButton.title = _fileTreeRootURL.lastPathComponent.length
        ? _fileTreeRootURL.lastPathComponent : _fileTreeRootURL.path;
    _fileTreeRootButton.toolTip = _fileTreeRootURL.path;
    [_fileOutlineView reloadData];
}

- (void)setFileTreeExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (!_fileTreeView || !_fileTreeWidthConstraint) return;
    _fileTreeExpanded = expanded;
    NSUInteger generation = ++_fileTreeAnimationGeneration;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (expanded) {
        CGFloat desired = _fileTreeWidthBeforeCollapse > 0 ? _fileTreeWidthBeforeCollapse : 260.0;
        CGFloat target = desired;
        _fileTreeView.hidden = NO;
        _fileTreeWidthConstraint.active = YES;
        if (_fileTreeWidthConstraint.constant <= 0.0) {
            _fileTreeWidthConstraint.constant = 0.0;
            _fileTreeView.alphaValue = reduceMotion ? 1.0 : 0.0;
            [_window.contentView layoutSubtreeIfNeeded];
        }
        if (!animated || reduceMotion) {
            _fileTreeWidthConstraint.constant = target;
            _fileTreeView.alphaValue = 1.0;
            [_window.contentView layoutSubtreeIfNeeded];
        } else {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.22;
                context.timingFunction = [CAMediaTimingFunction functionWithName:
                    kCAMediaTimingFunctionEaseInEaseOut];
                self->_fileTreeWidthConstraint.animator.constant = target;
                self->_fileTreeView.animator.alphaValue = 1.0;
                [self->_window.contentView layoutSubtreeIfNeeded];
            } completionHandler:nil];
        }
        return;
    }
    CGFloat width = NSWidth(_fileTreeView.frame);
    if (width > 0.0) _fileTreeWidthBeforeCollapse = width;
    if (!animated || reduceMotion) {
        _fileTreeWidthConstraint.constant = 0.0;
        _fileTreeView.alphaValue = 1.0;
        _fileTreeView.hidden = YES;
        [_window.contentView layoutSubtreeIfNeeded];
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        context.timingFunction = [CAMediaTimingFunction functionWithName:
            kCAMediaTimingFunctionEaseInEaseOut];
        self->_fileTreeWidthConstraint.animator.constant = 0.0;
        self->_fileTreeView.animator.alphaValue = 0.0;
        [self->_window.contentView layoutSubtreeIfNeeded];
    } completionHandler:^{
        if (generation != self->_fileTreeAnimationGeneration || self->_fileTreeExpanded) return;
        self->_fileTreeView.hidden = YES;
        self->_fileTreeView.alphaValue = 1.0;
    }];
}

- (void)toggleFileTree:(id)sender {
    (void)sender;
    [self setFileTreeExpanded:!_fileTreeExpanded animated:YES];
}

- (void)chooseFileTreeRoot:(id)sender {
    (void)sender;
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            self->_fileTreeRootManuallySelected = YES;
            self->_fileTreeRootSessionID = [self->_selectedSession.sessionID copy];
            [self setFileTreeRootURL:panel.URL];
        }
    }];
}

- (void)filterFileTree:(id)sender {
    (void)sender;
    [_fileOutlineView reloadData];
}

- (NSArray<NSDictionary *> *)fileTreeChildrenForItem:(NSDictionary *)item {
    NSURL *directoryURL = item ? item[@"url"] : _fileTreeRootURL;
    if (!directoryURL) return @[];
    NSString *cacheKey = directoryURL.path ?: @"";
    NSArray<NSDictionary *> *children = _fileTreeChildrenByPath[cacheKey];
    if (!children) {
        children = PTFileTreeChildren(directoryURL, nil) ?: @[];
        _fileTreeChildrenByPath[cacheKey] = children;
    }
    NSString *query = [_fileTreeSearchField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) return children;
    NSPredicate *predicate = [NSPredicate predicateWithBlock:
        ^BOOL(NSDictionary *child, NSDictionary *bindings) {
            (void)bindings;
            return [child[@"name"] rangeOfString:query
                options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
        }];
    return [children filteredArrayUsingPredicate:predicate];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (outlineView != _fileOutlineView) return 0;
    return [self fileTreeChildrenForItem:[item isKindOfClass:NSDictionary.class] ? item : nil].count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (outlineView != _fileOutlineView) return nil;
    NSArray *children = [self fileTreeChildrenForItem:
        [item isKindOfClass:NSDictionary.class] ? item : nil];
    return index >= 0 && index < (NSInteger)children.count ? children[index] : nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return outlineView == _fileOutlineView &&
        [item isKindOfClass:NSDictionary.class] && [item[@"directory"] boolValue];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView
     viewForTableColumn:(NSTableColumn *)tableColumn
                  item:(id)item {
    (void)tableColumn;
    if (outlineView != _fileOutlineView || ![item isKindOfClass:NSDictionary.class]) return nil;
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"file-tree-cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"file-tree-cell";
        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.imageScaling = NSImageScaleProportionallyDown;
        cell.imageView = icon;
        [cell addSubview:icon];
        NSTextField *name = [NSTextField labelWithString:@""];
        name.translatesAutoresizingMaskIntoConstraints = NO;
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        name.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
        cell.textField = name;
        [cell addSubview:name];
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:16],
            [icon.heightAnchor constraintEqualToConstant:16],
            [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:7],
            [name.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
            [name.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    BOOL directory = [item[@"directory"] boolValue];
    cell.textField.stringValue = item[@"name"] ?: @"";
    cell.textField.toolTip = [item[@"url"] path];
    cell.imageView.image = [NSImage imageWithSystemSymbolName:directory ? @"folder" : @"doc.text"
        accessibilityDescription:directory ? PTL(@"文件夹", @"Folder") : PTL(@"文件", @"File")];
    cell.imageView.contentTintColor = directory ? PTWarmAccentColor() : NSColor.secondaryLabelColor;
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object != _fileOutlineView) return;
    NSInteger row = _fileOutlineView.selectedRow;
    if (row < 0) return;
    NSDictionary *item = [_fileOutlineView itemAtRow:row];
    if (![item isKindOfClass:NSDictionary.class]) return;
    if ([item[@"directory"] boolValue]) {
        if ([_fileOutlineView isItemExpanded:item]) [_fileOutlineView collapseItem:item];
        else [_fileOutlineView expandItem:item];
        return;
    }
    NSURL *url = item[@"url"];
    if ([url isKindOfClass:NSURL.class]) [self openPreviewFileURL:url];
}

- (void)renderActiveFilePreview {
    if (!_filePreviewWebReady) return;
    if (!_activeFilePreviewPayload) {
        [_filePreviewWebView evaluateJavaScript:@"document.body.classList.add('file-preview-mode');document.getElementById('content').innerHTML='<div class=\"file-empty\"><div>▱</div><h2>打开文件</h2><p>从右侧目录树选择文件</p></div>';" completionHandler:nil];
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:_activeFilePreviewPayload options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (!json) return;
    NSString *script = [NSString stringWithFormat:
        @"window.PrettyTermRenderer.renderFilePreview(%@); null;", json];
    [_filePreviewWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        if (error) self->_statusLabel.stringValue = PTL(@"文件预览显示失败", @"File preview display failed");
    }];
}

- (void)openFileWorkspace:(id)sender {
    (void)sender;
    if (![_fileTreeRootSessionID isEqual:_selectedSession.sessionID]) {
        _fileTreeRootManuallySelected = NO;
        _fileTreeRootSessionID = [_selectedSession.sessionID copy];
    }
    if (!_fileTreeRootManuallySelected &&
        (!_fileTreeRootURL || ![_fileTreeRootURL.path isEqual:_selectedSession.cwd])) {
        NSString *cwd = _selectedSession.cwd.stringByStandardizingPath;
        if (cwd.length > 0) [self setFileTreeRootURL:[NSURL fileURLWithPath:cwd isDirectory:YES]];
    }
    void (^openFiles)(void) = ^{
        self->_fileToolPageOpen = YES;
        [self showToolPageKind:@"file" animated:YES];
        [self setToolWorkspaceExpanded:YES animated:YES];
        [self setFileTreeExpanded:YES animated:YES];
        [self rebuildToolTabBar];
    };
    openFiles();
}

- (void)openPreviewFileURL:(NSURL *)url {
    NSError *error = nil;
    NSDictionary<NSString *, NSString *> *payload = PTFilePreviewPayloadForURL(url, &error);
    if (!payload) {
        _statusLabel.stringValue = error.localizedDescription ?: PTL(@"这个文件不提供预览", @"Preview is unavailable for this file");
        return;
    }
    _activeFilePreviewPayload = payload;
    void (^openFile)(void) = ^{
        self->_fileToolPageOpen = YES;
        [self showToolPageKind:@"file" animated:YES];
        [self setToolWorkspaceExpanded:YES animated:YES];
        [self rebuildToolTabBar];
        [self renderActiveFilePreview];
    };
    openFile();
}

- (NSView *)buildConversation {
    PTAppearanceSurfaceView *workspace = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    workspace.translatesAutoresizingMaskIntoConstraints = NO;
    workspace.surfaceStyle = PTAppearanceSurfaceStyleCanvas;

    PTWorkspaceSplitView *workspaceSplit = [[PTWorkspaceSplitView alloc] initWithFrame:NSZeroRect];
    workspaceSplit.translatesAutoresizingMaskIntoConstraints = NO;
    workspaceSplit.vertical = YES;
    workspaceSplit.dividerStyle = NSSplitViewDividerStyleThin;
    workspaceSplit.delegate = self;
    _workspaceSplitView = workspaceSplit;
    [workspace addSubview:workspaceSplit];

    PTAppearanceSurfaceView *pane = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    pane.surfaceStyle = PTAppearanceSurfaceStyleCanvas;
    _conversationPane = pane;

    NSVisualEffectView *header = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.material = NSVisualEffectMaterialHeaderView;
    header.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    header.state = NSVisualEffectStateActive;
    [pane addSubview:header];

    _conversationTitle = [self label:PTL(@"选择一个 Claude 会话", @"Select a conversation") size:14 weight:NSFontWeightBold color:NSColor.labelColor];
    [_conversationTitle setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addSubview:_conversationTitle];
    _conversationDetail = [self label:PTL(@"显示老师和 Claude 的文本对话", @"Claude transcript view") size:10.5 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [_conversationDetail setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addSubview:_conversationDetail];

    _modelPicker = [[PTWarmPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _modelPicker.translatesAutoresizingMaskIntoConstraints = NO;
    _modelPicker.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _modelPicker.target = self;
    _modelPicker.action = @selector(changeModel:);
    [_modelPicker addItemWithTitle:PTL(@"当前模型", @"Current model")];
    NSArray<NSArray<NSString *> *> *models = @[
        @[@"Claude Fable 5", @"claude-fable-5"],
        @[@"Claude Opus 5.5", @"claude-opus-5-5"],
        @[@"Claude Sonnet 5", @"claude-sonnet-5"],
        @[@"Claude Sonnet 4.6", @"claude-sonnet-4-6"],
        @[@"Claude Haiku 4.5", @"claude-haiku-4-5"]
    ];
    for (NSArray<NSString *> *entry in models) {
        [_modelPicker addItemWithTitle:entry[0]];
        _modelPicker.lastItem.representedObject = entry[1];
    }
    _modelPicker.enabled = NO;

    _remoteButton = PTWarmButton(@"Remote", self, @selector(enableRemoteControl:));
    _remoteButton.enabled = NO;
    _remoteButton.toolTip = PTL(@"在 Claude.ai 继续当前会话", @"Continue the current conversation on Claude.ai");
    [header addSubview:_remoteButton];

    _compactButton = PTWarmButton(@"Compact", self, @selector(compactConversation:));
    _compactButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    _compactButton.enabled = NO;
    _compactButton.toolTip = PTL(@"向当前 Claude Code 会话发送 /compact", @"Send /compact to the current Claude Code conversation");
    [header addSubview:_compactButton];

    _inspectorToggleButton = PTWarmButton(@"", self, @selector(toggleInspector:));
    _inspectorToggleButton.image = [NSImage imageWithSystemSymbolName:@"list.bullet" accessibilityDescription:PTL(@"检查器摘要", @"Inspector summary")];
    _inspectorToggleButton.toolTip = PTL(@"显示或收起检查器", @"Show or collapse the inspector");
    [header addSubview:_inspectorToggleButton];

    _connectButton = PTWarmButton(PTL(@"连接 Claude", @"Sync"), self, @selector(connectSelectedSession:));
    _connectButton.contentTintColor = PTWarmAccentColor();
    _connectButton.enabled = NO;
    _connectButton.toolTip = PTL(@"连接选中的 Claude Code 后台会话", @"Connect the selected Claude Code conversation");
    [header addSubview:_connectButton];

    PTAnimatedButton *floatingButton = PTWarmButton(@"", self, @selector(toggleFloatingConversation:));
    floatingButton.image = [NSImage imageWithSystemSymbolName:@"pin"
        accessibilityDescription:PTL(@"悬浮当前对话", @"Float current conversation")];
    _floatingButton = floatingButton;
    _floatingButton.toolTip = PTL(@"悬浮当前对话（⌘O）", @"Float current conversation (⌘O)");
    _floatingButton.enabled = NO;
    [header addSubview:_floatingButton];

    _workspaceTabScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _workspaceTabScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _workspaceTabScroll.drawsBackground = NO;
    _workspaceTabScroll.borderType = NSNoBorder;
    _workspaceTabScroll.hasHorizontalScroller = NO;
    _workspaceTabScroll.hasVerticalScroller = NO;
    _workspaceTabScroll.autohidesScrollers = YES;
    [pane addSubview:_workspaceTabScroll];

    _workspaceTabStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _workspaceTabStack.translatesAutoresizingMaskIntoConstraints = NO;
    _workspaceTabStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _workspaceTabStack.alignment = NSLayoutAttributeCenterY;
    _workspaceTabStack.spacing = 6;
    _workspaceTabStack.edgeInsets = NSEdgeInsetsMake(5, 10, 5, 10);
    _workspaceTabScroll.documentView = _workspaceTabStack;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    [configuration.userContentController addScriptMessageHandler:self name:@"quoteSelection"];
    [configuration.userContentController addScriptMessageHandler:self name:@"openTranscriptEditReview"];
    [configuration.userContentController addScriptMessageHandler:self name:@"openTranscriptFile"];
    [configuration.userContentController addScriptMessageHandler:self name:@"answerQuestion"];
    [configuration.userContentController addScriptMessageHandler:self name:@"copyAssistantOutput"];
    _conversationView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    _conversationView.translatesAutoresizingMaskIntoConstraints = NO;
    _conversationView.navigationDelegate = self;
    if (@available(macOS 12.0, *)) _conversationView.underPageBackgroundColor = NSColor.clearColor;
    [pane addSubview:_conversationView];
    NSURL *htmlURL = [NSBundle.mainBundle URLForResource:@"index" withExtension:@"html"];
    if (htmlURL) [_conversationView loadFileURL:htmlURL allowingReadAccessToURL:NSBundle.mainBundle.resourceURL];

    PTAppearanceSurfaceView *composerBar = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    composerBar.translatesAutoresizingMaskIntoConstraints = NO;
    composerBar.surfaceStyle = PTAppearanceSurfaceStyleCanvas;
    [pane addSubview:composerBar];

    _composerTargetLabel = [self label:PTL(@"发送给当前会话", @"Send to the current conversation") size:10.5 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [composerBar addSubview:_composerTargetLabel];

    _imagePreviewScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _imagePreviewScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _imagePreviewScroll.drawsBackground = NO;
    _imagePreviewScroll.hasHorizontalScroller = YES;
    _imagePreviewScroll.hasVerticalScroller = NO;
    _imagePreviewScroll.autohidesScrollers = YES;
    _imagePreviewScroll.hidden = YES;
    _composerSurface = [[PTComposerDropSurfaceView alloc] initWithFrame:NSZeroRect];
    _composerSurface.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _composerSurface.dropHandler = ^BOOL(NSArray<NSURL *> *urls) {
        return [weakSelf addComposerAttachmentURLs:urls floating:NO];
    };
    [composerBar addSubview:_composerSurface];

    [_composerSurface addSubview:_imagePreviewScroll];

    _imagePreviewStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _imagePreviewStack.translatesAutoresizingMaskIntoConstraints = NO;
    _imagePreviewStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _imagePreviewStack.alignment = NSLayoutAttributeCenterY;
    _imagePreviewStack.spacing = 7;
    _imagePreviewStack.edgeInsets = NSEdgeInsetsMake(2, 0, 2, 0);
    _imagePreviewScroll.documentView = _imagePreviewStack;

    PTAnimatedButton *addButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    addButton.title = @"＋";
    addButton.font = [NSFont systemFontOfSize:25 weight:NSFontWeightLight];
    addButton.contentTintColor = NSColor.labelColor;
    addButton.fillColor = NSColor.clearColor;
    addButton.hoverFillColor = PTWarmChipColor();
    addButton.pressedFillColor = PTWarmBorderColor();
    addButton.cornerRadius = 19;
    addButton.target = self;
    addButton.action = @selector(chooseAttachments:);
    _imageButton = addButton;
    _imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _imageButton.toolTip = PTL(@"添加文件或图片，也可以直接拖入", @"Add files or images, or drag them here");
    _imageButton.enabled = NO;
    [_composerSurface addSubview:_imageButton];

    NSScrollView *composerScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    composerScroll.translatesAutoresizingMaskIntoConstraints = NO;
    composerScroll.borderType = NSNoBorder;
    composerScroll.hasVerticalScroller = YES;
    composerScroll.autohidesScrollers = YES;
    composerScroll.drawsBackground = NO;
    [_composerSurface addSubview:composerScroll];

    _composerTextView = [[PTComposerTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 52)];
    _composerTextView.font = [NSFont systemFontOfSize:15 weight:NSFontWeightRegular];
    _composerTextView.drawsBackground = NO;
    _composerTextView.richText = NO;
    _composerTextView.allowsUndo = YES;
    _composerTextView.verticallyResizable = YES;
    _composerTextView.horizontallyResizable = NO;
    _composerTextView.textContainer.widthTracksTextView = YES;
    _composerTextView.textContainerInset = NSMakeSize(7, 9);
    _composerTextView.placeholderText = PTL(@"给 Claude 发消息", @"Message Claude");
    _composerTextView.editable = YES;
    _composerTextView.submitHandler = ^{
        [weakSelf sendMessage:nil];
    };
    _composerTextView.commandMenuHandler = ^{
        PTAppDelegate *self = weakSelf;
        if (self) [self updateClaudeCommandsForComposer:self->_composerTextView];
    };
    _composerTextView.commandKeyHandler = ^BOOL(NSEvent *event) {
        PTAppDelegate *self = weakSelf;
        return self ? [self handleCommandKey:event composer:self->_composerTextView] : NO;
    };
    _composerTextView.imagePasteHandler = ^BOOL(NSPasteboard *pasteboard) {
        return [weakSelf handleImagePasteboard:pasteboard];
    };
    _composerTextView.fileDropHandler = ^BOOL(NSArray<NSURL *> *urls) {
        return [weakSelf addComposerAttachmentURLs:urls floating:NO];
    };
    composerScroll.documentView = _composerTextView;

    _composerEffortButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    _composerEffortButton.title = PTL(@"推理强度⌄", @"Effort⌄");
    _composerEffortButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _composerEffortButton.contentTintColor = NSColor.secondaryLabelColor;
    _composerEffortButton.fillColor = NSColor.clearColor;
    _composerEffortButton.hoverFillColor = PTWarmChipColor();
    _composerEffortButton.pressedFillColor = PTWarmBorderColor();
    _composerEffortButton.cornerRadius = 17;
    _composerEffortButton.target = self;
    _composerEffortButton.action = @selector(showComposerOptions:);
    _composerEffortButton.translatesAutoresizingMaskIntoConstraints = NO;
    _composerEffortButton.enabled = NO;
    [_composerSurface addSubview:_composerEffortButton];

    PTAnimatedButton *sendButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    sendButton.title = @"↑";
    sendButton.font = [NSFont systemFontOfSize:23 weight:NSFontWeightMedium];
    sendButton.contentTintColor = NSColor.whiteColor;
    sendButton.fillColor = PTColor(0.12, 0.11, 0.10);
    sendButton.hoverFillColor = PTWarmAccentColor();
    sendButton.pressedFillColor = PTColor(0.45, 0.18, 0.06);
    sendButton.cornerRadius = 22;
    sendButton.target = self;
    sendButton.action = @selector(sendMessage:);
    _sendButton = sendButton;
    _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    _sendButton.toolTip = PTL(@"发送消息", @"Send message");
    _sendButton.enabled = NO;
    [_composerSurface addSubview:_sendButton];

    NSVisualEffectView *statusBar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    statusBar.material = NSVisualEffectMaterialHeaderView;
    statusBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    statusBar.state = NSVisualEffectStateActive;
    [pane addSubview:statusBar];
    _bottomStatusLabel = [self label:PTL(@"Claude Code 后台执行", @"Claude Code runs in the background") size:10 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [statusBar addSubview:_bottomStatusLabel];

    _composerHeightConstraint = [composerBar.heightAnchor constraintEqualToConstant:112];
    _imagePreviewHeightConstraint = [_imagePreviewScroll.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:pane.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:60],
        [_conversationTitle.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:18],
        [_conversationTitle.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
        [_conversationDetail.leadingAnchor constraintEqualToAnchor:_conversationTitle.leadingAnchor],
        [_conversationDetail.topAnchor constraintEqualToAnchor:_conversationTitle.bottomAnchor constant:2],
        [_connectButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-14],
        [_connectButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_connectButton.widthAnchor constraintEqualToConstant:84],
        [_compactButton.trailingAnchor constraintEqualToAnchor:_connectButton.leadingAnchor constant:-8],
        [_compactButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_compactButton.widthAnchor constraintEqualToConstant:68],
        [_floatingButton.trailingAnchor constraintEqualToAnchor:_compactButton.leadingAnchor constant:-8],
        [_floatingButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_floatingButton.widthAnchor constraintEqualToConstant:34],
        [_floatingButton.heightAnchor constraintEqualToConstant:28],
        [_remoteButton.trailingAnchor constraintEqualToAnchor:_floatingButton.leadingAnchor constant:-8],
        [_remoteButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [_remoteButton.widthAnchor constraintEqualToConstant:60],
        [_conversationTitle.trailingAnchor constraintLessThanOrEqualToAnchor:_remoteButton.leadingAnchor constant:-12],
        [_conversationDetail.trailingAnchor constraintLessThanOrEqualToAnchor:_remoteButton.leadingAnchor constant:-12],

        [_workspaceTabScroll.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [_workspaceTabScroll.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [_workspaceTabScroll.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [_workspaceTabScroll.heightAnchor constraintEqualToConstant:44],
        [_workspaceTabStack.leadingAnchor constraintEqualToAnchor:_workspaceTabScroll.contentView.leadingAnchor],
        [_workspaceTabStack.topAnchor constraintEqualToAnchor:_workspaceTabScroll.contentView.topAnchor],
        [_workspaceTabStack.bottomAnchor constraintEqualToAnchor:_workspaceTabScroll.contentView.bottomAnchor],

        [composerBar.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [composerBar.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [composerBar.bottomAnchor constraintEqualToAnchor:statusBar.topAnchor],
        _composerHeightConstraint,
        [_composerTargetLabel.leadingAnchor constraintEqualToAnchor:_composerSurface.leadingAnchor constant:4],
        [_composerTargetLabel.topAnchor constraintEqualToAnchor:composerBar.topAnchor constant:8],
        [_composerSurface.centerXAnchor constraintEqualToAnchor:composerBar.centerXAnchor],
        [_composerSurface.leadingAnchor constraintGreaterThanOrEqualToAnchor:composerBar.leadingAnchor constant:14],
        [_composerSurface.widthAnchor constraintLessThanOrEqualToConstant:800],
        [_composerSurface.topAnchor constraintEqualToAnchor:_composerTargetLabel.bottomAnchor constant:6],
        [_composerSurface.bottomAnchor constraintEqualToAnchor:composerBar.bottomAnchor constant:-10],
        [_imagePreviewScroll.leadingAnchor constraintEqualToAnchor:_composerSurface.leadingAnchor constant:12],
        [_imagePreviewScroll.trailingAnchor constraintEqualToAnchor:_composerSurface.trailingAnchor constant:-12],
        [_imagePreviewScroll.topAnchor constraintEqualToAnchor:_composerSurface.topAnchor constant:7],
        _imagePreviewHeightConstraint,
        [_imagePreviewStack.leadingAnchor constraintEqualToAnchor:_imagePreviewScroll.contentView.leadingAnchor],
        [_imagePreviewStack.topAnchor constraintEqualToAnchor:_imagePreviewScroll.contentView.topAnchor],
        [_imagePreviewStack.bottomAnchor constraintEqualToAnchor:_imagePreviewScroll.contentView.bottomAnchor],
        [_imageButton.leadingAnchor constraintEqualToAnchor:_composerSurface.leadingAnchor constant:10],
        [_imageButton.widthAnchor constraintEqualToConstant:38],
        [_imageButton.heightAnchor constraintEqualToConstant:38],
        [composerScroll.leadingAnchor constraintEqualToAnchor:_imageButton.trailingAnchor constant:6],
        [composerScroll.topAnchor constraintEqualToAnchor:_imagePreviewScroll.bottomAnchor constant:2],
        [composerScroll.bottomAnchor constraintEqualToAnchor:_composerSurface.bottomAnchor constant:-7],
        [_imageButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [composerScroll.trailingAnchor constraintEqualToAnchor:_composerEffortButton.leadingAnchor constant:-5],
        [_composerEffortButton.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-6],
        [_composerEffortButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [_composerEffortButton.widthAnchor constraintEqualToConstant:92],
        [_composerEffortButton.heightAnchor constraintEqualToConstant:34],
        [_sendButton.trailingAnchor constraintEqualToAnchor:_composerSurface.trailingAnchor constant:-10],
        [_sendButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [_sendButton.widthAnchor constraintEqualToConstant:44],
        [_sendButton.heightAnchor constraintEqualToConstant:44],
        [statusBar.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [statusBar.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [statusBar.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor],
        [statusBar.heightAnchor constraintEqualToConstant:26],
        [_bottomStatusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:18],
        [_bottomStatusLabel.trailingAnchor constraintEqualToAnchor:statusBar.trailingAnchor constant:-16],
        [_bottomStatusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],

        [_conversationView.topAnchor constraintEqualToAnchor:_workspaceTabScroll.bottomAnchor],
        [_conversationView.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor],
        [_conversationView.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [_conversationView.bottomAnchor constraintEqualToAnchor:composerBar.topAnchor]
    ]];
    NSLayoutConstraint *readingWidth = [_composerSurface.widthAnchor constraintEqualToAnchor:composerBar.widthAnchor constant:-28];
    readingWidth.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    readingWidth.active = YES;
    [self updateWorkspaceTabBar];
    [self buildHomeInPane:pane];
    NSView *toolWorkspace = [self buildToolWorkspace];
    [workspaceSplit addArrangedSubview:pane];
    _toolWorkspaceWidthConstraint = [toolWorkspace.widthAnchor constraintEqualToConstant:0.0];
    _toolWorkspaceWidthConstraint.priority = 999;
    _toolWorkspaceWidthConstraint.active = YES;
    toolWorkspace.hidden = YES;
    _toolWorkspaceWidthBeforeCollapse = 620.0;
    [NSLayoutConstraint activateConstraints:@[
        [workspaceSplit.topAnchor constraintEqualToAnchor:workspace.topAnchor],
        [workspaceSplit.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor],
        [workspaceSplit.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor],
        [workspaceSplit.bottomAnchor constraintEqualToAnchor:workspace.bottomAnchor]
    ]];
    return workspace;
}

- (void)buildHomeInPane:(NSView *)pane {
    NSString *draft = _homePromptTextView.string ?: @"";
    PTAppearanceSurfaceView *home = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    home.translatesAutoresizingMaskIntoConstraints = NO;
    home.surfaceStyle = PTAppearanceSurfaceStyleCanvas;
    home.hidden = !_homeVisible;
    _homeView = home;
    [pane addSubview:home];
    PTAnimatedButton *back = PTWarmButton(PTL(@"返回会话", @"Back to conversation"), self, @selector(hideHome:));
    [home addSubview:back];
    PTAnimatedButton *newConversation = PTWarmButton(PTL(@"＋ 新建对话", @"＋ New conversation"), self, @selector(startBlankHomeConversation:));
    [home addSubview:newConversation];

    NSView *welcome = [NSView new];
    welcome.translatesAutoresizingMaskIntoConstraints = NO;
    [home addSubview:welcome];
    NSImageView *icon = [NSImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [NSImage imageNamed:@"PrettyTermLogo"];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [welcome addSubview:icon];
    _homeTitleLabel = [self label:@"" size:26 weight:NSFontWeightMedium color:NSColor.labelColor];
    _homeTitleLabel.alignment = NSTextAlignmentCenter;
    _homeTitleLabel.maximumNumberOfLines = 0;
    _homeTitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [welcome addSubview:_homeTitleLabel];
    NSTextField *subtitle = [self label:PTL(@"从一个想法，开始新的对话", @"Start a new conversation with an idea")
        size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    subtitle.alignment = NSTextAlignmentCenter;
    [welcome addSubview:subtitle];

    NSView *inputArea = [NSView new];
    inputArea.translatesAutoresizingMaskIntoConstraints = NO;
    [home addSubview:inputArea];
    _homeProjectPicker = [[PTWarmPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _homeProjectPicker.translatesAutoresizingMaskIntoConstraints = NO;
    _homeProjectPicker.target = self;
    _homeProjectPicker.action = @selector(changeHomeProject:);
    [inputArea addSubview:_homeProjectPicker];
    PTComposerDropSurfaceView *card = [[PTComposerDropSurfaceView alloc] initWithFrame:NSZeroRect];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [inputArea addSubview:card];
    NSScrollView *scroll = [NSScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    [card addSubview:scroll];
    _homePromptTextView = [[PTComposerTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 90)];
    _homePromptTextView.font = [NSFont systemFontOfSize:16];
    _homePromptTextView.drawsBackground = NO;
    _homePromptTextView.richText = NO;
    _homePromptTextView.allowsUndo = YES;
    _homePromptTextView.verticallyResizable = YES;
    _homePromptTextView.horizontallyResizable = NO;
    _homePromptTextView.textContainer.widthTracksTextView = YES;
    _homePromptTextView.textContainerInset = NSMakeSize(8, 10);
    _homePromptTextView.placeholderText = PTL(@"随心输入，开始新的对话", @"Ask anything to start a new conversation");
    _homePromptTextView.string = draft;
    __weak typeof(self) weakSelf = self;
    _homePromptTextView.submitHandler = ^{ [weakSelf startHomeConversation:nil]; };
    scroll.documentView = _homePromptTextView;
    PTAnimatedButton *send = PTWarmButton(@"↑", self, @selector(startHomeConversation:));
    send.font = [NSFont systemFontOfSize:23 weight:NSFontWeightMedium];
    send.fillColor = PTColor(0.12, 0.11, 0.10);
    send.contentTintColor = NSColor.whiteColor;
    send.cornerRadius = 22;
    [card addSubview:send];
    NSTextField *engine = [self label:@"Claude Code" size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [card addSubview:engine];
    _homeStatusLabel = [self label:@"" size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    _homeStatusLabel.maximumNumberOfLines = 2;
    _homeStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [inputArea addSubview:_homeStatusLabel];
    NSLayoutConstraint *width = [inputArea.widthAnchor constraintEqualToAnchor:home.widthAnchor constant:-64];
    width.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    [NSLayoutConstraint activateConstraints:@[
        [home.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor], [home.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor],
        [home.topAnchor constraintEqualToAnchor:pane.topAnchor], [home.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor],
        [back.topAnchor constraintEqualToAnchor:home.topAnchor constant:16], [back.trailingAnchor constraintEqualToAnchor:home.trailingAnchor constant:-20],
        [newConversation.topAnchor constraintEqualToAnchor:home.topAnchor constant:16], [newConversation.leadingAnchor constraintEqualToAnchor:home.leadingAnchor constant:20],
        [welcome.centerXAnchor constraintEqualToAnchor:home.centerXAnchor], [welcome.centerYAnchor constraintEqualToAnchor:home.centerYAnchor constant:-80],
        [welcome.widthAnchor constraintEqualToAnchor:home.widthAnchor constant:-48],
        [icon.topAnchor constraintEqualToAnchor:welcome.topAnchor], [icon.centerXAnchor constraintEqualToAnchor:welcome.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:54], [icon.heightAnchor constraintEqualToConstant:54],
        [_homeTitleLabel.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:24],
        [_homeTitleLabel.leadingAnchor constraintEqualToAnchor:welcome.leadingAnchor], [_homeTitleLabel.trailingAnchor constraintEqualToAnchor:welcome.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:_homeTitleLabel.bottomAnchor constant:12],
        [subtitle.centerXAnchor constraintEqualToAnchor:welcome.centerXAnchor], [subtitle.bottomAnchor constraintEqualToAnchor:welcome.bottomAnchor],
        [inputArea.centerXAnchor constraintEqualToAnchor:home.centerXAnchor], width, [inputArea.widthAnchor constraintLessThanOrEqualToConstant:800],
        [inputArea.bottomAnchor constraintEqualToAnchor:home.bottomAnchor constant:-28],
        [_homeProjectPicker.topAnchor constraintEqualToAnchor:inputArea.topAnchor], [_homeProjectPicker.leadingAnchor constraintEqualToAnchor:inputArea.leadingAnchor constant:8],
        [_homeProjectPicker.widthAnchor constraintLessThanOrEqualToAnchor:inputArea.widthAnchor constant:-16], [_homeProjectPicker.heightAnchor constraintEqualToConstant:32],
        [card.topAnchor constraintEqualToAnchor:_homeProjectPicker.bottomAnchor constant:10],
        [card.leadingAnchor constraintEqualToAnchor:inputArea.leadingAnchor], [card.trailingAnchor constraintEqualToAnchor:inputArea.trailingAnchor], [card.heightAnchor constraintEqualToConstant:164],
        [scroll.topAnchor constraintEqualToAnchor:card.topAnchor constant:12], [scroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [scroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14], [scroll.bottomAnchor constraintEqualToAnchor:send.topAnchor constant:-6],
        [send.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12], [send.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
        [send.widthAnchor constraintEqualToConstant:44], [send.heightAnchor constraintEqualToConstant:44],
        [engine.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22], [engine.centerYAnchor constraintEqualToAnchor:send.centerYAnchor],
        [_homeStatusLabel.leadingAnchor constraintEqualToAnchor:inputArea.leadingAnchor constant:8], [_homeStatusLabel.trailingAnchor constraintEqualToAnchor:inputArea.trailingAnchor constant:-8],
        [_homeStatusLabel.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:8], [_homeStatusLabel.bottomAnchor constraintEqualToAnchor:inputArea.bottomAnchor]
    ]];
    [self updateHomeProjects];
}

- (void)updateHomeProjects {
    [_homeProjectPicker removeAllItems];
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    if (_homeProjectPath.length) [paths addObject:_homeProjectPath];
    for (PTSessionInfo *session in _sessions) if (session.cwd.length) [paths addObject:session.cwd];
    if (!_homeProjectPath.length) [_homeProjectPicker addItemWithTitle:PTL(@"选择项目", @"Choose a project")];
    for (NSString *path in paths) {
        [_homeProjectPicker addItemWithTitle:[NSString stringWithFormat:@"%@  ·  %@", path.lastPathComponent, path.stringByDeletingLastPathComponent]];
        _homeProjectPicker.lastItem.representedObject = path;
        _homeProjectPicker.lastItem.toolTip = path;
        _homeProjectPicker.lastItem.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:nil];
    }
    [_homeProjectPicker.menu addItem:NSMenuItem.separatorItem];
    [_homeProjectPicker addItemWithTitle:PTL(@"选择文件夹…", @"Choose folder…")];
    _homeProjectPicker.lastItem.tag = 1;
    for (NSMenuItem *item in _homeProjectPicker.itemArray)
        if ([item.representedObject isEqual:_homeProjectPath]) [_homeProjectPicker selectItem:item];
    _homeTitleLabel.stringValue = _homeProjectPath.length
        ? [NSString stringWithFormat:PTL(@"想在 %@ 中做些什么？", @"What would you like to do in %@?"), _homeProjectPath.lastPathComponent]
        : PTL(@"今天，想一起做些什么？", @"What would you like to work on today?");
}

- (void)showHome:(id)sender {
    (void)sender;
    [self dismissCommandPalette];
    if (!_homeProjectPath.length) _homeProjectPath = [_selectedSession.cwd copy];
    [self updateHomeProjects];
    _homeVisible = YES;
    _homeView.hidden = NO;
    [_window makeFirstResponder:_homePromptTextView];
}

- (void)hideHome:(id)sender {
    (void)sender;
    _homeVisible = NO;
    _homeView.hidden = YES;
    [_window makeFirstResponder:_composerTextView];
}

- (void)chooseHomeFolderThen:(void (^)(void))completion {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) self->_homeProjectPath = panel.URL.path;
        [self updateHomeProjects];
        if (result == NSModalResponseOK && completion) completion();
    }];
}

- (void)changeHomeProject:(NSPopUpButton *)sender {
    if (sender.selectedItem.tag == 1) { [self chooseHomeFolderThen:nil]; return; }
    if ([sender.selectedItem.representedObject isKindOfClass:NSString.class]) _homeProjectPath = sender.selectedItem.representedObject;
    [self updateHomeProjects];
}

- (PTClaudeBridge *)newHomeBridge { return [PTClaudeBridge new]; }

- (void)startBlankHomeConversation:(id)sender {
    (void)sender;
    if (_homeStartingBridge) return;
    if (!_homeProjectPath.length) {
        [self chooseHomeFolderThen:^{ [self startBlankHomeConversation:nil]; }];
        return;
    }
    _homeSubmittedPrompt = nil;
    _homeBlankSessionDirectory = [_homeProjectPath copy];
    _homeStartingBridge = [self newHomeBridge];
    _homeStatusLabel.stringValue = PTL(@"正在启动新对话…", @"Starting a new conversation…");
    __weak typeof(self) weakSelf = self;
    _homeStartingBridge.statusChanged = ^(NSString *status) { [weakSelf homeLaunchStatusChanged:status]; };
    [_homeStartingBridge startNewSessionInDirectory:_homeBlankSessionDirectory];
}

- (void)homeLaunchStatusChanged:(NSString *)status {
    _homeStatusLabel.stringValue = status ?: @"";
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
            [self rebuildSessionSidebarRows];
            [_sessionTable reloadData];
        }
    }
    [_store refresh];
    [self finishHomeSessionIfAvailable];
}

- (void)startHomeConversation:(id)sender {
    (void)sender;
    NSString *prompt = _homePromptTextView.string ?: @"";
    if (!prompt.length || _homeStartingBridge) return;
    if (!_homeProjectPath.length) {
        [self chooseHomeFolderThen:^{ [self startHomeConversation:nil]; }];
        return;
    }
    PTSessionInfo *session = [PTSessionInfo new];
    session.sessionID = NSUUID.UUID.UUIDString.lowercaseString;
    session.cwd = _homeProjectPath;
    _homeStartingSessionID = session.sessionID;
    _homeSubmittedPrompt = [prompt copy];
    _homeStartingBridge = [self newHomeBridge];
    _homeStatusLabel.stringValue = PTL(@"正在启动新对话…", @"Starting a new conversation…");
    __weak typeof(self) weakSelf = self;
    _homeStartingBridge.statusChanged = ^(NSString *status) { [weakSelf homeLaunchStatusChanged:status]; };
    [_homeStartingBridge startNewSession:session prompt:prompt];
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
    if (_homeSubmittedPrompt) [_homePromptTextView clearAfterSuccessfulSubmissionMatchingText:_homeSubmittedPrompt];
    _homeStartingSessionID = nil;
    _homeStartingBridge = nil;
    _homeSubmittedPrompt = nil;
    _homeBlankSessionDirectory = nil;
    _homeStatusLabel.stringValue = @"";
    if (_homeVisible) {
        [self hideHome:nil];
        [self activateWorkspaceTab:tab animated:YES];
    } else [self updateWorkspaceTabBar];
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
        [self updateConnectButtonTitle];
        return;
    }
    completion(nil);
}

- (void)presentClaudeWaiting:(BOOL)waiting forSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    NSString *script = [NSString stringWithFormat:
        @"window.setClaudeWaiting && window.setClaudeWaiting(%@); null;",
        waiting ? @"true" : @"false"];
    if (_webReady && [_selectedSession.sessionID isEqual:sessionID]) {
        [_conversationView evaluateJavaScript:script completionHandler:nil];
    }
    if (_floatingWebReady && _floatingPanel.visible && [_floatingSessionID isEqual:sessionID]) {
        [_floatingConversationView evaluateJavaScript:script completionHandler:nil];
    }
}

- (void)presentClaudeStreamForBridge:(PTClaudeBridge *)bridge {
    if (!bridge.sessionID.length) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:bridge.streamPayload options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *script = [NSString stringWithFormat:@"window.setClaudeStream(%@); null;", json];
    if (_webReady && [_selectedSession.sessionID isEqual:bridge.sessionID])
        [_conversationView evaluateJavaScript:script completionHandler:nil];
    if (_floatingWebReady && _floatingPanel.visible && [_floatingSessionID isEqual:bridge.sessionID])
        [_floatingConversationView evaluateJavaScript:script completionHandler:nil];
}

- (void)beginAwaitingClaudeReplyForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    if (!_awaitingClaudeBaselineBySessionID) {
        _awaitingClaudeBaselineBySessionID = [NSMutableDictionary dictionary];
    }
    PTSessionInfo *session = [self sessionWithID:sessionID];
    _awaitingClaudeBaselineBySessionID[sessionID] = @(session.assistantMessages.count);
    [self presentClaudeWaiting:YES forSessionID:sessionID];
    [self refreshAgentStateAndControls];
}

- (void)finishAwaitingClaudeReplyForSessionID:(NSString *)sessionID {
    if (!_awaitingClaudeBaselineBySessionID[sessionID]) return;
    [_awaitingClaudeBaselineBySessionID removeObjectForKey:sessionID];
    [self presentClaudeWaiting:NO forSessionID:sessionID];
    [self refreshAgentStateAndControls];
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
            _statusLabel.stringValue = PTL(@"Claude 已开始回复", @"Claude has started responding");
            return;
        }
    }
}

- (void)updateFloatingControls {
    BOOL hasSelection = _selectedSession.sessionID.length > 0;
    BOOL showingSelection = _floatingPanel.visible &&
        [_floatingSessionID isEqual:_selectedSession.sessionID];
    _floatingButton.enabled = hasSelection;
    _floatingButton.image = [NSImage imageWithSystemSymbolName:(showingSelection ? @"pin.fill" : @"pin")
        accessibilityDescription:(showingSelection ? @"关闭悬浮对话" : @"悬浮当前对话")];
    _floatingButton.toolTip = showingSelection ? @"关闭悬浮对话（⌘O）" : @"悬浮当前对话（⌘O）";
    _floatingMenuItem.enabled = hasSelection;
    _floatingMenuItem.title = showingSelection ? @"关闭悬浮对话" : @"悬浮当前对话";
}

- (void)buildFloatingPanelIfNeeded {
    if (_floatingPanel) return;
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow |
        NSWindowStyleMaskNonactivatingPanel;
    _floatingPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 640)
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    _floatingPanel.delegate = self;
    _floatingPanel.level = NSFloatingWindowLevel;
    _floatingPanel.floatingPanel = YES;
    _floatingPanel.hidesOnDeactivate = NO;
    _floatingPanel.becomesKeyOnlyIfNeeded = YES;
    _floatingPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    _floatingPanel.minSize = NSMakeSize(360, 320);
    _floatingPanel.releasedWhenClosed = NO;
    _floatingPanel.titlebarAppearsTransparent = YES;
    _floatingPanel.backgroundColor = PTWarmCanvasColor();

    PTAppearanceSurfaceView *surface = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    surface.surfaceStyle = PTAppearanceSurfaceStyleCanvas;
    _floatingPanel.contentView = surface;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    [configuration.userContentController addScriptMessageHandler:self name:@"quoteSelection"];
    [configuration.userContentController addScriptMessageHandler:self name:@"openTranscriptEditReview"];
    [configuration.userContentController addScriptMessageHandler:self name:@"openTranscriptFile"];
    [configuration.userContentController addScriptMessageHandler:self name:@"answerQuestion"];
    [configuration.userContentController addScriptMessageHandler:self name:@"copyAssistantOutput"];
    _floatingConversationView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    _floatingConversationView.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingConversationView.navigationDelegate = self;
    if (@available(macOS 12.0, *)) _floatingConversationView.underPageBackgroundColor = NSColor.clearColor;
    [surface addSubview:_floatingConversationView];

    PTAppearanceSurfaceView *composerBar = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
    composerBar.translatesAutoresizingMaskIntoConstraints = NO;
    composerBar.surfaceStyle = PTAppearanceSurfaceStyleCanvas;
    [surface addSubview:composerBar];

    _floatingComposerLabel = [self label:PTL(@"发送给当前会话", @"Send to the current conversation") size:10.5
        weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [composerBar addSubview:_floatingComposerLabel];

    _floatingImagePreviewScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _floatingImagePreviewScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingImagePreviewScroll.drawsBackground = NO;
    _floatingImagePreviewScroll.hasHorizontalScroller = YES;
    _floatingImagePreviewScroll.hasVerticalScroller = NO;
    _floatingImagePreviewScroll.autohidesScrollers = YES;
    _floatingImagePreviewScroll.hidden = YES;
    _floatingComposerSurface = [[PTComposerDropSurfaceView alloc] initWithFrame:NSZeroRect];
    _floatingComposerSurface.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _floatingComposerSurface.dropHandler = ^BOOL(NSArray<NSURL *> *urls) {
        return [weakSelf addComposerAttachmentURLs:urls floating:YES];
    };
    [composerBar addSubview:_floatingComposerSurface];
    [_floatingComposerSurface addSubview:_floatingImagePreviewScroll];

    _floatingImagePreviewStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _floatingImagePreviewStack.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingImagePreviewStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _floatingImagePreviewStack.alignment = NSLayoutAttributeCenterY;
    _floatingImagePreviewStack.spacing = 6;
    _floatingImagePreviewScroll.documentView = _floatingImagePreviewStack;

    PTAnimatedButton *floatingAdd = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    floatingAdd.title = @"＋";
    floatingAdd.font = [NSFont systemFontOfSize:23 weight:NSFontWeightLight];
    floatingAdd.contentTintColor = NSColor.labelColor;
    floatingAdd.fillColor = NSColor.clearColor;
    floatingAdd.hoverFillColor = PTWarmChipColor();
    floatingAdd.pressedFillColor = PTWarmBorderColor();
    floatingAdd.cornerRadius = 18;
    floatingAdd.target = self;
    floatingAdd.action = @selector(chooseFloatingAttachments:);
    _floatingImageButton = floatingAdd;
    _floatingImageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingImageButton.toolTip = PTL(@"添加文件或图片，也可以直接拖入", @"Add files or images, or drag them here");
    _floatingImageButton.enabled = NO;
    [_floatingComposerSurface addSubview:_floatingImageButton];

    NSScrollView *composerScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    composerScroll.translatesAutoresizingMaskIntoConstraints = NO;
    composerScroll.borderType = NSNoBorder;
    composerScroll.hasVerticalScroller = YES;
    composerScroll.autohidesScrollers = YES;
    composerScroll.drawsBackground = NO;
    [_floatingComposerSurface addSubview:composerScroll];

    _floatingComposerTextView = [[PTComposerTextView alloc] initWithFrame:NSMakeRect(0, 0, 360, 44)];
    _floatingComposerTextView.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    _floatingComposerTextView.drawsBackground = NO;
    _floatingComposerTextView.richText = NO;
    _floatingComposerTextView.allowsUndo = YES;
    _floatingComposerTextView.verticallyResizable = YES;
    _floatingComposerTextView.horizontallyResizable = NO;
    _floatingComposerTextView.textContainer.widthTracksTextView = YES;
    _floatingComposerTextView.textContainerInset = NSMakeSize(7, 7);
    _floatingComposerTextView.placeholderText = PTL(@"给 Claude 发消息", @"Message Claude");
    _floatingComposerTextView.editable = YES;
    _floatingComposerTextView.submitHandler = ^{
        [weakSelf sendFloatingMessage:nil];
    };
    _floatingComposerTextView.commandMenuHandler = ^{
        PTAppDelegate *self = weakSelf;
        if (self) [self updateClaudeCommandsForComposer:self->_floatingComposerTextView];
    };
    _floatingComposerTextView.commandKeyHandler = ^BOOL(NSEvent *event) {
        PTAppDelegate *self = weakSelf;
        return self ? [self handleCommandKey:event composer:self->_floatingComposerTextView] : NO;
    };
    _floatingComposerTextView.imagePasteHandler = ^BOOL(NSPasteboard *pasteboard) {
        return [weakSelf handleFloatingImagePasteboard:pasteboard];
    };
    _floatingComposerTextView.fileDropHandler = ^BOOL(NSArray<NSURL *> *urls) {
        return [weakSelf addComposerAttachmentURLs:urls floating:YES];
    };
    composerScroll.documentView = _floatingComposerTextView;

    _floatingEffortButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    _floatingEffortButton.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _floatingEffortButton.contentTintColor = NSColor.secondaryLabelColor;
    _floatingEffortButton.fillColor = NSColor.clearColor;
    _floatingEffortButton.hoverFillColor = PTWarmChipColor();
    _floatingEffortButton.pressedFillColor = PTWarmBorderColor();
    _floatingEffortButton.cornerRadius = 16;
    _floatingEffortButton.target = self;
    _floatingEffortButton.action = @selector(showComposerOptions:);
    _floatingEffortButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_floatingComposerSurface addSubview:_floatingEffortButton];

    PTAnimatedButton *floatingSend = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    floatingSend.title = @"↑";
    floatingSend.font = [NSFont systemFontOfSize:21 weight:NSFontWeightMedium];
    floatingSend.contentTintColor = NSColor.whiteColor;
    floatingSend.fillColor = PTColor(0.12, 0.11, 0.10);
    floatingSend.hoverFillColor = PTWarmAccentColor();
    floatingSend.pressedFillColor = PTColor(0.45, 0.18, 0.06);
    floatingSend.cornerRadius = 20;
    floatingSend.target = self;
    floatingSend.action = @selector(sendFloatingMessage:);
    _floatingSendButton = floatingSend;
    _floatingSendButton.translatesAutoresizingMaskIntoConstraints = NO;
    _floatingSendButton.enabled = NO;
    [_floatingComposerSurface addSubview:_floatingSendButton];

    _floatingComposerHeightConstraint = [composerBar.heightAnchor constraintEqualToConstant:108];
    _floatingImagePreviewHeightConstraint = [_floatingImagePreviewScroll.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_floatingConversationView.topAnchor constraintEqualToAnchor:surface.topAnchor],
        [_floatingConversationView.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [_floatingConversationView.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [_floatingConversationView.bottomAnchor constraintEqualToAnchor:composerBar.topAnchor],
        [composerBar.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [composerBar.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [composerBar.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor],
        _floatingComposerHeightConstraint,
        [_floatingComposerLabel.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:14],
        [_floatingComposerLabel.trailingAnchor constraintEqualToAnchor:composerBar.trailingAnchor constant:-14],
        [_floatingComposerLabel.topAnchor constraintEqualToAnchor:composerBar.topAnchor constant:7],
        [_floatingComposerSurface.leadingAnchor constraintEqualToAnchor:composerBar.leadingAnchor constant:12],
        [_floatingComposerSurface.trailingAnchor constraintEqualToAnchor:composerBar.trailingAnchor constant:-12],
        [_floatingComposerSurface.topAnchor constraintEqualToAnchor:_floatingComposerLabel.bottomAnchor constant:5],
        [_floatingComposerSurface.bottomAnchor constraintEqualToAnchor:composerBar.bottomAnchor constant:-9],
        [_floatingImagePreviewScroll.leadingAnchor constraintEqualToAnchor:_floatingComposerSurface.leadingAnchor constant:10],
        [_floatingImagePreviewScroll.trailingAnchor constraintEqualToAnchor:_floatingComposerSurface.trailingAnchor constant:-10],
        [_floatingImagePreviewScroll.topAnchor constraintEqualToAnchor:_floatingComposerSurface.topAnchor constant:6],
        _floatingImagePreviewHeightConstraint,
        [_floatingImagePreviewStack.leadingAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.contentView.leadingAnchor],
        [_floatingImagePreviewStack.topAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.contentView.topAnchor],
        [_floatingImagePreviewStack.bottomAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.contentView.bottomAnchor],
        [_floatingImageButton.leadingAnchor constraintEqualToAnchor:_floatingComposerSurface.leadingAnchor constant:8],
        [_floatingImageButton.widthAnchor constraintEqualToConstant:36],
        [_floatingImageButton.heightAnchor constraintEqualToConstant:36],
        [composerScroll.leadingAnchor constraintEqualToAnchor:_floatingImageButton.trailingAnchor constant:5],
        [composerScroll.topAnchor constraintEqualToAnchor:_floatingImagePreviewScroll.bottomAnchor constant:2],
        [composerScroll.bottomAnchor constraintEqualToAnchor:_floatingComposerSurface.bottomAnchor constant:-6],
        [_floatingImageButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [composerScroll.trailingAnchor constraintEqualToAnchor:_floatingEffortButton.leadingAnchor constant:-4],
        [_floatingEffortButton.trailingAnchor constraintEqualToAnchor:_floatingSendButton.leadingAnchor constant:-4],
        [_floatingEffortButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [_floatingEffortButton.widthAnchor constraintEqualToConstant:74],
        [_floatingEffortButton.heightAnchor constraintEqualToConstant:32],
        [_floatingSendButton.trailingAnchor constraintEqualToAnchor:_floatingComposerSurface.trailingAnchor constant:-8],
        [_floatingSendButton.centerYAnchor constraintEqualToAnchor:composerScroll.centerYAnchor],
        [_floatingSendButton.widthAnchor constraintEqualToConstant:40],
        [_floatingSendButton.heightAnchor constraintEqualToConstant:40]
    ]];
    [self updateComposerConfigurationButtons];

    NSURL *htmlURL = [NSBundle.mainBundle URLForResource:@"index" withExtension:@"html"];
    if (htmlURL) {
        [_floatingConversationView loadFileURL:htmlURL allowingReadAccessToURL:NSBundle.mainBundle.resourceURL];
    }
}

- (void)positionFloatingPanelNearMainWindow {
    NSScreen *screen = _window.screen ?: NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;
    NSRect mainFrame = _window.frame;
    NSRect panelFrame = _floatingPanel.frame;
    panelFrame.origin.x = MIN(NSMaxX(mainFrame) - panelFrame.size.width - 22,
                              NSMaxX(visible) - panelFrame.size.width - 12);
    panelFrame.origin.x = MAX(panelFrame.origin.x, NSMinX(visible) + 12);
    panelFrame.origin.y = MIN(NSMaxY(mainFrame) - panelFrame.size.height - 22,
                              NSMaxY(visible) - panelFrame.size.height - 12);
    panelFrame.origin.y = MAX(panelFrame.origin.y, NSMinY(visible) + 12);
    [_floatingPanel setFrame:panelFrame display:NO];
}

- (void)renderFloatingSession:(PTSessionInfo *)session {
    if (!_floatingWebReady || !_floatingPanel.visible || !session) return;
    PTClaudeBridge *streamBridge = [self bridgeForSessionID:session.sessionID];
    [streamBridge reconcileStreamWithMessages:session.assistantMessages];
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

    NSUInteger messageCount = session.assistantMessages.count;
    BOOL canAppend = [_floatingRenderedSessionID isEqual:session.sessionID] &&
        _floatingRenderedModifiedAt != nil && _floatingRenderedMessageCount < messageCount;

    // 与主窗口同一套策略：追加时不再序列化整份历史消息（JS 侧会直接丢弃）。
    NSMutableDictionary *payload = [@{
        @"sessionId": session.sessionID ?: @"",
        @"title": session.title ?: @"未命名会话",
        @"cwd": session.cwd ?: @"",
        @"model": session.model ?: @"Claude",
        @"interfaceLanguage": PTInterfaceLanguageCode(),
        @"awaitingReply": @(_awaitingClaudeBaselineBySessionID[session.sessionID] != nil)
    } mutableCopy];
    payload[@"questionUpdates"] = PTQuestionUpdates(session.assistantMessages);
    if (!canAppend) payload[@"messages"] = session.assistantMessages ?: @[];

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : nil;
    if (!json) return;

    NSString *script = nil;
    if (canAppend) {
        NSArray *incoming = [session.assistantMessages subarrayWithRange:
            NSMakeRange(_floatingRenderedMessageCount, messageCount - _floatingRenderedMessageCount)];
        NSData *incomingData = [NSJSONSerialization dataWithJSONObject:incoming options:0 error:nil];
        NSString *incomingJSON = incomingData
            ? [[NSString alloc] initWithData:incomingData encoding:NSUTF8StringEncoding] : nil;
        if (incomingJSON) {
            script = [NSString stringWithFormat:
                @"(function(){var m=%@;"
                 "if(!window.__ptSessionMatches||!window.__ptSessionMatches(m))return 0;"
                 "window.appendClaudeMessages(m,%@);return 1;})()",
                json, incomingJSON];
        }
    }
    if (!script) script = [NSString stringWithFormat:@"window.setClaudeSession(%@); null;", json];
    NSUInteger generation = _floatingRenderGeneration;
    NSString *targetSessionID = [session.sessionID copy];
    NSDate *targetModifiedAt = session.modifiedAt;
    _floatingRenderInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [_floatingConversationView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        self->_floatingRenderInFlight = NO;
        BOOL appendRejected = canAppend && [result isKindOfClass:NSNumber.class] &&
            ![(NSNumber *)result boolValue];
        BOOL stillCurrent = generation == self->_floatingRenderGeneration &&
            self->_floatingPanel.visible && [self->_floatingSessionID isEqual:targetSessionID];
        if (stillCurrent && !error && !appendRejected) {
            self->_floatingRenderedSessionID = targetSessionID;
            self->_floatingRenderedModifiedAt = targetModifiedAt;
            self->_floatingRenderedMessageCount = session.assistantMessages.count;
            [self presentClaudeStreamForBridge:streamBridge];
        } else if (stillCurrent && (error || appendRejected)) {
            self->_floatingPanel.title = @"悬浮对话 · 显示更新失败";
        }
        PTSessionInfo *pending = self->_pendingFloatingSession;
        self->_pendingFloatingSession = nil;
        if (pending && self->_floatingPanel.visible) {
            [self renderFloatingSession:pending];
        }
    }];
}

- (void)refreshFloatingConversation {
    if (!_floatingPanel.visible || _floatingSessionID.length == 0) return;
    PTSessionInfo *session = [self sessionWithID:_floatingSessionID];
    if (!session) return;
    [self updateFloatingTitleForSession:session];
    [self renderFloatingSession:session];
    [self updateFloatingComposerState];
}

- (void)toggleFloatingConversation:(id)sender {
    (void)sender;
    PTFloatingConversationAction action = PTFloatingConversationActionForState(
        _floatingPanel.visible,
        _floatingSessionID,
        _selectedSession.sessionID
    );
    if (action == PTFloatingConversationActionNone) {
        return;
    }
    if (action == PTFloatingConversationActionClose) {
        [_floatingPanel close];
        return;
    }

    BOOL wasVisible = _floatingPanel.visible;
    [self buildFloatingPanelIfNeeded];
    if (_floatingSessionID.length && ![_floatingSessionID isEqual:_selectedSession.sessionID]) {
        [self clearFloatingPendingImagesAfterSuccessfulSend];
        _floatingComposerTextView.string = @"";
    }
    _floatingSessionID = [_selectedSession.sessionID copy];
    _floatingRenderedSessionID = nil;
    _floatingRenderedModifiedAt = nil;
    _floatingRenderedMessageCount = 0;
    _pendingFloatingSession = nil;
    _floatingRenderGeneration += 1;
    if (!wasVisible) [self positionFloatingPanelNearMainWindow];
    [_floatingPanel orderFrontRegardless];
    [self syncFullSessionIDs];
    [self refreshFloatingConversation];
    [self updateFloatingControls];
    [self updateFloatingComposerState];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object != _floatingPanel) return;
    _floatingRenderGeneration += 1;
    _floatingSessionID = nil;
    _floatingRenderedSessionID = nil;
    _floatingRenderedModifiedAt = nil;
    _floatingRenderedMessageCount = 0;
    _pendingFloatingSession = nil;
    [self clearFloatingPendingImagesAfterSuccessfulSend];
    _floatingComposerTextView.string = @"";
    [self syncFullSessionIDs];
    [self updateFloatingControls];
    [self updateFloatingComposerState];
}

- (NSArray<NSData *> *)pendingImagePNGsForClaude {
    NSMutableArray<NSData *> *images = [NSMutableArray arrayWithCapacity:_pendingImages.count];
    for (NSDictionary *item in _pendingImages) {
        NSData *png = [item[@"pngData"] isKindOfClass:NSData.class] ? item[@"pngData"] : nil;
        if (png.length) [images addObject:png];
    }
    return images;
}

- (NSArray<NSString *> *)pendingFilesForClaude {
    return [_pendingFiles copy] ?: @[];
}

- (NSArray<NSData *> *)floatingPendingImagePNGsForClaude {
    NSMutableArray<NSData *> *images = [NSMutableArray arrayWithCapacity:_floatingPendingImages.count];
    for (NSDictionary *item in _floatingPendingImages) {
        NSData *png = [item[@"pngData"] isKindOfClass:NSData.class] ? item[@"pngData"] : nil;
        if (png.length) [images addObject:png];
    }
    return images;
}

- (NSArray<NSString *> *)floatingPendingFilesForClaude {
    return [_floatingPendingFiles copy] ?: @[];
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
            [files addObject:path];
            added++;
        }
    }
    if (floating) {
        [self updateFloatingImagePreviews];
        _floatingComposerLabel.stringValue = [NSString stringWithFormat:
            PTL(@"已添加 %lu 个附件", @"Added %lu attachments"), (unsigned long)added];
    } else {
        [self updateImagePreviews];
        _statusLabel.stringValue = [NSString stringWithFormat:
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
        @"temporary": @(temporary)
    }];
    if (temporary) [_temporaryImagePaths addObject:url.path];
    [self updateFloatingImagePreviews];
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
        _floatingComposerLabel.stringValue = @"无法读取剪贴板图片";
        return YES;
    }
    _floatingComposerLabel.stringValue = @"已从剪贴板添加图片";
    return YES;
}

- (void)chooseFloatingAttachments:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = PTL(@"添加文件或图片", @"Add files or images");
    panel.prompt = PTL(@"添加", @"Add");
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;
    panel.resolvesAliases = YES;
    [panel beginSheetModalForWindow:_floatingPanel completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        [self addComposerAttachmentURLs:panel.URLs floating:YES];
    }];
}

- (void)chooseFloatingImages:(id)sender {
    [self chooseFloatingAttachments:sender];
}

- (void)removeFloatingPendingFile:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    if (path.length == 0) return;
    [_floatingPendingFiles removeObject:path];
    [self updateFloatingImagePreviews];
}

- (void)removeFloatingPendingImage:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    NSUInteger index = [_floatingPendingImages indexOfObjectPassingTest:
        ^BOOL(NSDictionary *item, NSUInteger itemIndex, BOOL *stop) {
            (void)itemIndex;
            (void)stop;
            return [item[@"path"] isEqual:path];
        }];
    if (index == NSNotFound) return;
    NSDictionary *item = _floatingPendingImages[index];
    [_floatingPendingImages removeObjectAtIndex:index];
    if ([item[@"temporary"] boolValue]) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [self updateFloatingImagePreviews];
}

- (void)updateFloatingImagePreviews {
    for (NSView *view in _floatingImagePreviewStack.arrangedSubviews.copy) {
        [_floatingImagePreviewStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *item in _floatingPendingImages) {
        PTAppearanceSurfaceView *chip = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.surfaceStyle = PTAppearanceSurfaceStyleChip;
        chip.layer.cornerRadius = 9;
        chip.layer.borderWidth = 0.6;

        NSImageView *thumbnail = [[NSImageView alloc] initWithFrame:NSZeroRect];
        thumbnail.translatesAutoresizingMaskIntoConstraints = NO;
        thumbnail.image = item[@"image"];
        thumbnail.imageScaling = NSImageScaleProportionallyUpOrDown;
        thumbnail.wantsLayer = YES;
        thumbnail.layer.cornerRadius = 6;
        thumbnail.layer.masksToBounds = YES;
        [chip addSubview:thumbnail];

        PTAnimatedButton *remove = PTWarmButton(@"", self, @selector(removeFloatingPendingImage:));
        remove.image = [NSImage imageWithSystemSymbolName:@"xmark"
            accessibilityDescription:@"移除图片"];
        remove.fillColor = NSColor.clearColor;
        remove.strokeColor = NSColor.clearColor;
        remove.cornerRadius = 8;
        remove.contentTintColor = NSColor.tertiaryLabelColor;
        remove.identifier = item[@"path"];
        [chip addSubview:remove];
        [_floatingImagePreviewStack addArrangedSubview:chip];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:64],
            [chip.heightAnchor constraintEqualToConstant:42],
            [thumbnail.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:5],
            [thumbnail.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [thumbnail.widthAnchor constraintEqualToConstant:32],
            [thumbnail.heightAnchor constraintEqualToConstant:32],
            [remove.leadingAnchor constraintEqualToAnchor:thumbnail.trailingAnchor constant:3],
            [remove.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-3],
            [remove.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.widthAnchor constraintEqualToConstant:20]
        ]];
    }
    for (NSString *path in _floatingPendingFiles) {
        PTAppearanceSurfaceView *chip = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.surfaceStyle = PTAppearanceSurfaceStyleChip;
        chip.layer.cornerRadius = 9;
        chip.layer.borderWidth = 0.6;
        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        BOOL isDirectory = NO;
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
        icon.image = [NSImage imageWithSystemSymbolName:isDirectory ? @"folder.fill" : @"doc.fill"
            accessibilityDescription:isDirectory ? PTL(@"文件夹", @"Folder") : PTL(@"文件", @"File")];
        icon.contentTintColor = PTWarmAccentColor();
        [chip addSubview:icon];
        NSTextField *name = [self label:path.lastPathComponent ?: PTL(@"文件", @"File")
            size:10 weight:NSFontWeightMedium color:NSColor.labelColor];
        name.toolTip = path;
        [chip addSubview:name];
        PTAnimatedButton *remove = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
        remove.translatesAutoresizingMaskIntoConstraints = NO;
        remove.title = @"×";
        remove.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        remove.contentTintColor = NSColor.secondaryLabelColor;
        remove.hoverFillColor = PTWarmBorderColor();
        remove.cornerRadius = 9;
        remove.target = self;
        remove.action = @selector(removeFloatingPendingFile:);
        remove.identifier = path;
        [chip addSubview:remove];
        [_floatingImagePreviewStack addArrangedSubview:chip];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:160],
            [chip.heightAnchor constraintEqualToConstant:42],
            [icon.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:8],
            [icon.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:20],
            [icon.heightAnchor constraintEqualToConstant:20],
            [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:7],
            [name.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:3],
            [remove.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-5],
            [remove.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.widthAnchor constraintEqualToConstant:20],
            [remove.heightAnchor constraintEqualToConstant:20],
            [name.widthAnchor constraintLessThanOrEqualToConstant:96]
        ]];
    }
    BOOL hasAttachments = _floatingPendingImages.count > 0 || _floatingPendingFiles.count > 0;
    _floatingImagePreviewScroll.hidden = !hasAttachments;
    _floatingImagePreviewHeightConstraint.constant = hasAttachments ? 46 : 0;
    _floatingComposerHeightConstraint.constant = hasAttachments ? 156 : 108;
    [_floatingPanel.contentView layoutSubtreeIfNeeded];
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
    [self updateFloatingImagePreviews];
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
        @"temporary": @(temporary)
    }];
    if (temporary) [_temporaryImagePaths addObject:url.path];
    [self updateImagePreviews];
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
        _statusLabel.stringValue = @"无法读取剪贴板图片";
        return YES;
    }
    _statusLabel.stringValue = @"已从剪贴板添加图片";
    return YES;
}

- (void)chooseAttachments:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = PTL(@"添加文件或图片", @"Add files or images");
    panel.prompt = PTL(@"添加", @"Add");
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;
    panel.resolvesAliases = YES;
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        [self addComposerAttachmentURLs:panel.URLs floating:NO];
    }];
}

- (void)chooseImages:(id)sender {
    [self chooseAttachments:sender];
}

- (void)removePendingFile:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    if (path.length == 0) return;
    [_pendingFiles removeObject:path];
    [self updateImagePreviews];
}

- (void)removePendingImage:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    NSUInteger index = [_pendingImages indexOfObjectPassingTest:
        ^BOOL(NSDictionary *item, NSUInteger itemIndex, BOOL *stop) {
            (void)itemIndex;
            (void)stop;
            return [item[@"path"] isEqual:path];
        }];
    if (index == NSNotFound) return;
    NSDictionary *item = _pendingImages[index];
    [_pendingImages removeObjectAtIndex:index];
    if ([item[@"temporary"] boolValue]) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [self updateImagePreviews];
}

- (void)updateImagePreviews {
    for (NSView *view in _imagePreviewStack.arrangedSubviews.copy) {
        [_imagePreviewStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *item in _pendingImages) {
        PTAppearanceSurfaceView *chip = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.surfaceStyle = PTAppearanceSurfaceStyleChip;
        chip.layer.cornerRadius = 10;
        chip.layer.borderWidth = 0.6;

        NSImageView *thumbnail = [[NSImageView alloc] initWithFrame:NSZeroRect];
        thumbnail.translatesAutoresizingMaskIntoConstraints = NO;
        thumbnail.image = item[@"image"];
        thumbnail.imageScaling = NSImageScaleProportionallyUpOrDown;
        thumbnail.wantsLayer = YES;
        thumbnail.layer.cornerRadius = 7;
        thumbnail.layer.masksToBounds = YES;
        [chip addSubview:thumbnail];

        NSString *path = item[@"path"];
        NSTextField *name = [self label:path.lastPathComponent ?: @"图片"
            size:10.5 weight:NSFontWeightMedium color:NSColor.labelColor];
        name.toolTip = path;
        [chip addSubview:name];

        PTAnimatedButton *remove = PTWarmButton(@"", self, @selector(removePendingImage:));
        remove.image = [NSImage imageWithSystemSymbolName:@"xmark"
            accessibilityDescription:@"移除图片"];
        remove.fillColor = NSColor.clearColor;
        remove.strokeColor = NSColor.clearColor;
        remove.cornerRadius = 8;
        remove.contentTintColor = NSColor.tertiaryLabelColor;
        remove.identifier = path;
        [chip addSubview:remove];

        [_imagePreviewStack addArrangedSubview:chip];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:180],
            [chip.heightAnchor constraintEqualToConstant:40],
            [thumbnail.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:5],
            [thumbnail.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [thumbnail.widthAnchor constraintEqualToConstant:30],
            [thumbnail.heightAnchor constraintEqualToConstant:30],
            [name.leadingAnchor constraintEqualToAnchor:thumbnail.trailingAnchor constant:7],
            [name.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:5],
            [remove.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-5],
            [remove.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.widthAnchor constraintEqualToConstant:20],
            [name.widthAnchor constraintLessThanOrEqualToConstant:108]
        ]];
    }
    for (NSString *path in _pendingFiles) {
        PTAppearanceSurfaceView *chip = [[PTAppearanceSurfaceView alloc] initWithFrame:NSZeroRect];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.surfaceStyle = PTAppearanceSurfaceStyleChip;
        chip.layer.cornerRadius = 10;
        chip.layer.borderWidth = 0.6;

        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        BOOL isDirectory = NO;
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
        icon.image = [NSImage imageWithSystemSymbolName:isDirectory ? @"folder.fill" : @"doc.fill"
            accessibilityDescription:isDirectory ? PTL(@"文件夹", @"Folder") : PTL(@"文件", @"File")];
        icon.contentTintColor = PTWarmAccentColor();
        [chip addSubview:icon];

        NSTextField *name = [self label:path.lastPathComponent ?: PTL(@"文件", @"File")
            size:10.5 weight:NSFontWeightMedium color:NSColor.labelColor];
        name.toolTip = path;
        [chip addSubview:name];

        PTAnimatedButton *remove = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
        remove.translatesAutoresizingMaskIntoConstraints = NO;
        remove.title = @"×";
        remove.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
        remove.contentTintColor = NSColor.secondaryLabelColor;
        remove.fillColor = NSColor.clearColor;
        remove.hoverFillColor = PTWarmBorderColor();
        remove.cornerRadius = 9;
        remove.target = self;
        remove.action = @selector(removePendingFile:);
        remove.identifier = path;
        [chip addSubview:remove];

        [_imagePreviewStack addArrangedSubview:chip];
        [NSLayoutConstraint activateConstraints:@[
            [chip.widthAnchor constraintEqualToConstant:190],
            [chip.heightAnchor constraintEqualToConstant:40],
            [icon.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:9],
            [icon.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:22],
            [icon.heightAnchor constraintEqualToConstant:22],
            [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
            [name.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:4],
            [remove.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-6],
            [remove.centerYAnchor constraintEqualToAnchor:chip.centerYAnchor],
            [remove.widthAnchor constraintEqualToConstant:20],
            [remove.heightAnchor constraintEqualToConstant:20],
            [name.widthAnchor constraintLessThanOrEqualToConstant:116]
        ]];
    }
    BOOL hasAttachments = _pendingImages.count > 0 || _pendingFiles.count > 0;
    _imagePreviewScroll.hidden = !hasAttachments;
    CGFloat previewHeight = hasAttachments ? 44 : 0;
    CGFloat composerHeight = hasAttachments ? 160 : 112;
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _imagePreviewHeightConstraint.constant = previewHeight;
        _composerHeightConstraint.constant = composerHeight;
        [_window.contentView layoutSubtreeIfNeeded];
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.24;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            self->_imagePreviewHeightConstraint.animator.constant = previewHeight;
            self->_composerHeightConstraint.animator.constant = composerHeight;
            [self->_window.contentView.animator layoutSubtreeIfNeeded];
        } completionHandler:nil];
    }
}

- (void)clearPendingImagesAfterSuccessfulSend {
    for (NSDictionary *item in _pendingImages.copy) {
        if (![item[@"temporary"] boolValue]) continue;
        NSString *path = item[@"path"];
        // Ctrl+V 返回后 Claude Code 已经把图片读入自己的输入缓冲区并在提交时
        // 写进 JSONL 的 base64 block；PrettyTerm 的预览临时文件无需继续保留。
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        [_temporaryImagePaths removeObject:path];
    }
    [_pendingImages removeAllObjects];
    [_pendingFiles removeAllObjects];
    [self updateImagePreviews];
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
        @[@"Claude Fable 5", @"Fable 5", @"claude-fable-5"],
        @[@"Claude Opus 5.5", @"Opus 5.5", @"claude-opus-5-5"],
        @[@"Claude Sonnet 5", @"Sonnet 5", @"claude-sonnet-5"],
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
    PTClaudeBridge *bridge = [self bridgeForSessionID:sessionID];
    if (bridge) return bridge.currentModel;
    if (sessionID.length) return [self sessionWithID:sessionID].model;
    return _selectedComposerModelID;
}

- (NSString *)composerEffortForSessionID:(NSString *)sessionID {
    PTClaudeBridge *bridge = [self bridgeForSessionID:sessionID];
    if (bridge) return bridge.currentEffort;
    if (sessionID.length) return [self sessionWithID:sessionID].effort;
    return _selectedComposerEffort;
}

- (void)updateComposerConfigurationButtons {
    for (PTAnimatedButton *button in [NSArray arrayWithObjects:_composerEffortButton, _floatingEffortButton, nil]) {
        NSString *sessionID = button == _floatingEffortButton ? _floatingSessionID : _selectedSession.sessionID;
        NSString *effort = [self composerEffortTitle:[self composerEffortForSessionID:sessionID]];
        button.title = [NSString stringWithFormat:@"%@ ⌄", effort];
        button.toolTip = [NSString stringWithFormat:PTL(@"模型：%@ · 推理强度：%@", @"Model: %@ · Effort: %@"),
            [self composerModelShortTitle:[self composerModelForSessionID:sessionID]], effort];
    }
}

- (void)showConfigurationStatus:(NSString *)status forSessionID:(NSString *)sessionID {
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        if ([tab.sessionID isEqual:sessionID]) {
            tab.status = status;
            tab.commandOutput = status;
        }
    }
    if ([_selectedSession.sessionID isEqual:sessionID]) _statusLabel.stringValue = status;
    if ([_floatingSessionID isEqual:sessionID]) _floatingComposerLabel.stringValue = status;
}

- (void)refreshComposerConfigurationPopoverForSessionID:(NSString *)sessionID {
    if (!_composerOptionsPopover.shown || ![_configurationSessionID isEqual:sessionID]) return;
    if ([_composerConfigurationPage isEqual:@"effort"]) {
        NSString *effort = [self composerEffortForSessionID:sessionID];
        _composerEffortPopoverTitle.stringValue = [NSString stringWithFormat:PTL(@"推理强度 · %@", @"Reasoning effort · %@"),
            [self composerEffortTitle:effort]];
        NSUInteger index = [[self composerEffortLevels] indexOfObject:effort ?: @""];
        _composerEffortSlider.selectedIndex = index == NSNotFound ? -1 : (NSInteger)index;
    } else if ([_composerConfigurationPage isEqual:@"model"]) [self showComposerModelPage:nil];
    else if ([_composerConfigurationPage isEqual:@"mode"]) [self showComposerModePage:nil];
    else if ([_composerConfigurationPage isEqual:@"advanced"]) [self showComposerAdvancedPage:nil];
}

- (PTAnimatedButton *)composerPopoverButtonWithTitle:(NSString *)title
                                               action:(SEL)action
                                           identifier:(NSString *)identifier {
    PTAnimatedButton *button = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = title;
    button.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    button.contentTintColor = NSColor.labelColor;
    button.fillColor = NSColor.clearColor;
    button.hoverFillColor = PTWarmChipColor();
    button.pressedFillColor = PTWarmBorderColor();
    button.strokeColor = PTWarmBorderColor();
    button.cornerRadius = 14;
    button.target = self;
    button.action = action;
    button.identifier = identifier;
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    return button;
}

- (void)replaceComposerOptionsWithViews:(NSArray<NSView *> *)views height:(CGFloat)height {
    for (NSView *view in _composerOptionsStack.arrangedSubviews.copy) {
        [_composerOptionsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSView *view in views) {
        view.alphaValue = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 1 : 0;
        [_composerOptionsStack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:_composerOptionsStack.widthAnchor constant:-30].active = YES;
    }
    _composerOptionsPopover.contentSize = NSMakeSize(310, height);
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.20;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            for (NSView *view in views) view.animator.alphaValue = 1;
        } completionHandler:nil];
    }
}

- (void)showComposerEffortPage:(id)sender {
    (void)sender;
    _composerConfigurationPage = @"effort";
    NSString *effort = [self composerEffortForSessionID:_configurationSessionID ?: _selectedSession.sessionID];
    NSTextField *title = [self label:[NSString stringWithFormat:PTL(@"推理强度 · %@", @"Reasoning effort · %@"),
        [self composerEffortTitle:effort]] size:15 weight:NSFontWeightSemibold color:NSColor.labelColor];
    _composerEffortPopoverTitle = title;
    _composerEffortSlider = [[PTEffortSlider alloc] initWithFrame:NSZeroRect];
    _composerEffortSlider.translatesAutoresizingMaskIntoConstraints = NO;
    NSUInteger index = [[self composerEffortLevels] indexOfObject:effort ?: @""];
    _composerEffortSlider.selectedIndex = index == NSNotFound ? -1 : (NSInteger)index;
    _composerEffortSlider.target = self;
    _composerEffortSlider.action = @selector(changeComposerEffort:);
    [_composerEffortSlider.heightAnchor constraintEqualToConstant:62].active = YES;

    NSView *captions = [[NSView alloc] initWithFrame:NSZeroRect];
    captions.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *faster = [self label:PTL(@"更快", @"Faster") size:10.5 weight:NSFontWeightMedium color:NSColor.tertiaryLabelColor];
    NSTextField *deeper = [self label:PTL(@"更深入", @"Deeper") size:10.5 weight:NSFontWeightMedium color:NSColor.tertiaryLabelColor];
    [captions addSubview:faster];
    [captions addSubview:deeper];
    [NSLayoutConstraint activateConstraints:@[
        [captions.heightAnchor constraintEqualToConstant:16],
        [faster.leadingAnchor constraintEqualToAnchor:captions.leadingAnchor constant:4],
        [faster.centerYAnchor constraintEqualToAnchor:captions.centerYAnchor],
        [deeper.trailingAnchor constraintEqualToAnchor:captions.trailingAnchor constant:-4],
        [deeper.centerYAnchor constraintEqualToAnchor:captions.centerYAnchor]
    ]];

    PTAnimatedButton *advanced = [self composerPopoverButtonWithTitle:PTL(@"高级设置  ›", @"Advanced  ›")
        action:@selector(showComposerAdvancedPage:) identifier:nil];
    [self replaceComposerOptionsWithViews:@[title, _composerEffortSlider, captions, advanced] height:216];
}

- (void)showComposerAdvancedPage:(id)sender {
    (void)sender;
    _composerConfigurationPage = @"advanced";
    _composerEffortPopoverTitle = nil;
    PTAnimatedButton *back = [self composerPopoverButtonWithTitle:PTL(@"‹  高级", @"‹  Advanced")
        action:@selector(showComposerEffortPage:) identifier:nil];
    NSString *sessionID = _configurationSessionID ?: _selectedSession.sessionID;
    NSString *model = [self composerModelShortTitle:[self composerModelForSessionID:sessionID]];
    NSString *effort = [self composerEffortTitle:[self composerEffortForSessionID:sessionID]];
    PTAnimatedButton *modelRow = [self composerPopoverButtonWithTitle:
        [NSString stringWithFormat:PTL(@"模型   ·   %@   ›", @"Model   ·   %@   ›"), model]
        action:@selector(showComposerModelPage:) identifier:nil];
    PTAnimatedButton *effortRow = [self composerPopoverButtonWithTitle:
        [NSString stringWithFormat:PTL(@"推理强度   ·   %@   ›", @"Effort   ·   %@   ›"), effort]
        action:@selector(showComposerEffortPage:) identifier:nil];
    PTClaudeBridge *bridge = [self bridgeForSessionID:_configurationSessionID ?: _selectedSession.sessionID];
    NSString *mode = bridge.permissionMode ?: PTL(@"未读取", @"Unknown");
    PTAnimatedButton *modeRow = [self composerPopoverButtonWithTitle:
        [NSString stringWithFormat:PTL(@"模式   ·   %@   ›", @"Mode   ·   %@   ›"), mode]
        action:@selector(showComposerModePage:) identifier:nil];
    PTAnimatedButton *commands = [self composerPopoverButtonWithTitle:PTL(@"命令 /   ›", @"Commands /   ›")
        action:@selector(showClaudeCommands:) identifier:nil];
    PTAnimatedButton *result = [self composerPopoverButtonWithTitle:PTL(@"查看命令结果   ›", @"View command result   ›")
        action:@selector(showClaudeCommandResult:) identifier:nil];
    [self replaceComposerOptionsWithViews:@[back, modelRow, effortRow, modeRow, commands, result] height:325];
}

- (void)showComposerModePage:(id)sender {
    (void)sender;
    _composerConfigurationPage = @"mode";
    NSMutableArray *views = [NSMutableArray arrayWithObject:[self composerPopoverButtonWithTitle:PTL(@"‹  模式", @"‹  Mode") action:@selector(showComposerAdvancedPage:) identifier:nil]];
    NSString *mode = [self bridgeForSessionID:_configurationSessionID ?: _selectedSession.sessionID].permissionMode;
    for (NSArray *entry in @[@[@"Plan", @"plan"], @[@"Auto", @"auto"], @[@"Bypass", @"bypass"], @[@"Default", @"default"], @[@"Accept edits", @"acceptEdits"]]) {
        NSString *wireMode = [entry[1] isEqual:@"bypass"] ? @"bypassPermissions" : entry[1];
        NSString *title = [[wireMode isEqual:mode] ? @"✓  " : @"    " stringByAppendingString:entry[0]];
        [views addObject:[self composerPopoverButtonWithTitle:title action:@selector(changeComposerMode:) identifier:entry[1]]];
    }
    [self replaceComposerOptionsWithViews:views height:320];
}

- (void)changeComposerMode:(PTAnimatedButton *)sender {
    NSString *sessionID = _configurationSessionID ?: _selectedSession.sessionID;
    [self sendOutgoingMessage:[@"/mode " stringByAppendingString:sender.identifier] imagePNGs:@[] forSessionID:sessionID success:^{
        [self refreshComposerConfigurationPopoverForSessionID:sessionID];
        [self showConfigurationStatus:[NSString stringWithFormat:PTL(@"当前模式：%@", @"Current mode: %@"),
            [self bridgeForSessionID:sessionID].permissionMode] forSessionID:sessionID];
    } failureResponder:nil];
}

- (void)dismissCommandPalette {
    [_commandPalette removeFromSuperview];
    _commandMenuComposer = nil;
    if (_commandDismissMonitor) { [NSEvent removeMonitor:_commandDismissMonitor]; _commandDismissMonitor = nil; }
    if (_commandLayoutObserver) { [NSNotificationCenter.defaultCenter removeObserver:_commandLayoutObserver]; _commandLayoutObserver = nil; }
}

- (NSString *)commandQueryForComposer:(PTComposerTextView *)composer {
    NSString *text = composer.string;
    if (![text hasPrefix:@"/"] || [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return nil;
    return [text substringFromIndex:1];
}

- (void)updateClaudeCommandsForComposer:(PTComposerTextView *)composer {
    if (composer.window.firstResponder != composer) return;
    if ([self commandQueryForComposer:composer] == nil) {
        if (_commandMenuComposer == composer) [self dismissCommandPalette];
        return;
    }
    [self showClaudeCommands:composer];
}

- (BOOL)handleCommandKey:(NSEvent *)event composer:(PTComposerTextView *)composer {
    if (!_commandPalette.superview || _commandMenuComposer != composer) return NO;
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift)) return NO;
    if (event.keyCode == 53) { [self dismissCommandPalette]; return YES; }
    if (event.keyCode == 125 || event.keyCode == 126) { [_commandPalette moveSelection:event.keyCode == 125 ? 1 : -1]; return YES; }
    if (event.keyCode == 48 || event.keyCode == 36 || event.keyCode == 76) {
        if ([_commandPalette chooseSelection]) return YES;
        [self dismissCommandPalette];
    }
    return NO;
}

- (void)layoutCommandPalette {
    NSView *root = _commandPalette.superview;
    if (!root || !_commandMenuComposer) return;
    NSView *surface = _commandMenuComposer == _floatingComposerTextView ? _floatingComposerSurface : _composerSurface;
    NSRect anchor = [surface convertRect:surface.bounds toView:root];
    CGFloat available = root.isFlipped ? NSMinY(anchor) - 16 : NSHeight(root.bounds) - NSMaxY(anchor) - 16;
    CGFloat height = MIN(MAX(54, _commandPalette.commands.count * 42 + 12), MIN(348, MAX(0, available)));
    CGFloat width = MIN(NSWidth(anchor), MAX(0, NSWidth(root.bounds) - 24));
    CGFloat x = MAX(12, MIN(NSMinX(anchor), NSWidth(root.bounds) - width - 12));
    CGFloat y = root.isFlipped ? NSMinY(anchor) - height - 8 : NSMaxY(anchor) + 8;
    _commandPalette.frame = NSMakeRect(x, y, width, height);
    [_commandPalette setNeedsLayout:YES];
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

- (void)showClaudeCommands:(id)sender {
    PTComposerTextView *composer = [sender isKindOfClass:PTComposerTextView.class] ? sender :
        ([_configurationSessionID isEqual:_floatingSessionID] && _floatingPanel.visible ? _floatingComposerTextView : _composerTextView);
    NSString *sessionID = composer == _floatingComposerTextView ? _floatingSessionID : _selectedSession.sessionID;
    if (!sessionID.length) return;
    if (_commandMenuComposer != composer) [self dismissCommandPalette];
    _commandMenuComposer = composer;
    _configurationSessionID = sessionID;
    [_composerOptionsPopover close];
    if (!_commandPalette) {
        _commandPalette = [[PTCommandPaletteView alloc] initWithFrame:NSZeroRect];
        __weak typeof(self) weakSelf = self;
        _commandPalette.chooseCommand = ^(NSDictionary *command) { [weakSelf insertClaudeCommand:command]; };
    }
    PTClaudeBridge *bridge = [self bridgeForSessionID:sessionID];
    _commandPalette.commands = [self commandSuggestions:bridge query:[self commandQueryForComposer:composer] ?: @""];
    if (!_commandPalette.superview) {
        [composer.window.contentView addSubview:_commandPalette positioned:NSWindowAbove relativeTo:nil];
        __weak typeof(self) weakSelf = self;
        _commandDismissMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event) {
            PTAppDelegate *self = weakSelf;
            if (!self) return event;
            NSView *hit = [event.window.contentView hitTest:[event.window.contentView convertPoint:event.locationInWindow fromView:nil]];
            if (event.window != composer.window || (!([hit isDescendantOf:self->_commandPalette]) && ![hit isDescendantOf:composer]))
                [self dismissCommandPalette];
            return event;
        }];
        NSView *surface = composer == _floatingComposerTextView ? _floatingComposerSurface : _composerSurface;
        surface.postsFrameChangedNotifications = YES;
        _commandLayoutObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification
            object:surface queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; [weakSelf layoutCommandPalette]; }];
    }
    [self layoutCommandPalette];
    [composer.window makeFirstResponder:composer];
    if (!bridge) {
        [self prepareBridgeForSessionID:sessionID completion:^(PTClaudeBridge *connected) {
            if (connected && self->_commandMenuComposer == composer && self->_commandPalette.superview) {
                self->_commandPalette.commands = [self commandSuggestions:connected query:[self commandQueryForComposer:composer] ?: @""];
                [self layoutCommandPalette];
            }
        }];
    }
}

- (void)insertClaudeCommand:(NSDictionary *)command {
    PTComposerTextView *composer = _commandMenuComposer;
    if (!composer) return;
    NSString *text = composer.string;
    NSRange range = composer.selectedRange;
    if ([text hasPrefix:@"/"]) {
        NSRange end = [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        range = NSMakeRange(0, end.location == NSNotFound ? text.length : end.location);
    }
    [self dismissCommandPalette];
    [composer.window makeFirstResponder:composer];
    NSString *suffix = NSMaxRange(range) < text.length && [NSCharacterSet.whitespaceAndNewlineCharacterSet
        characterIsMember:[text characterAtIndex:NSMaxRange(range)]] ? @"" : @" ";
    [composer insertText:[NSString stringWithFormat:@"/%@%@", command[@"name"], suffix] replacementRange:range];
}

- (void)showClaudeCommandResult:(id)sender {
    [_composerOptionsPopover close];
    NSString *sessionID = _configurationSessionID ?: _selectedSession.sessionID;
    NSString *text = nil;
    for (PTWorkspaceTab *tab in _workspaceTabs) if ([tab.sessionID isEqual:sessionID]) text = tab.commandOutput;
    text = text ?: PTL(@"暂无命令结果", @"No command result yet");
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 520, 340)];
    scroll.hasVerticalScroller = YES;
    NSTextView *view = [[NSTextView alloc] initWithFrame:scroll.bounds];
    view.editable = NO; view.selectable = YES; view.textContainerInset = NSMakeSize(14, 14);
    view.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    view.autoresizingMask = NSViewWidthSizable;
    view.textContainer.widthTracksTextView = YES;
    view.string = text; scroll.documentView = view;
    NSViewController *controller = [NSViewController new]; controller.view = scroll;
    _commandResultPopover = [NSPopover new];
    _commandResultPopover.behavior = NSPopoverBehaviorTransient;
    _commandResultPopover.contentViewController = controller;
    _commandResultPopover.contentSize = scroll.frame.size;
    NSView *anchor = [sessionID isEqual:_floatingSessionID] && _floatingPanel.visible ? _floatingEffortButton : _composerEffortButton;
    [_commandResultPopover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
}

- (void)showComposerModelPage:(id)sender {
    (void)sender;
    _composerConfigurationPage = @"model";
    NSString *model = [self composerModelForSessionID:_configurationSessionID ?: _selectedSession.sessionID];
    _composerEffortPopoverTitle = nil;
    PTAnimatedButton *back = [self composerPopoverButtonWithTitle:PTL(@"‹  选择模型", @"‹  Choose model")
        action:@selector(showComposerAdvancedPage:) identifier:nil];
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:back];
    for (NSArray<NSString *> *entry in [self composerModelEntries]) {
        NSString *mark = [entry[2] isEqual:model] ? @"✓  " : @"    ";
        PTAnimatedButton *row = [self composerPopoverButtonWithTitle:
            [mark stringByAppendingString:entry[0]] action:@selector(changeComposerModel:) identifier:entry[2]];
        [views addObject:row];
    }
    [self replaceComposerOptionsWithViews:views height:300];
}

- (void)showComposerOptions:(id)sender {
    _configurationSessionID = sender == _floatingEffortButton ? _floatingSessionID : _selectedSession.sessionID;
    if (!_composerOptionsPopover) {
        _composerOptionsPopover = [[NSPopover alloc] init];
        _composerOptionsPopover.behavior = NSPopoverBehaviorTransient;
        _composerOptionsPopover.animates = YES;
        NSViewController *controller = [[NSViewController alloc] init];
        PTAppearanceSurfaceView *surface = [[PTAppearanceSurfaceView alloc] initWithFrame:NSMakeRect(0, 0, 310, 216)];
        surface.surfaceStyle = PTAppearanceSurfaceStyleCard;
        _composerOptionsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _composerOptionsStack.translatesAutoresizingMaskIntoConstraints = NO;
        _composerOptionsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _composerOptionsStack.alignment = NSLayoutAttributeLeading;
        _composerOptionsStack.spacing = 9;
        _composerOptionsStack.edgeInsets = NSEdgeInsetsMake(15, 15, 15, 15);
        [surface addSubview:_composerOptionsStack];
        [NSLayoutConstraint activateConstraints:@[
            [_composerOptionsStack.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
            [_composerOptionsStack.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
            [_composerOptionsStack.topAnchor constraintEqualToAnchor:surface.topAnchor],
            [_composerOptionsStack.bottomAnchor constraintLessThanOrEqualToAnchor:surface.bottomAnchor]
        ]];
        controller.view = surface;
        _composerOptionsPopover.contentViewController = controller;
    }
    [self showComposerEffortPage:nil];
    [_composerOptionsPopover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSRectEdgeMaxY];
    [[self bridgeForSessionID:_configurationSessionID] refreshSettingsWithCompletion:nil];
}

- (void)changeComposerEffort:(PTEffortSlider *)slider {
    NSArray<NSString *> *levels = [self composerEffortLevels];
    if (slider.submittedIndex < 0 || slider.submittedIndex >= (NSInteger)levels.count) return;
    NSString *effort = levels[slider.submittedIndex];
    NSString *sessionID = _configurationSessionID ?: _selectedSession.sessionID;
    [self sendOutgoingMessage:[NSString stringWithFormat:@"/effort %@", effort]
                    imagePNGs:@[]
                 forSessionID:sessionID
                      success:^{
        [self updateComposerConfigurationButtons];
        [self refreshComposerConfigurationPopoverForSessionID:sessionID];
        [self showConfigurationStatus:[NSString stringWithFormat:PTL(@"当前推理强度：%@", @"Current effort: %@"),
            [self composerEffortTitle:[self composerEffortForSessionID:sessionID]]] forSessionID:sessionID];
    } failureResponder:nil];
}

- (void)changeComposerModel:(PTAnimatedButton *)sender {
    [self changeComposerToModel:sender.identifier];
}

- (void)changeComposerToModel:(NSString *)modelID {
    if (modelID.length == 0) return;
    NSString *sessionID = [_configurationSessionID ?: _selectedSession.sessionID copy];
    [self sendOutgoingMessage:[NSString stringWithFormat:@"/model %@", modelID]
                    imagePNGs:@[]
                 forSessionID:sessionID
                      success:^{
        [self updateComposerConfigurationButtons];
        [self refreshComposerConfigurationPopoverForSessionID:sessionID];
        [self showConfigurationStatus:[NSString stringWithFormat:PTL(@"当前模型：%@", @"Current model: %@"),
            [self composerModelShortTitle:[self composerModelForSessionID:sessionID]]] forSessionID:sessionID];
    } failureResponder:nil];
}

- (void)refreshAgentStateAndControls {
    _agentState.selectedSessionID = _selectedSession.sessionID ?: @"";
    _agentState.boundSessionID = _bridge.sessionID ?: @"";
    _agentState.bridgeRunning = _bridge.running;
    BOOL ready = _agentState.commandsEnabled;
    BOOL awaiting = _bridge.responding || _awaitingClaudeBaselineBySessionID[_selectedSession.sessionID] != nil;
    _composerTextView.editable = ready;
    _sendButton.enabled = ready;
    _sendButton.title = awaiting ? @"■" : @"↑";
    _sendButton.font = [NSFont systemFontOfSize:(awaiting ? 18 : 23) weight:NSFontWeightMedium];
    _sendButton.action = awaiting
        ? @selector(stopSelectedClaudeOutput:) : @selector(sendMessage:);
    _sendButton.toolTip = awaiting
        ? PTL(@"停止 Claude 输出", @"Stop Claude output")
        : PTL(@"发送消息", @"Send message");
    _imageButton.enabled = ready;
    _composerSurface.dropEnabled = ready;
    _composerEffortButton.enabled = ready;
    _remoteButton.enabled = ready;
    _modelPicker.enabled = ready;
    _compactButton.enabled = ready;
    _compactButton.title = _bridge.compacting ? PTL(@"压缩中…", @"Compacting…") : @"Compact";
    [self updateComposerConfigurationButtons];

    NSString *ttyState = _bridge.running
        ? PTL(@"Claude 后台已连接", @"Claude background session connected")
        : PTL(@"Claude 后台未连接", @"Claude background session disconnected");
    NSString *mode = [_bridge.permissionMode isEqual:@"bypassPermissions"] ? @"Bypass" : _bridge.permissionMode;
    _inspectorConnectionLabel.stringValue = [NSString stringWithFormat:@"%@ · %@\n%@",
        ttyState, mode ?: @"—", ready ? PTL(@"当前选中会话可操作", @"Selected conversation is available")
                        : PTL(@"请选择会话", @"Choose a conversation")];
    _composerTargetLabel.stringValue = awaiting
        ? PTL(@"Claude 正在工作 · 点击停止键中断",
              @"Claude is working · click Stop to interrupt")
        : ready
        ? [NSString stringWithFormat:PTL(@"发送给：%@ · 可添加或拖入附件 · ↩ 发送，⌘↩ 换行", @"To: %@ · add or drop attachments · ↩ send, ⌘↩ newline"),
            _selectedSession.title ?: PTL(@"当前会话", @"Current conversation")]
        : PTL(@"请选择会话", @"Choose a conversation");
    _bottomStatusLabel.stringValue = awaiting
        ? PTL(@"■ 正在工作 · 可随时停止",
              @"■ Working · Stop is available")
        : _bridge.running
        ? [NSString stringWithFormat:PTL(@"● 已连接 · %@ · 等待操作 · Claude Code 后台执行", @"● Connected · %@ · ready · Claude Code runs in the background"),
            _selectedSession.title ?: PTL(@"当前会话", @"Current conversation")]
        : PTL(@"○ Claude 后台未连接 · 操作时自动连接", @"○ Claude background session disconnected · controls remain available");
    [self updateFloatingComposerState];
}

- (void)updateFloatingComposerState {
    if (!_floatingComposerTextView || !_floatingSendButton) return;
    PTSessionInfo *session = [self sessionWithID:_floatingSessionID];
    PTClaudeBridge *floatingBridge = [self bridgeForSessionID:_floatingSessionID];
    BOOL awaiting = floatingBridge.responding || _awaitingClaudeBaselineBySessionID[_floatingSessionID] != nil;
    BOOL ready = _floatingPanel.visible && _floatingSessionID.length > 0;
    _floatingComposerTextView.editable = ready;
    _floatingSendButton.enabled = ready;
    _floatingSendButton.title = awaiting ? @"■" : @"↑";
    _floatingSendButton.font = [NSFont systemFontOfSize:(awaiting ? 17 : 21) weight:NSFontWeightMedium];
    _floatingSendButton.action = awaiting
        ? @selector(stopFloatingClaudeOutput:) : @selector(sendFloatingMessage:);
    _floatingSendButton.toolTip = awaiting
        ? PTL(@"停止 Claude 输出", @"Stop Claude output")
        : PTL(@"发送消息", @"Send message");
    _floatingImageButton.enabled = ready;
    _floatingComposerSurface.dropEnabled = ready;
    _floatingEffortButton.enabled = ready;
    if (awaiting) {
        _floatingComposerLabel.stringValue = PTL(@"Claude 正在工作 · 点击停止键中断",
                                                   @"Claude is working · click Stop to interrupt");
    } else if (ready) {
        _floatingComposerLabel.stringValue = [NSString stringWithFormat:
            PTL(@"发送给：%@ · 可添加或拖入附件 · ↩ 发送，⌘↩ 换行", @"To: %@ · add or drop attachments · ↩ send, ⌘↩ newline"),
            session.title ?: PTL(@"悬浮会话", @"Floating conversation")];
    } else if (_agentState.sendInFlight && floatingBridge.running) {
        _floatingComposerLabel.stringValue = PTL(@"正在提交到 Claude Code…", @"Submitting to Claude Code…");
    } else {
        _floatingComposerLabel.stringValue = [NSString stringWithFormat:
            PTL(@"发送给：%@ · Claude 后台尚未连接", @"To: %@ · Claude background session is not connected"),
            session.title ?: PTL(@"悬浮会话", @"Floating conversation")];
    }
}

- (void)updateFloatingTitleForSession:(PTSessionInfo *)session {
    if (!_floatingPanel || !session) return;
    NSString *quota = _planUsageAvailable
        ? [NSString stringWithFormat:@"5h %@%% · 7d %@%%",
            _fiveHourPercent < 10.0 ? [NSString stringWithFormat:@"%.1f", _fiveHourPercent] : [NSString stringWithFormat:@"%.0f", _fiveHourPercent],
            _sevenDayPercent < 10.0 ? [NSString stringWithFormat:@"%.1f", _sevenDayPercent] : [NSString stringWithFormat:@"%.0f", _sevenDayPercent]]
        : @"额度 —";
    NSString *cost = session.apiCostAvailable
        ? [NSString stringWithFormat:@"API≈%@", PTAPIEquivalentCostDisplay(session.apiEquivalentCostUSD)]
        : @"API≈—";
    _floatingPanel.title = [NSString stringWithFormat:@"%@ · %@ · %@",
        session.title ?: @"悬浮对话", quota, cost];
}

static NSColor *PTQuotaTierColor(double percent) {
    if (percent >= 90.0) return NSColor.systemRedColor;
    if (percent >= 60.0) return NSColor.systemOrangeColor;
    return NSColor.systemGreenColor;
}

static NSString *PTContextCategoryDisplayName(NSString *key) {
    NSDictionary<NSString *, NSArray<NSString *> *> *names = @{
        @"system_prompt": @[@"系统提示词", @"System prompt"],
        @"system_tools": @[@"系统工具", @"System tools"],
        @"memory_files": @[@"记忆文件", @"Memory files"],
        @"skills": @[@"Skills", @"Skills"],
        @"messages": @[@"消息", @"Messages"],
        @"conversation_system": @[@"对话 · 系统开销", @"Conversation & system"],
        @"free_space": @[@"剩余空间", @"Free space"],
        @"autocompact_buffer": @[@"自动压缩缓冲", @"Autocompact buffer"]
    };
    NSArray<NSString *> *localized = names[key];
    return localized ? PTL(localized[0], localized[1]) : key;
}

- (void)clearContextBreakdownRows {
    for (NSView *view in _inspectorContextDetailStack.arrangedSubviews.copy) {
        [_inspectorContextDetailStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

- (void)rebuildContextBreakdownRows:(NSArray<NSDictionary *> *)breakdown {
    [self clearContextBreakdownRows];
    if (breakdown.count == 0) {
        NSString *message = PTL(@"会话刚开始，还没有 usage 数据。",
                                @"Session just started — no usage data yet.");
        NSTextField *empty = [self label:message size:10 weight:NSFontWeightRegular
                                   color:NSColor.tertiaryLabelColor];
        empty.lineBreakMode = NSLineBreakByWordWrapping;
        empty.maximumNumberOfLines = 0;
        [empty setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
        [empty setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_inspectorContextDetailStack addArrangedSubview:empty];
        [empty.widthAnchor constraintEqualToAnchor:_inspectorContextDetailStack.widthAnchor].active = YES;
        return;
    }
    NSDictionary<NSString *, NSColor *> *colors = @{
        @"system_prompt": NSColor.systemGrayColor,
        @"system_tools": PTWarmBorderColor(),
        @"memory_files": NSColor.systemPinkColor,
        @"skills": NSColor.systemOrangeColor,
        @"messages": NSColor.systemPurpleColor,
        @"conversation_system": NSColor.systemPurpleColor,
        @"free_space": NSColor.systemGreenColor,
        @"autocompact_buffer": NSColor.tertiaryLabelColor
    };
    for (NSDictionary *entry in breakdown) {
        NSString *key = [entry[@"category"] isKindOfClass:NSString.class]
            ? entry[@"category"] : @"";
        NSColor *color = colors[key] ?: PTWarmAccentColor();
        double percentage = [entry[@"percentage"] doubleValue];

        NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        NSTextField *dot = [self label:@"●" size:8.5 weight:NSFontWeightBold color:color];
        NSTextField *name = [self label:PTContextCategoryDisplayName(key)
                                   size:10.5 weight:NSFontWeightMedium color:NSColor.labelColor];
        NSTextField *value = [self label:[NSString stringWithFormat:@"%@ · %.1f%%",
            PTCompactTokenCount([entry[@"tokens"] unsignedIntegerValue]), percentage]
                                    size:10.5 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
        value.font = [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightSemibold];
        PTMeterView *meter = [[PTMeterView alloc] initWithFrame:NSZeroRect];
        meter.translatesAutoresizingMaskIntoConstraints = NO;
        meter.progress = percentage / 100.0;
        meter.fillColor = color;
        [row addSubview:dot];
        [row addSubview:name];
        [row addSubview:value];
        [row addSubview:meter];
        [NSLayoutConstraint activateConstraints:@[
            [dot.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [dot.firstBaselineAnchor constraintEqualToAnchor:name.firstBaselineAnchor],
            [name.topAnchor constraintEqualToAnchor:row.topAnchor],
            [name.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:5],
            [value.firstBaselineAnchor constraintEqualToAnchor:name.firstBaselineAnchor],
            [value.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [value.leadingAnchor constraintGreaterThanOrEqualToAnchor:name.trailingAnchor constant:6],
            [meter.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
            [meter.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [meter.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [meter.heightAnchor constraintEqualToConstant:4],
            [meter.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
        ]];
        [_inspectorContextDetailStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:_inspectorContextDetailStack.widthAnchor].active = YES;
    }
}

- (void)clearCostBreakdownRows {
    for (NSView *view in _inspectorCostDetailStack.arrangedSubviews.copy) {
        [_inspectorCostDetailStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

- (void)rebuildCostBreakdownRows:(NSDictionary<NSString *, NSDictionary *> *)breakdown {
    NSArray<NSString *> *modelKeys = [breakdown.allKeys sortedArrayUsingComparator:
        ^NSComparisonResult(NSString *modelA, NSString *modelB) {
            double costA = [breakdown[modelA][@"cost"] doubleValue];
            double costB = [breakdown[modelB][@"cost"] doubleValue];
            return costA < costB ? NSOrderedDescending : (costA > costB ? NSOrderedAscending : NSOrderedSame);
        }];
    [self clearCostBreakdownRows];

    NSArray<NSColor *> *modelColors = @[PTWarmAccentColor(), NSColor.systemBlueColor,
        NSColor.systemPurpleColor, NSColor.systemTealColor];
    NSUInteger colorIndex = 0;
    for (NSString *modelKey in modelKeys) {
        NSDictionary *entry = breakdown[modelKey];
        double modelCost = [entry[@"cost"] doubleValue];
        double share = _selectedSession.apiEquivalentCostUSD > 0
            ? modelCost / _selectedSession.apiEquivalentCostUSD : 0;

        NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        NSTextField *nameLabel = [self label:modelKey size:11 weight:NSFontWeightSemibold color:NSColor.labelColor];
        NSTextField *costLabel = [self label:PTAPIEquivalentCostDisplay(modelCost) size:11 weight:NSFontWeightBold color:NSColor.labelColor];
        PTMeterView *meter = [[PTMeterView alloc] initWithFrame:NSZeroRect];
        meter.translatesAutoresizingMaskIntoConstraints = NO;
        meter.progress = share;
        meter.fillColor = modelColors[colorIndex % modelColors.count];
        colorIndex++;
        NSTextField *tokenCaption = [self label:[NSString stringWithFormat:
            @"%@ input · %@ output · %@ cache read · %@ cache write",
            PTCompactTokenCount([entry[@"input"] unsignedIntegerValue]),
            PTCompactTokenCount([entry[@"output"] unsignedIntegerValue]),
            PTCompactTokenCount([entry[@"cacheRead"] unsignedIntegerValue]),
            PTCompactTokenCount([entry[@"cacheWrite"] unsignedIntegerValue])]
            size:10 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
        tokenCaption.lineBreakMode = NSLineBreakByWordWrapping;
        tokenCaption.maximumNumberOfLines = 0;

        [row addSubview:nameLabel];
        [row addSubview:costLabel];
        [row addSubview:meter];
        [row addSubview:tokenCaption];
        [NSLayoutConstraint activateConstraints:@[
            [nameLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
            [nameLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [costLabel.firstBaselineAnchor constraintEqualToAnchor:nameLabel.firstBaselineAnchor],
            [costLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [costLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:nameLabel.trailingAnchor constant:6],
            [meter.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:5],
            [meter.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [meter.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [meter.heightAnchor constraintEqualToConstant:5],
            [tokenCaption.topAnchor constraintEqualToAnchor:meter.bottomAnchor constant:4],
            [tokenCaption.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [tokenCaption.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [tokenCaption.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
        ]];
        [_inspectorCostDetailStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:_inspectorCostDetailStack.widthAnchor].active = YES;
    }
}

- (void)updateUsageDisplays {
    if (_planUsageAvailable) {
        NSString *fivePercentText = _fiveHourPercent < 10.0
            ? [NSString stringWithFormat:@"%.1f", _fiveHourPercent]
            : [NSString stringWithFormat:@"%.0f", _fiveHourPercent];
        NSString *sevenPercentText = _sevenDayPercent < 10.0
            ? [NSString stringWithFormat:@"%.1f", _sevenDayPercent]
            : [NSString stringWithFormat:@"%.0f", _sevenDayPercent];
        _quotaLabel.stringValue = [NSString stringWithFormat:@"5h %@%% · 7d %@%%",
            fivePercentText, sevenPercentText];
        _quotaLabel.textColor = MAX(_fiveHourPercent, _sevenDayPercent) >= 80.0
            ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
        NSString *fiveCountdown = PTCountdownDescription(_fiveHourResetAt, NSDate.date);
        NSString *sevenCountdown = PTCountdownDescription(_sevenDayResetAt, NSDate.date);
        _quotaLabel.toolTip = [NSString stringWithFormat:
            PTL(@"5 小时：%@%%，%@\n7 天：%@%%，%@\n随本会话每次 API 响应更新",
                @"5 hours: %@%%, %@\n7 days: %@%%, %@\nUpdates with each API response in this conversation"),
            fivePercentText, fiveCountdown, sevenPercentText, sevenCountdown];

        _inspectorFiveHourPercentLabel.stringValue = [NSString stringWithFormat:@"%@%%", fivePercentText];
        _inspectorFiveHourPercentLabel.textColor = PTQuotaTierColor(_fiveHourPercent);
        _inspectorFiveHourMeter.progress = _fiveHourPercent / 100.0;
        _inspectorFiveHourMeter.fillColor = PTQuotaTierColor(_fiveHourPercent);
        _inspectorFiveHourCaption.stringValue = fiveCountdown;

        _inspectorSevenDayPercentLabel.stringValue = [NSString stringWithFormat:@"%@%%", sevenPercentText];
        _inspectorSevenDayPercentLabel.textColor = PTQuotaTierColor(_sevenDayPercent);
        _inspectorSevenDayMeter.progress = _sevenDayPercent / 100.0;
        _inspectorSevenDayMeter.fillColor = PTQuotaTierColor(_sevenDayPercent);
        _inspectorSevenDayCaption.stringValue = sevenCountdown;
    } else {
        _quotaLabel.stringValue = @"5h — · 7d —";
        _quotaLabel.textColor = NSColor.secondaryLabelColor;
        NSString *reason = _planUsageError.length ? _planUsageError : @"正在读取 Claude 套餐额度";
        _quotaLabel.toolTip = reason;

        _inspectorFiveHourPercentLabel.stringValue = @"—";
        _inspectorFiveHourPercentLabel.textColor = NSColor.labelColor;
        _inspectorFiveHourMeter.progress = 0;
        _inspectorFiveHourCaption.stringValue = reason;

        _inspectorSevenDayPercentLabel.stringValue = @"—";
        _inspectorSevenDayPercentLabel.textColor = NSColor.labelColor;
        _inspectorSevenDayMeter.progress = 0;
        _inspectorSevenDayCaption.stringValue = reason;
    }

    if (_selectedSession.apiCostAvailable) {
        _inspectorCostHeadline.stringValue = PTAPIEquivalentCostDisplay(_selectedSession.apiEquivalentCostUSD);
        if (_selectedSession.codeLinesAdded > 0 || _selectedSession.codeLinesRemoved > 0) {
            NSMutableAttributedString *pill = [[NSMutableAttributedString alloc] init];
            NSFont *pillFont = [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightSemibold];
            [pill appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@" +%lu ", (unsigned long)_selectedSession.codeLinesAdded]
                    attributes:@{NSForegroundColorAttributeName: NSColor.systemGreenColor, NSFontAttributeName: pillFont}]];
            [pill appendAttributedString:[[NSAttributedString alloc]
                initWithString:[NSString stringWithFormat:@"/ -%lu ", (unsigned long)_selectedSession.codeLinesRemoved]
                    attributes:@{NSForegroundColorAttributeName: NSColor.systemRedColor, NSFontAttributeName: pillFont}]];
            _inspectorCostChangesPill.attributedStringValue = pill;
            _inspectorCostChangesPill.hidden = NO;
        } else {
            _inspectorCostChangesPill.hidden = YES;
        }

        // 跟 changedFiles / tasks 一样按值比较：这段每次 transcript 变动都会被调到，
        // 无条件重建整棵子视图树 + 重新激活 Auto Layout 约束会白白拖慢主线程。
        NSDictionary<NSString *, NSDictionary *> *breakdown = _selectedSession.modelUsageBreakdown ?: @{};
        if (![_renderedCostBreakdown isEqualToDictionary:breakdown]) {
            _renderedCostBreakdown = [breakdown copy];
            [self rebuildCostBreakdownRows:breakdown];
        }
    } else if (!_renderedCostBreakdown || _renderedCostBreakdown.count > 0) {
        _renderedCostBreakdown = @{};
        _inspectorCostHeadline.stringValue = PTL(@"暂无可计价 usage", @"No priceable usage yet");
        _inspectorCostChangesPill.hidden = YES;
        [self clearCostBreakdownRows];
    }

    if (_floatingPanel.visible && _floatingSessionID.length) {
        [self updateFloatingTitleForSession:[self sessionWithID:_floatingSessionID]];
    }
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
    [self updateUsageDisplays];
}

- (void)refreshClaudeUsage:(NSTimer *)timer {
    (void)timer;
    [[self bridgeForSessionID:_selectedSession.sessionID] refreshUsage];
}

- (void)reloadGitDirectoryPickerSelecting:(NSString *)selectedPath {
    [_gitDirectoryPicker removeAllItems];
    for (NSString *path in _gitDirectoryPaths ?: @[]) {
        NSString *name = path.lastPathComponent.length ? path.lastPathComponent : path;
        [_gitDirectoryPicker addItemWithTitle:name];
        NSMenuItem *item = _gitDirectoryPicker.lastItem;
        item.representedObject = path;
        item.toolTip = path;
    }
    _gitDirectoryPicker.enabled = _gitDirectoryPaths.count > 0;
    _removeGitDirectoryButton.enabled = _gitDirectoryPaths.count > 0;
    _gitPublishButton.enabled = _gitDirectoryPaths.count > 0 && !_gitActionInFlight;
    if (_gitDirectoryPaths.count == 0) {
        [_gitDirectoryPicker addItemWithTitle:PTL(@"尚未发现目录", @"No directory found")];
        _gitObservedDirectory = nil;
        return;
    }
    NSUInteger selectedIndex = [_gitDirectoryPaths indexOfObject:selectedPath];
    if (selectedIndex == NSNotFound) selectedIndex = 0;
    [_gitDirectoryPicker selectItemAtIndex:selectedIndex];
    _gitObservedDirectory = [_gitDirectoryPaths[selectedIndex] copy];
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
        [self reloadGitDirectoryPickerSelecting:preferred];
    } else if (!_gitObservedDirectory.length && nextPaths.count > 0) {
        [self reloadGitDirectoryPickerSelecting:preferred];
    }
}

- (void)restoreInspectorAfterToolWorkspaceCollapseIfNeeded:(BOOL)animated {
    if (!_restoreInspectorAfterTools) return;
    _restoreInspectorAfterTools = NO;
    [self setInspectorExpanded:YES animated:animated];
}

- (void)setToolWorkspaceExpanded:(BOOL)expanded animated:(BOOL)animated {
    if (!_toolWorkspaceView || !_toolWorkspaceWidthConstraint) return;
    if (expanded && _inspectorExpanded) {
        _restoreInspectorAfterTools = YES;
        [self setInspectorExpanded:NO animated:NO];
    }
    NSUInteger generation = ++_toolWorkspaceAnimationGeneration;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (expanded) {
        if (![_workspaceSplitView.arrangedSubviews containsObject:_toolWorkspaceView]) {
            [_workspaceSplitView addArrangedSubview:_toolWorkspaceView];
            [_workspaceSplitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];
        }
        CGFloat available = NSWidth(_workspaceSplitView.bounds);
        CGFloat desired = _toolWorkspaceWidthBeforeCollapse > 0
            ? _toolWorkspaceWidthBeforeCollapse : MAX(360.0, available * 0.58);
        CGFloat target = desired;
        _toolWorkspaceView.hidden = NO;
        _gitDiffScroll.hidden = ![_activeToolPageKind isEqual:@"review"];
        _filePreviewWebView.hidden = ![_activeToolPageKind isEqual:@"file"];
        _toolWorkspaceWidthConstraint.active = YES;
        if (_toolWorkspaceWidthConstraint.constant <= 0.0) {
            _toolWorkspaceWidthConstraint.constant = 0.0;
            _toolWorkspaceView.alphaValue = reduceMotion ? 1.0 : 0.0;
            [_window.contentView layoutSubtreeIfNeeded];
        }
        if (!animated || reduceMotion) {
            _toolWorkspaceWidthConstraint.constant = target;
            _toolWorkspaceView.alphaValue = 1.0;
            [_window.contentView layoutSubtreeIfNeeded];
            return;
        }
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.22;
            context.timingFunction = [CAMediaTimingFunction functionWithName:
                kCAMediaTimingFunctionEaseInEaseOut];
            self->_toolWorkspaceWidthConstraint.animator.constant = target;
            self->_toolWorkspaceView.animator.alphaValue = 1.0;
            [self->_window.contentView layoutSubtreeIfNeeded];
        } completionHandler:nil];
        return;
    }

    CGFloat visibleWidth = NSWidth(_toolWorkspaceView.frame);
    if (visibleWidth > 0.0) _toolWorkspaceWidthBeforeCollapse = visibleWidth;
    if (!animated || reduceMotion) {
        _toolWorkspaceWidthConstraint.constant = 0.0;
        _toolWorkspaceView.alphaValue = 1.0;
        _toolWorkspaceView.hidden = YES;
        _gitDiffScroll.hidden = YES;
        _filePreviewWebView.hidden = YES;
        [_workspaceSplitView removeArrangedSubview:_toolWorkspaceView];
        [_toolWorkspaceView removeFromSuperview];
        [_window.contentView layoutSubtreeIfNeeded];
        [self restoreInspectorAfterToolWorkspaceCollapseIfNeeded:animated];
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        context.timingFunction = [CAMediaTimingFunction functionWithName:
            kCAMediaTimingFunctionEaseInEaseOut];
        self->_toolWorkspaceWidthConstraint.animator.constant = 0.0;
        self->_toolWorkspaceView.animator.alphaValue = 0.0;
        [self->_window.contentView layoutSubtreeIfNeeded];
    } completionHandler:^{
        if (generation != self->_toolWorkspaceAnimationGeneration) return;
        self->_toolWorkspaceView.hidden = YES;
        self->_gitDiffScroll.hidden = YES;
        self->_filePreviewWebView.hidden = YES;
        self->_toolWorkspaceView.alphaValue = 1.0;
        [self->_workspaceSplitView removeArrangedSubview:self->_toolWorkspaceView];
        [self->_toolWorkspaceView removeFromSuperview];
        [self->_window.contentView layoutSubtreeIfNeeded];
        [self restoreInspectorAfterToolWorkspaceCollapseIfNeeded:animated];
    }];
}

- (void)setInspectorExpanded:(BOOL)expanded animated:(BOOL)animated {
    [self setInspectorExpanded:expanded animated:animated completion:nil];
}

- (void)setInspectorExpanded:(BOOL)expanded
                     animated:(BOOL)animated
                   completion:(void (^)(void))completion {
    if (!_inspectorView || !_window.contentView) {
        if (completion) completion();
        return;
    }
    _inspectorExpanded = expanded;
    [self updateInspectorPresentation];
    if (_inspectorFloating) {
        _inspectorView.hidden = !expanded;
        _inspectorView.alphaValue = 1.0;
        _inspectorToggleButton.state = expanded
            ? NSControlStateValueOn : NSControlStateValueOff;
        if (completion) completion();
        return;
    }

    NSUInteger generation = ++_inspectorAnimationGeneration;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    CGFloat targetWidth = [self adaptiveInspectorWidth];
    _inspectorWidthConstraint.constant = targetWidth;
    if (expanded) {
        _inspectorView.hidden = NO;
        _inspectorView.alphaValue = reduceMotion ? 1.0 : 0.0;
        if (!animated || reduceMotion) {
            _inspectorView.alphaValue = 1.0;
            if (completion) completion();
        } else {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.22;
                context.timingFunction = [CAMediaTimingFunction functionWithName:
                    kCAMediaTimingFunctionEaseInEaseOut];
                self->_inspectorView.animator.alphaValue = 1.0;
            } completionHandler:^{
                if (generation != self->_inspectorAnimationGeneration) return;
                if (completion) completion();
            }];
        }
        _inspectorToggleButton.state = NSControlStateValueOn;
        return;
    }

    if (!animated || reduceMotion) {
        _inspectorView.alphaValue = 1.0;
        _inspectorView.hidden = YES;
        if (completion) completion();
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.22;
            context.timingFunction = [CAMediaTimingFunction functionWithName:
                kCAMediaTimingFunctionEaseInEaseOut];
            self->_inspectorView.animator.alphaValue = 0.0;
        } completionHandler:^{
            if (generation != self->_inspectorAnimationGeneration) return;
            self->_inspectorView.hidden = YES;
            self->_inspectorView.alphaValue = 1.0;
            if (completion) completion();
        }];
    }
    _inspectorToggleButton.state = NSControlStateValueOff;
}

- (void)closeToolWorkspace:(id)sender {
    (void)sender;
    _reviewToolPageOpen = NO;
    _gitDiffExpanded = NO;
    _gitReviewShowsTranscriptEdits = NO;
    _transcriptEditReviewEvents = nil;
    _gitDiffGeneration++;
    [_gitDiffProgress stopAnimation:nil];
    _gitDiffProgress.hidden = YES;
    _gitDiffRefreshButton.hidden = YES;
    _gitDiffToggleButton.title = PTL(@"打开 Git 审查  ›", @"Open Git Review  ›");
    if (_fileToolPageOpen) [self showToolPageKind:@"file" animated:YES];
    else {
        _activeToolPageKind = nil;
        [self rebuildToolTabBar];
        [self setToolWorkspaceExpanded:NO animated:YES];
    }
}

- (void)gitDirectorySelectionChanged:(id)sender {
    (void)sender;
    NSString *path = [_gitDirectoryPicker.selectedItem.representedObject isKindOfClass:NSString.class]
        ? _gitDirectoryPicker.selectedItem.representedObject : @"";
    if (path.length == 0) return;
    _gitObservedDirectory = [path copy];
    _gitDirectoryManuallySelected = YES;
    _statusLabel.stringValue = PTL(@"已切换 PrettyTerm 的 Git 观察目录；Claude Code 目录未改变", @"PrettyTerm's Git directory changed; Claude Code's directory did not");
    _bottomStatusLabel.stringValue = PTL(@"Git 观察目录已切换 · Claude Code 如需访问，请执行 /add-dir", @"Git observation changed · run /add-dir if Claude Code needs access");
    if (_gitDiffExpanded && !_gitReviewShowsTranscriptEdits) [self refreshGitDiff:nil];
}

- (void)addManualGitDirectory:(id)sender {
    (void)sender;
    NSString *rawPath = [_gitDirectoryInput.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *path = rawPath.stringByExpandingTildeInPath.stringByStandardizingPath;
    BOOL isDirectory = NO;
    BOOL valid = path.length > 0 && [path hasPrefix:@"/"] &&
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory;
    if (!valid) {
        _statusLabel.stringValue = PTL(@"请输入存在的绝对文件夹路径", @"Enter an existing absolute folder path");
        return;
    }
    if (!_gitDirectoryPaths) _gitDirectoryPaths = [NSMutableArray array];
    [_suppressedGitDirectoryPaths removeObject:path];
    [NSUserDefaults.standardUserDefaults setObject:
        [_suppressedGitDirectoryPaths.allObjects sortedArrayUsingSelector:@selector(compare:)]
        forKey:@"PTGitSuppressedDirectories"];
    if (![_gitDirectoryPaths containsObject:path]) [_gitDirectoryPaths insertObject:path atIndex:0];
    _gitObservedDirectory = [path copy];
    _gitDirectoryManuallySelected = YES;
    [NSUserDefaults.standardUserDefaults setObject:_gitDirectoryPaths forKey:@"PTGitObservedDirectories"];
    [self reloadGitDirectoryPickerSelecting:path];
    _gitDirectoryInput.stringValue = @"";
    _statusLabel.stringValue = PTL(@"已添加 Git 观察目录；这不会改变 Claude Code 的目录", @"Git observation directory added; Claude Code's directory is unchanged");
    _bottomStatusLabel.stringValue = [NSString stringWithFormat:PTL(@"如需 Claude 访问，请在 Claude Code 执行 /add-dir %@", @"To give Claude access, run /add-dir %@ in Claude Code"), path];
    if (_gitDiffExpanded && !_gitReviewShowsTranscriptEdits) [self refreshGitDiff:nil];
}

- (void)removeSelectedGitDirectory:(id)sender {
    (void)sender;
    NSString *path = [_gitDirectoryPicker.selectedItem.representedObject
        isKindOfClass:NSString.class] ? _gitDirectoryPicker.selectedItem.representedObject : @"";
    NSUInteger removedIndex = [_gitDirectoryPaths indexOfObject:path];
    if (path.length == 0 || removedIndex == NSNotFound) return;

    if (!_suppressedGitDirectoryPaths) {
        _suppressedGitDirectoryPaths = [NSMutableSet set];
    }
    [_suppressedGitDirectoryPaths addObject:path];
    [NSUserDefaults.standardUserDefaults setObject:
        [_suppressedGitDirectoryPaths.allObjects sortedArrayUsingSelector:@selector(compare:)]
        forKey:@"PTGitSuppressedDirectories"];
    [_gitDirectoryPaths removeObjectAtIndex:removedIndex];
    [NSUserDefaults.standardUserDefaults setObject:_gitDirectoryPaths
        forKey:@"PTGitObservedDirectories"];

    NSString *nextSelection = @"";
    if (_gitDirectoryPaths.count > 0) {
        NSUInteger nextIndex = MIN(removedIndex, _gitDirectoryPaths.count - 1);
        nextSelection = _gitDirectoryPaths[nextIndex];
    }
    _gitObservedDirectory = nil;
    _gitDirectoryManuallySelected = nextSelection.length > 0;
    [self reloadGitDirectoryPickerSelecting:nextSelection];

    if (_gitDirectoryPaths.count == 0 && !_gitReviewShowsTranscriptEdits) {
        _gitDiffGeneration++;
        [self replaceGitReviewDocument:[self gitReviewDocumentForSnapshot:@{
            @"error": PTL(@"尚未选择 Git 观察目录。", @"No Git observation directory is selected.")
        }] animated:_gitDiffExpanded];
        _gitDiffRefreshButton.enabled = NO;
    } else if (_gitDiffExpanded && !_gitReviewShowsTranscriptEdits) {
        [self refreshGitDiff:nil];
    }
    _statusLabel.stringValue = [NSString stringWithFormat:
        PTL(@"已从 PrettyTerm 记忆中删除 %@", @"Removed %@ from PrettyTerm memory"), path.lastPathComponent ?: path];
    _bottomStatusLabel.stringValue = PTL(
        @"已持续排除此目录 · 仅手动重新添加可恢复 · Claude Code 目录未改变",
        @"Directory stays excluded · add it manually to restore · Claude Code is unchanged");
}

- (void)buildGitActionPopoverIfNeeded {
    if (_gitActionPopover) return;
    _gitActionPopover = [[NSPopover alloc] init];
    _gitActionPopover.behavior = NSPopoverBehaviorTransient;
    _gitActionPopover.contentSize = NSMakeSize(360, 300);

    NSViewController *controller = [[NSViewController alloc] init];
    PTAppearanceSurfaceView *surface = [[PTAppearanceSurfaceView alloc]
        initWithFrame:NSMakeRect(0, 0, 360, 300)];
    surface.surfaceStyle = PTAppearanceSurfaceStyleCard;
    controller.view = surface;
    _gitActionPopover.contentViewController = controller;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    [surface addSubview:stack];

    _gitActionBranchLabel = [self label:PTL(@"⌘ 读取当前分支…", @"⌘ Reading current branch…") size:13
        weight:NSFontWeightSemibold color:NSColor.labelColor];
    [stack addArrangedSubview:_gitActionBranchLabel];

    _gitCommitMessageField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _gitCommitMessageField.translatesAutoresizingMaskIntoConstraints = NO;
    _gitCommitMessageField.placeholderString = PTL(@"提交信息", @"Commit message");
    _gitCommitMessageField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    _gitCommitMessageField.delegate = self;
    [stack addArrangedSubview:_gitCommitMessageField];

    _gitIncludeUnstagedButton = [[PTWarmToggleButton alloc] initWithFrame:NSZeroRect];
    _gitIncludeUnstagedButton.translatesAutoresizingMaskIntoConstraints = NO;
    _gitIncludeUnstagedButton.state = NSControlStateValueOn;
    _gitIncludeUnstagedButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    _gitIncludeUnstagedButton.contentTintColor = PTWarmAccentColor();
    NSStackView *unstagedRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    unstagedRow.translatesAutoresizingMaskIntoConstraints = NO;
    unstagedRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    unstagedRow.alignment = NSLayoutAttributeCenterY;
    unstagedRow.spacing = 5;
    NSTextField *unstagedLabel = [self label:PTL(@"包含未暂存的更改", @"Include unstaged changes") size:11.5
        weight:NSFontWeightMedium color:NSColor.labelColor];
    [unstagedRow addArrangedSubview:_gitIncludeUnstagedButton];
    [unstagedRow addArrangedSubview:unstagedLabel];
    [_gitIncludeUnstagedButton.widthAnchor constraintEqualToConstant:24].active = YES;
    [_gitIncludeUnstagedButton.heightAnchor constraintEqualToConstant:24].active = YES;
    [stack addArrangedSubview:unstagedRow];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];

    _gitCommitButton = PTWarmButton(PTL(@"提交", @"Commit"), self, @selector(commitGitChanges:));
    _gitCommitAndPushButton = PTWarmButton(PTL(@"提交并推送", @"Commit and Push"),
        self, @selector(commitAndPushGitChanges:));
    _gitPushButton = PTWarmButton(PTL(@"推送", @"Push"), self, @selector(pushGitChanges:));
    for (NSButton *button in @[_gitCommitButton, _gitCommitAndPushButton, _gitPushButton]) {
        button.alignment = NSTextAlignmentLeft;
        button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        button.contentTintColor = PTWarmAccentColor();
        [stack addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    _gitCommitButton.toolTip = PTL(@"只提交暂存区；勾选后会先暂存仓库内全部改动", @"Commit staged changes only; when checked, all repository changes are staged first");
    _gitCommitAndPushButton.toolTip = PTL(@"提交成功后再执行 git push", @"Run git push after a successful commit");
    _gitPushButton.toolTip = PTL(@"推送已有提交", @"Push existing commits");

    NSStackView *statusRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    statusRow.translatesAutoresizingMaskIntoConstraints = NO;
    statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusRow.alignment = NSLayoutAttributeCenterY;
    statusRow.spacing = 7;
    _gitActionProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _gitActionProgress.translatesAutoresizingMaskIntoConstraints = NO;
    _gitActionProgress.style = NSProgressIndicatorStyleSpinning;
    _gitActionProgress.controlSize = NSControlSizeSmall;
    _gitActionProgress.displayedWhenStopped = NO;
    _gitActionProgress.hidden = YES;
    _gitActionStatusLabel = [self label:PTL(@"填写提交信息后可提交", @"Enter a commit message to commit") size:10
        weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    _gitActionStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [statusRow addArrangedSubview:_gitActionProgress];
    [statusRow addArrangedSubview:_gitActionStatusLabel];
    [stack addArrangedSubview:statusRow];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:surface.topAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-18],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:surface.bottomAnchor constant:-14],
        [_gitCommitMessageField.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_gitActionProgress.widthAnchor constraintEqualToConstant:14],
        [_gitActionProgress.heightAnchor constraintEqualToConstant:14],
        [_gitActionStatusLabel.widthAnchor constraintLessThanOrEqualToConstant:300]
    ]];
}

- (void)updateGitActionControls {
    NSString *message = [_gitCommitMessageField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL canCommit = !_gitActionInFlight && _gitObservedDirectory.length > 0 && message.length > 0;
    _gitCommitButton.enabled = canCommit;
    _gitCommitAndPushButton.enabled = canCommit;
    _gitPushButton.enabled = !_gitActionInFlight && _gitObservedDirectory.length > 0;
    _gitCommitMessageField.enabled = !_gitActionInFlight;
    _gitIncludeUnstagedButton.enabled = !_gitActionInFlight;
    _gitPublishButton.enabled = !_gitActionInFlight && _gitObservedDirectory.length > 0;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _gitCommitMessageField) [self updateGitActionControls];
}

- (void)showGitActions:(id)sender {
    if (_gitObservedDirectory.length == 0) {
        _statusLabel.stringValue = PTL(@"请先选择 Git 观察目录", @"Select a Git observation directory first");
        return;
    }
    [self buildGitActionPopoverIfNeeded];
    _gitActionStatusLabel.stringValue = PTL(@"填写提交信息后可提交", @"Enter a commit message to commit");
    [self updateGitActionControls];
    [_gitActionPopover showRelativeToRect:[sender bounds]
                                   ofView:sender
                            preferredEdge:NSRectEdgeMaxY];
    [_gitCommitMessageField.window makeFirstResponder:_gitCommitMessageField];

    NSString *directory = [_gitObservedDirectory copy];
    _gitActionBranchLabel.stringValue = PTL(@"⌘ 读取当前分支…", @"⌘ Reading current branch…");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int status = 0;
        NSString *branch = [[PTRunGit(directory, @[@"branch", @"--show-current"], &status)
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![directory isEqual:self->_gitObservedDirectory]) return;
            self->_gitActionBranchLabel.stringValue = status == 0 && branch.length > 0
                ? [NSString stringWithFormat:@"⌘  %@", branch]
                : @"⌘  detached HEAD";
        });
    });
}

- (void)performGitCommit:(BOOL)commit push:(BOOL)push {
    if (_gitActionInFlight || _gitObservedDirectory.length == 0) return;
    NSString *message = [_gitCommitMessageField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (commit && message.length == 0) {
        _gitActionStatusLabel.stringValue = PTL(@"提交信息为空", @"Commit message is empty");
        return;
    }

    NSString *directory = [_gitObservedDirectory copy];
    BOOL includeUnstaged = _gitIncludeUnstagedButton.state == NSControlStateValueOn;
    _gitActionInFlight = YES;
    _gitActionStatusLabel.stringValue = commit
        ? PTL(@"正在提交…", @"Committing…") : PTL(@"正在推送…", @"Pushing…");
    _gitActionProgress.hidden = NO;
    [_gitActionProgress startAnimation:nil];
    [self updateGitActionControls];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int status = 0;
        NSString *root = [[PTRunGit(directory, @[@"rev-parse", @"--show-toplevel"], &status)
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
        NSMutableArray<NSString *> *outputs = [NSMutableArray array];
        if (status != 0 && root.length) [outputs addObject:root];
        if (status == 0 && commit && includeUnstaged) {
            NSString *output = PTRunGit(root, @[@"add", @"-A", @"--", @"."], &status);
            if (output.length) [outputs addObject:output];
        }
        if (status == 0 && commit) {
            NSString *output = PTRunGit(root, @[@"commit", @"-m", message], &status);
            if (output.length) [outputs addObject:output];
        }
        if (status == 0 && push) {
            NSString *output = PTRunGit(root, @[@"push"], &status);
            if (output.length) [outputs addObject:output];
        }
        NSString *combined = [[outputs componentsJoinedByString:@"\n"]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (combined.length > 360) {
            NSRange tailRange = [combined rangeOfComposedCharacterSequencesForRange:
                NSMakeRange(combined.length - 360, 360)];
            combined = [[combined substringWithRange:tailRange]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
        NSString *success = commit && push
            ? PTL(@"提交并推送完成", @"Commit and push completed")
            : (commit ? PTL(@"提交完成", @"Commit completed") : PTL(@"推送完成", @"Push completed"));
        NSString *result = status == 0 ? success
            : (combined.length ? combined : PTL(@"Git 操作失败", @"Git operation failed"));
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_gitActionInFlight = NO;
            [self->_gitActionProgress stopAnimation:nil];
            self->_gitActionProgress.hidden = YES;
            self->_gitActionStatusLabel.stringValue = result;
            self->_gitActionStatusLabel.toolTip = combined;
            if (status == 0 && commit) self->_gitCommitMessageField.stringValue = @"";
            [self updateGitActionControls];
            self->_statusLabel.stringValue = result;
            self->_bottomStatusLabel.stringValue = result;
            if (self->_gitDiffExpanded && !self->_gitReviewShowsTranscriptEdits) {
                [self refreshGitDiff:nil];
            }
        });
    });
}

- (void)commitGitChanges:(id)sender {
    (void)sender;
    [self performGitCommit:YES push:NO];
}

- (void)commitAndPushGitChanges:(id)sender {
    (void)sender;
    [self performGitCommit:YES push:YES];
}

- (void)pushGitChanges:(id)sender {
    (void)sender;
    [self performGitCommit:NO push:YES];
}

- (void)toggleGitDiff:(id)sender {
    (void)sender;
    if (!_gitDiffExpanded && _gitObservedDirectory.length == 0) {
        _statusLabel.stringValue = PTL(@"请先选择或添加 Git 观察目录", @"Select or add a Git observation directory first");
        return;
    }
    if (_gitDiffExpanded) {
        [self closeToolWorkspace:nil];
        return;
    }
    _gitDiffExpanded = YES;
    _reviewToolPageOpen = YES;
    _gitReviewShowsTranscriptEdits = NO;
    _transcriptEditReviewEvents = nil;
    _gitDiffToggleButton.title = PTL(@"关闭 Git 审查  ‹", @"Close Git Review  ‹");
    _gitDiffRefreshButton.hidden = NO;
    [self showToolPageKind:@"review" animated:YES];
    [self setToolWorkspaceExpanded:YES animated:YES];
    [self rebuildToolTabBar];
    [self refreshGitDiff:nil];
}

- (NSAttributedString *)transcriptEditReviewDocumentForEvents:
    (NSArray<NSDictionary *> *)events {
    __block NSAttributedString *document = nil;
    [_gitDiffTextView.effectiveAppearance performAsCurrentDrawingAppearance:^{
        document = PTTranscriptEditReviewAttributedString(events ?: @[]);
    }];
    return document ?: [[NSAttributedString alloc] initWithString:@""];
}

- (void)showTranscriptEditReviewWithEvents:(NSArray<NSDictionary *> *)events {
    _gitDiffGeneration++;
    [_gitDiffProgress stopAnimation:nil];
    _gitDiffProgress.hidden = YES;
    _gitDiffRefreshButton.hidden = YES;
    _gitReviewShowsTranscriptEdits = YES;
    _transcriptEditReviewEvents = [events copy];
    _gitDiffExpanded = YES;
    _reviewToolPageOpen = YES;
    _gitDiffToggleButton.title = PTL(@"关闭本轮审查  ‹", @"Close Turn Review  ‹");
    [self showToolPageKind:@"review" animated:YES];
    [self setToolWorkspaceExpanded:YES animated:YES];
    [self rebuildToolTabBar];
    [self replaceGitReviewDocument:[self transcriptEditReviewDocumentForEvents:events]
                          animated:YES];
}

- (NSAttributedString *)gitReviewDocumentForSnapshot:
    (NSDictionary<NSString *, NSString *> *)snapshot {
    __block NSAttributedString *document = nil;
    [_gitDiffTextView.effectiveAppearance performAsCurrentDrawingAppearance:^{
        document = PTGitReviewAttributedString(snapshot);
    }];
    return document ?: [[NSAttributedString alloc] initWithString:@""];
}

- (void)replaceGitReviewDocument:(NSAttributedString *)document animated:(BOOL)animated {
    if (!document) return;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (!animated || reduceMotion || _gitDiffScroll.hidden) {
        [_gitDiffTextView.textStorage setAttributedString:document];
        _gitDiffTextView.alphaValue = 1.0;
        [_gitDiffTextView scrollRangeToVisible:NSMakeRange(0, 0)];
        return;
    }
    _gitDiffTextView.wantsLayer = YES;
    CATransition *transition = [CATransition animation];
    transition.type = kCATransitionFade;
    transition.duration = 0.22;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:
        kCAMediaTimingFunctionEaseInEaseOut];
    [_gitDiffTextView.layer addAnimation:transition forKey:@"replace-review-document"];
    [_gitDiffTextView.textStorage setAttributedString:document];
    [_gitDiffTextView scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)refreshGitDiff:(id)sender {
    (void)sender;
    NSString *directory = [_gitObservedDirectory copy];
    if (directory.length == 0) return;
    _gitReviewShowsTranscriptEdits = NO;
    _transcriptEditReviewEvents = nil;
    _gitDiffToggleButton.title = PTL(@"关闭 Git 审查  ‹", @"Close Git Review  ‹");
    NSUInteger generation = ++_gitDiffGeneration;
    _gitDiffRefreshButton.enabled = NO;
    _gitDiffProgress.hidden = NO;
    [_gitDiffProgress startAnimation:nil];
    if (_gitDiffTextView.string.length == 0 ||
        [_gitDiffTextView.string containsString:@"选择目录后"]) {
        [self replaceGitReviewDocument:PTGitReviewLoadingAttributedString() animated:NO];
    } else if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _gitDiffTextView.animator.alphaValue = 0.58;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary<NSString *, NSString *> *snapshot =
            PTGitReviewSnapshotForDirectory(directory);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_gitDiffGeneration ||
                ![directory isEqual:self->_gitObservedDirectory]) return;
            [self->_gitDiffProgress stopAnimation:nil];
            self->_gitDiffProgress.hidden = YES;
            self->_gitDiffRefreshButton.enabled = YES;
            [self replaceGitReviewDocument:[self gitReviewDocumentForSnapshot:snapshot]
                                  animated:YES];
        });
    });
}

- (NSArray<NSDictionary *> *)existingChangedFilesFromFiles:(NSArray<NSDictionary *> *)files {
    NSMutableArray<NSDictionary *> *existing = [NSMutableArray arrayWithCapacity:files.count];
    for (NSDictionary *file in files) {
        NSString *path = [file[@"filePath"] isKindOfClass:NSString.class] ? file[@"filePath"] : @"";
        BOOL directory = NO;
        if (path.length == 0 || ![path hasPrefix:@"/"] ||
            ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] || directory) {
            continue;
        }
        [existing addObject:file];
    }
    return existing;
}

- (void)showEmptyChangedFilesState {
    for (NSView *view in _changedFilesStack.arrangedSubviews.copy) {
        [_changedFilesStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    _changedFileButtonsByPath = @{};
    NSTextField *empty = [self label:PTL(@"本轮没有 Edit / Write 改动", @"No Edit / Write changes in this turn")
        size:10.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
    [_changedFilesStack addArrangedSubview:empty];
}

- (void)updateInspectorForSession:(PTSessionInfo *)session {
    if (!session) return;
    [self rememberGitDirectoriesForSession:session];
    BOOL hasContextUsage = session.contextUsed > 0 && session.contextWindow > 0;
    double contextRatio = hasContextUsage
        ? MIN(1.0, (double)session.contextUsed / (double)session.contextWindow) : 0;
    _inspectorContextLabel.stringValue = hasContextUsage
        ? [NSString stringWithFormat:@"%@ / %@ tokens",
            PTCompactTokenCount(session.contextUsed), PTCompactTokenCount(session.contextWindow)]
        : PTL(@"暂无 usage 数据", @"No usage data yet");
    _inspectorContextPercentLabel.stringValue = hasContextUsage
        ? [NSString stringWithFormat:(contextRatio * 100.0 < 10.0 ? @"%.1f%%" : @"%.0f%%"),
            contextRatio * 100.0]
        : @"—";
    _inspectorContextMeter.progress = contextRatio;
    _inspectorContextMeter.fillColor = PTWarmAccentColor();

    NSArray<NSDictionary *> *contextBreakdown = session.contextBreakdown ?: @[];
    // 总 usage 在普通 assistant 记录里就有，而分类只在 Claude Code 自己已写入
    // /context 记录时可用。详情始终可点，但绝不为此向 Terminal 发送命令。
    _contextDisclosureButton.enabled = YES;
    if (![_renderedContextBreakdown isEqualToArray:contextBreakdown]) {
        _renderedContextBreakdown = [contextBreakdown copy];
        [self rebuildContextBreakdownRows:contextBreakdown];
    }
    _inspectorContextDetailStack.hidden = !_contextDetailExpanded || contextBreakdown.count == 0;
    [self updateUsageDisplays];

    NSArray<NSDictionary *> *changedFiles = [self existingChangedFilesFromFiles:session.changedFiles ?: @[]];
    if (![_renderedChangedFiles isEqualToArray:changedFiles]) {
        _renderedChangedFiles = [changedFiles copy];
        if (changedFiles.count == 0) {
            [self showEmptyChangedFilesState];
        } else {
            // 路径相同的按钮永不因 added/removed 数字变化而拆除；只更新其内容。
            // 这样 transcript 轮询恰好撞上 mouseDown/mouseUp 时，action 仍属于同一对象。
            for (NSView *view in _changedFilesStack.arrangedSubviews.copy) {
                if (![view isKindOfClass:PTFirstMouseButton.class]) {
                    [_changedFilesStack removeArrangedSubview:view];
                    [view removeFromSuperview];
                }
            }
            NSMutableDictionary<NSString *, PTAnimatedButton *> *nextButtons =
                [NSMutableDictionary dictionary];
            NSUInteger fileIndex = 0;
            for (NSDictionary *file in changedFiles) {
                NSString *path = [file[@"filePath"] isKindOfClass:NSString.class]
                    ? file[@"filePath"] : @"";
                NSString *identity = path.length > 0 ? path : [NSString stringWithFormat:@"missing-path-%lu",
                    (unsigned long)fileIndex];
                PTAnimatedButton *button = _changedFileButtonsByPath[identity];
                if (!button) {
                    button = PTWarmButton(@"", self, @selector(revealChangedFile:));
                    button.buttonType = NSButtonTypeMomentaryPushIn;
                    button.alignment = NSTextAlignmentCenter;
                    button.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
                    button.fillColor = PTWarmChipColor();
                    button.hoverFillColor = PTWarmBorderColor();
                    button.cornerRadius = 8;
                    [_changedFilesStack addArrangedSubview:button];
                }
                NSString *title = [NSString stringWithFormat:@"%@    +%@  −%@  ↗",
                    file[@"displayName"] ?: @"文件", file[@"added"] ?: @0, file[@"removed"] ?: @0];
                button.title = title;
                button.toolTip = [NSString stringWithFormat:@"在 Finder 中显示\n%@", path];
                button.identifier = path;
                nextButtons[identity] = button;
                fileIndex++;
            }
            for (NSString *identity in _changedFileButtonsByPath) {
                if (nextButtons[identity]) continue;
                PTAnimatedButton *button = _changedFileButtonsByPath[identity];
                [_changedFilesStack removeArrangedSubview:button];
                [button removeFromSuperview];
            }
            _changedFileButtonsByPath = nextButtons;
        }
        [self applyAdaptiveInspectorWidth];
    }

    // 任务也按值更新，使 transcript 修订只重建发生变化的检查器内容。
    NSArray<NSDictionary *> *tasks = session.tasks ?: @[];
    if (![_renderedTasks isEqualToArray:tasks]) {
        _renderedTasks = [tasks copy];
        for (NSView *view in _tasksStack.arrangedSubviews.copy) {
            [_tasksStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }
        if (tasks.count == 0) {
            NSTextField *empty = [self label:PTL(@"当前会话没有任务", @"No tasks in this conversation") size:10.5 weight:NSFontWeightRegular color:NSColor.tertiaryLabelColor];
            [_tasksStack addArrangedSubview:empty];
        } else {
            for (NSDictionary *task in tasks) {
                NSString *status = [task[@"status"] isKindOfClass:NSString.class] ? task[@"status"] : @"pending";
                NSString *statusEmoji = @"⚪️";
                NSColor *statusColor = NSColor.secondaryLabelColor;
                if ([status isEqual:@"in_progress"]) {
                    statusEmoji = @"🔵";
                    statusColor = PTColor(0.0, 0.48, 0.99);
                } else if ([status isEqual:@"completed"]) {
                    statusEmoji = @"✅";
                    statusColor = PTColor(0.20, 0.78, 0.35);
                }
                NSString *taskID = [task[@"id"] isKindOfClass:NSString.class] ? task[@"id"] : @"?";
                NSString *subject = [task[@"subject"] isKindOfClass:NSString.class] ? task[@"subject"] : @"未命名任务";
                NSString *title = [NSString stringWithFormat:@"%@ #%@ %@", statusEmoji, taskID, subject];
                NSTextField *label = [self label:title size:10.5 weight:NSFontWeightMedium color:statusColor];
                label.lineBreakMode = NSLineBreakByTruncatingTail;
                [_tasksStack addArrangedSubview:label];
                [label.widthAnchor constraintEqualToAnchor:_tasksStack.widthAnchor].active = YES;
            }
        }
    }
}

- (void)toggleInspector:(id)sender {
    (void)sender;
    if (!_toolWorkspaceView.hidden && _toolWorkspaceWidthConstraint.constant > 0) {
        _restoreInspectorAfterTools = YES;
        [self setToolWorkspaceExpanded:NO animated:YES];
        return;
    }
    [self setInspectorExpanded:!_inspectorExpanded animated:YES];
}

- (void)toggleSidePanel:(id)sender {
    (void)sender;
    if (!_toolWorkspaceView.hidden && _toolWorkspaceWidthConstraint.constant > 0) {
        [self setToolWorkspaceExpanded:NO animated:YES];
    } else if (_reviewToolPageOpen || _fileToolPageOpen) {
        [self setToolWorkspaceExpanded:YES animated:YES];
    } else {
        [self openFileWorkspace:nil];
    }
}

- (void)toggleContextDetail:(id)sender {
    (void)sender;
    _contextDetailExpanded = !_contextDetailExpanded;
    _inspectorContextDetailStack.hidden = !_contextDetailExpanded;
    _contextDisclosureButton.title = _contextDetailExpanded
        ? PTL(@"详情 ⌄", @"Details ⌄") : PTL(@"详情 ›", @"Details ›");
    if (!_contextDetailExpanded || _selectedSession.contextBreakdown.count > 0) return;

    [self rebuildContextBreakdownRows:@[]];
    _statusLabel.stringValue = PTL(@"当前暂无已记录的上下文分类 · 未向 Terminal 发送命令",
                                   @"No recorded context categories yet · no Terminal command was sent");
}

- (void)toggleCostDetail:(id)sender {
    (void)sender;
    _costDetailExpanded = !_costDetailExpanded;
    _inspectorCostDetailStack.hidden = !_costDetailExpanded;
    _costDisclosureButton.title = _costDetailExpanded
        ? PTL(@"详情 ⌄", @"Details ⌄") : PTL(@"详情 ›", @"Details ›");
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

- (void)openTranscriptEditReviewForSessionID:(NSString *)sessionID
                                    turnIndex:(NSUInteger)turnIndex {
    if (sessionID.length == 0) return;
    if (![_selectedSession.sessionID isEqual:sessionID]) {
        PTSessionInfo *matchingSession = nil;
        for (PTSessionInfo *session in _sessions) {
            if ([session.sessionID isEqual:sessionID]) {
                matchingSession = session;
                break;
            }
        }
        if (!matchingSession) return;
        NSString *projectKey = PTSessionProjectKey(matchingSession);
        [self loadCollapsedSessionProjectsIfNeeded];
        if ([_collapsedSessionProjectPaths containsObject:projectKey]) {
            [_collapsedSessionProjectPaths removeObject:projectKey];
            [self persistCollapsedSessionProjects];
            [self rebuildSessionSidebarRows];
            [_sessionTable reloadData];
        }
        NSInteger matchingRow = [self sidebarRowForSessionID:sessionID];
        if (matchingRow == NSNotFound) return;
        [_sessionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:matchingRow]
                     byExtendingSelection:NO];
        _selectedSession = matchingSession;
        [self showSelectedSession];
    }

    NSArray<NSDictionary *> *events = [self transcriptEditEventsForSession:_selectedSession
                                                                  turnIndex:turnIndex];
    if (events.count == 0) {
        _statusLabel.stringValue = PTL(@"这个回合没有可审阅的 Edit / Write 记录", @"This turn has no recorded Edit / Write changes to review");
        return;
    }

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self showTranscriptEditReviewWithEvents:events];
    _statusLabel.stringValue = PTL(@"正在显示本轮已记录的本地修改 · 未执行 git diff", @"Showing recorded local changes for this turn · git diff was not run");
}

- (void)revealChangedFile:(NSButton *)sender {
    NSString *path = [sender.identifier isKindOfClass:NSString.class] ? sender.identifier : @"";
    BOOL directory = NO;
    BOOL exists = path.length > 0 &&
        [path hasPrefix:@"/"] &&
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory];
    if (!exists || directory) {
        [_changedFilesStack removeArrangedSubview:sender];
        [sender removeFromSuperview];
        NSMutableDictionary<NSString *, PTAnimatedButton *> *buttons =
            [_changedFileButtonsByPath mutableCopy] ?: [NSMutableDictionary dictionary];
        [buttons removeObjectForKey:path];
        _changedFileButtonsByPath = buttons;
        _renderedChangedFiles = [self existingChangedFilesFromFiles:_renderedChangedFiles ?: @[]];
        if (_changedFileButtonsByPath.count == 0) [self showEmptyChangedFilesState];
        return;
    }
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
    _statusLabel.stringValue = [NSString stringWithFormat:PTL(@"已在 Finder 中显示 %@", @"Revealed %@ in Finder"), path.lastPathComponent];
}

- (void)updateContextAndModelForSession:(PTSessionInfo *)session {
    if (!session) return;
    NSString *liveModel = [self bridgeForSessionID:session.sessionID].currentModel;
    if (liveModel.length) session.model = liveModel;
    NSString *liveEffort = [self bridgeForSessionID:session.sessionID].currentEffort;
    if (liveEffort.length) session.effort = liveEffort;
    NSNumber *liveContext = [self bridgeForSessionID:session.sessionID].contextTokens;
    if (liveContext) session.contextUsed = liveContext.unsignedIntegerValue;

    NSUInteger window = session.contextWindow;
    NSUInteger used = session.contextUsed;
    if (used > 0 && window > 0) {
        double ratio = MIN(1.0, (double)used / (double)window);
        _contextBar.doubleValue = ratio;
        _contextLabel.stringValue = [NSString stringWithFormat:@"ctx %.0f%% · %@/%@",
            ratio * 100.0, PTCompactTokenCount(used), PTCompactTokenCount(window)];
        _contextBar.toolTip = [NSString stringWithFormat:@"最近一次调用占用 %lu / %lu tokens",
            (unsigned long)used, (unsigned long)window];
    } else {
        _contextBar.doubleValue = 0;
        _contextLabel.stringValue = @"ctx —";
        _contextBar.toolTip = @"该会话尚无 usage 数据";
    }

    NSInteger selectedIndex = 0;
    for (NSInteger index = 1; index < _modelPicker.numberOfItems; index++) {
        if ([[_modelPicker itemAtIndex:index].representedObject isEqual:session.model]) {
            selectedIndex = index;
            break;
        }
    }
    [_modelPicker selectItemAtIndex:selectedIndex];
    _modelPicker.itemArray.firstObject.title = session.model.length
        ? [NSString stringWithFormat:PTL(@"当前 · %@", @"Current · %@"), session.model]
        : PTL(@"当前模型", @"Current model");
    [self updateComposerConfigurationButtons];
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
        if (self->_bridge.currentModel.length) return;
        if (self->_selectedSession && self->_bridge.running &&
            [self->_bridge.sessionID isEqual:self->_selectedSession.sessionID]) {
            self->_selectedSession.model = model;
            [self updateContextAndModelForSession:self->_selectedSession];
            self->_statusLabel.stringValue = [NSString stringWithFormat:PTL(@"检测到模型切换：%@", @"Model switch detected: %@"), model];
        }
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

- (void)loadCollapsedSessionProjectsIfNeeded {
    if (_collapsedSessionProjectPaths) return;
    NSArray<NSString *> *stored = [NSUserDefaults.standardUserDefaults
        stringArrayForKey:PTSessionProjectCollapsedDefaultsKey];
    _collapsedSessionProjectPaths = [NSMutableSet setWithArray:stored ?: @[]];
}

- (void)persistCollapsedSessionProjects {
    NSArray<NSString *> *paths = [_collapsedSessionProjectPaths.allObjects
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    [NSUserDefaults.standardUserDefaults setObject:paths
                                            forKey:PTSessionProjectCollapsedDefaultsKey];
}

- (void)rebuildSessionSidebarRows {
    [self loadCollapsedSessionProjectsIfNeeded];
    NSMutableOrderedSet<NSString *> *projectOrder = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, NSMutableArray<PTSessionInfo *> *> *grouped =
        [NSMutableDictionary dictionary];
    for (PTSessionInfo *session in _sessions ?: @[]) {
        NSString *projectKey = PTSessionProjectKey(session);
        NSMutableArray<PTSessionInfo *> *projectSessions = grouped[projectKey];
        if (!projectSessions) {
            projectSessions = [NSMutableArray array];
            grouped[projectKey] = projectSessions;
            [projectOrder addObject:projectKey];
        }
        [projectSessions addObject:session];
    }

    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSString *projectKey in projectOrder) {
        NSArray<PTSessionInfo *> *projectSessions = grouped[projectKey];
        BOOL collapsed = [_collapsedSessionProjectPaths containsObject:projectKey];
        [rows addObject:@{
            @"kind": @"project",
            @"projectKey": projectKey,
            @"title": PTSessionProjectTitle(projectKey),
            @"sessionCount": @(projectSessions.count),
            @"collapsed": @(collapsed)
        }];
        if (collapsed) continue;
        for (PTSessionInfo *session in projectSessions) {
            [rows addObject:@{
                @"kind": @"session",
                @"projectKey": projectKey,
                @"session": session
            }];
        }
    }
    _sessionSidebarRows = rows;
}

- (PTSessionInfo *)sessionForSidebarRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_sessionSidebarRows.count) return nil;
    NSDictionary *item = _sessionSidebarRows[row];
    return [item[@"kind"] isEqual:@"session"] ? item[@"session"] : nil;
}

- (NSInteger)sidebarRowForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return NSNotFound;
    for (NSInteger row = 0; row < (NSInteger)_sessionSidebarRows.count; row++) {
        PTSessionInfo *session = [self sessionForSidebarRow:row];
        if ([session.sessionID isEqual:sessionID]) return row;
    }
    return NSNotFound;
}

- (void)toggleSessionProject:(NSButton *)sender {
    NSString *projectKey = [sender.identifier isKindOfClass:NSString.class]
        ? sender.identifier : @"";
    if (projectKey.length == 0) return;
    [self loadCollapsedSessionProjectsIfNeeded];
    if ([_collapsedSessionProjectPaths containsObject:projectKey]) {
        [_collapsedSessionProjectPaths removeObject:projectKey];
    } else {
        [_collapsedSessionProjectPaths addObject:projectKey];
    }
    [self persistCollapsedSessionProjects];
    NSString *selectedID = _activeWorkspaceTab.sessionID.length
        ? _activeWorkspaceTab.sessionID : _selectedSession.sessionID;
    [self rebuildSessionSidebarRows];
    [_sessionTable reloadData];
    NSInteger selectedRow = [self sidebarRowForSessionID:selectedID];
    if (selectedRow == NSNotFound) {
        [_sessionTable deselectAll:nil];
    } else {
        [_sessionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow]
                     byExtendingSelection:NO];
    }
    for (NSInteger row = 0; row < (NSInteger)_sessionSidebarRows.count; row++) {
        NSDictionary *item = _sessionSidebarRows[row];
        if ([item[@"kind"] isEqual:@"project"] &&
            [item[@"projectKey"] isEqual:projectKey]) {
            [_sessionTable scrollRowToVisible:row];
            break;
        }
    }
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

    _applyingSessions = YES;
    NSString *selectedID = _selectedSession.sessionID;
    _sessions = sessions;
    [self rebuildSessionSidebarRows];
    [_sessionTable reloadData];

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
        NSInteger selectedRow = [self sidebarRowForSessionID:_selectedSession.sessionID];
        if (selectedRow == NSNotFound) {
            [_sessionTable deselectAll:nil];
        } else {
        [_sessionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
        }
        if (manualRefresh && [_manualRefreshSessionID isEqual:_selectedSession.sessionID]) {
            _renderedSessionID = nil;
            _renderedModifiedAt = nil;
            _renderedMessageCount = 0;
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
    }
    [self refreshFloatingConversation];
    [self updateFloatingControls];
    [self updateWorkspaceTabBar];
    _manualRefreshSessionID = nil;
    if (!_bridge.running) {
        _statusLabel.stringValue = [NSString stringWithFormat:PTL(@"已发现 %lu 个本地会话", @"Found %lu local conversations"), (unsigned long)sessions.count];
    }
    _applyingSessions = NO;
    [self updateHomeProjects];
    [self finishHomeSessionIfAvailable];
}

- (void)syncFullSessionIDs {
    if (!_store) return;
    NSMutableSet<NSString *> *sessionIDs = [NSMutableSet set];
    for (PTWorkspaceTab *tab in _workspaceTabs) {
        if (tab.sessionID.length) [sessionIDs addObject:tab.sessionID];
    }
    if (_floatingPanel.visible && _floatingSessionID.length)
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
    [self updateContextAndModelForSession:_selectedSession];
    _conversationTitle.stringValue = _selectedSession.title ?: PTL(@"未命名会话", @"Untitled conversation");
    NSString *folder = _selectedSession.cwd.lastPathComponent.length ? _selectedSession.cwd.lastPathComponent : _selectedSession.cwd;
    NSString *model = _selectedSession.model.length ? _selectedSession.model : @"Claude";
    _conversationDetail.stringValue = [NSString stringWithFormat:PTL(@"%@ · %@ · %lu 轮对话", @"%@ · %@ · %lu turns"),
        folder.length ? folder : PTL(@"未知目录", @"Unknown directory"), model,
        (unsigned long)PTSessionTurnCount(_selectedSession)];
    _connectButton.enabled = YES;
    [self updateInspectorForSession:_selectedSession];
    [self refreshAgentStateAndControls];
    [self renderSession:_selectedSession];
    [self updateFloatingControls];
    [self updateWorkspaceTabBar];
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
    if (!_webReady || !session) return;
    PTClaudeBridge *streamBridge = [self bridgeForSessionID:session.sessionID];
    [streamBridge reconcileStreamWithMessages:session.assistantMessages];
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

    BOOL canAppend = [_renderedSessionID isEqual:session.sessionID] &&
        _renderedModifiedAt != nil && _renderedMessageCount < messageCount;

    // 追加渲染时不再序列化整份历史消息：app.js 的 appendClaudeMessages 收到
    // 后第一件事就是 delete metadata.messages，只用元数据 + 增量那几条。
    // 真实 7.7MB transcript 上，全量 payload 每次要在主线程生成 3.6MB 脚本
    // （约 17ms，还不含 WebView 解析这 3.6MB 源码的开销），而只传元数据是 10KB。
    NSMutableDictionary *payload = [@{
        @"sessionId": session.sessionID ?: @"",
        @"title": session.title ?: @"未命名会话",
        @"cwd": session.cwd ?: @"",
        @"model": session.model ?: @"Claude",
        @"interfaceLanguage": PTInterfaceLanguageCode(),
        @"awaitingReply": @(_awaitingClaudeBaselineBySessionID[session.sessionID] != nil)
    } mutableCopy];
    payload[@"questionUpdates"] = PTQuestionUpdates(session.assistantMessages);
    if (!canAppend) payload[@"messages"] = session.assistantMessages ?: @[];

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!jsonData) return;
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (!json) return;

    NSString *script = nil;
    if (canAppend) {
        NSArray *incoming = [session.assistantMessages subarrayWithRange:
            NSMakeRange(_renderedMessageCount, messageCount - _renderedMessageCount)];
        NSData *incomingData = [NSJSONSerialization dataWithJSONObject:incoming options:0 error:nil];
        NSString *incomingJSON = incomingData
            ? [[NSString alloc] initWithData:incomingData encoding:NSUTF8StringEncoding] : nil;
        if (incomingJSON) {
            // 元数据里没有 messages，先核对 JS 仍持有同一个会话。
            script = [NSString stringWithFormat:
                @"(function(){var m=%@;"
                 "if(!window.__ptSessionMatches||!window.__ptSessionMatches(m))return 0;"
                 "window.appendClaudeMessages(m,%@);return 1;})()",
                json, incomingJSON];
        }
    }
    if (!script) script = [NSString stringWithFormat:@"window.setClaudeSession(%@); null;", json];

    _renderInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [_conversationView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        PTAppDelegate *self = weakSelf;
        if (!self) return;
        self->_renderInFlight = NO;
        BOOL appendRejected = canAppend && [result isKindOfClass:NSNumber.class] &&
            ![(NSNumber *)result boolValue];
        if (error || appendRejected) {
            self->_statusLabel.stringValue = PTL(@"显示更新失败", @"Display update failed");
        } else {
            self->_renderedSessionID = session.sessionID;
            self->_renderedMessageCount = messageCount;
            self->_renderedModifiedAt = session.modifiedAt;
            [self presentClaudeStreamForBridge:streamBridge];
        }

        PTSessionInfo *pending = self->_pendingRenderSession;
        self->_pendingRenderSession = nil;
        if (pending) [self renderSession:pending];
    }];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return _sessionSidebarRows.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    NSDictionary *item = row >= 0 && row < (NSInteger)_sessionSidebarRows.count
        ? _sessionSidebarRows[row] : nil;
    if ([item[@"kind"] isEqual:@"project"]) {
        PTSessionProjectCellView *cell = [tableView
            makeViewWithIdentifier:@"PTSessionProjectCell" owner:self];
        if (!cell) {
            cell = [[PTSessionProjectCellView alloc] initWithFrame:NSMakeRect(0, 0, 260, 42)];
            cell.identifier = @"PTSessionProjectCell";
        }
        [cell configureWithProjectKey:item[@"projectKey"]
                                title:item[@"title"]
                         sessionCount:[item[@"sessionCount"] unsignedIntegerValue]
                            collapsed:[item[@"collapsed"] boolValue]
                               target:self
                               action:@selector(toggleSessionProject:)];
        return cell;
    }

    PTSessionCellView *cell = [tableView makeViewWithIdentifier:@"PTSessionCell" owner:self];
    if (!cell) {
        cell = [[PTSessionCellView alloc] initWithFrame:NSMakeRect(0, 0, 260, 62)];
        cell.identifier = @"PTSessionCell";
    }
    PTSessionInfo *session = item[@"session"];
    [cell configure:session];
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= (NSInteger)_sessionSidebarRows.count) return 66.0;
    return [_sessionSidebarRows[row][@"kind"] isEqual:@"project"] ? 42.0 : 66.0;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    (void)tableView;
    return [self sessionForSidebarRow:row] != nil;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    PTSessionRowView *rowView = [tableView makeViewWithIdentifier:@"PTSessionRow" owner:self];
    if (!rowView) {
        rowView = [[PTSessionRowView alloc] initWithFrame:NSZeroRect];
        rowView.identifier = @"PTSessionRow";
    }
    return rowView;
}

// 右键菜单只对 clickedRow 生效，不改选中项——老师可能只想看看某个会话的文件在哪，
// 不希望右键顺手把正在同步的会话切走。行号会被 1.5 秒一次的 applySessions 打乱，
// 所以路径在菜单弹出时就固化进 representedObject，回调时不再按行号回查。
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _sessionTable.menu) return;
    [menu removeAllItems];
    NSInteger row = _sessionTable.clickedRow;
    PTSessionInfo *session = [self sessionForSidebarRow:row];
    if (!session) return;

    [self populateSessionContextMenu:menu forSession:session];
}

- (void)populateSessionContextMenu:(NSMenu *)menu forSession:(PTSessionInfo *)session {
    NSString *path = session.filePath ?: @"";
    BOOL exists = path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:path];

    NSMenuItem *rename = [menu addItemWithTitle:PTL(@"重命名", @"Rename") action:@selector(renameSessionFromMenu:) keyEquivalent:@""];
    rename.target = self;
    rename.representedObject = session;
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *reveal = [menu addItemWithTitle:PTL(@"在 Finder 中显示", @"Reveal in Finder")
                                         action:@selector(revealSessionTranscript:)
                                  keyEquivalent:@""];
    reveal.target = self;
    reveal.representedObject = path;
    reveal.enabled = exists;
    reveal.toolTip = exists ? path : PTL(@"transcript 文件已不存在", @"Transcript file no longer exists");

    NSMenuItem *copyPath = [menu addItemWithTitle:PTL(@"拷贝 transcript 路径", @"Copy transcript path")
                                           action:@selector(copySessionTranscriptPath:)
                                    keyEquivalent:@""];
    copyPath.target = self;
    copyPath.representedObject = path;
    copyPath.enabled = path.length > 0;

    [menu addItem:[NSMenuItem separatorItem]];
    NSString *projectPath = session.cwd.stringByStandardizingPath ?: @"";
    BOOL isDirectory = NO;
    BOOL projectExists = projectPath.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:projectPath isDirectory:&isDirectory] &&
        isDirectory;
    NSMenuItem *openProject = [menu addItemWithTitle:PTL(@"打开项目文件夹", @"Open project folder")
                                               action:@selector(openSessionProjectFolder:)
                                        keyEquivalent:@""];
    openProject.target = self;
    openProject.representedObject = projectPath;
    openProject.enabled = projectExists;
    openProject.toolTip = projectExists
        ? projectPath
        : PTL(@"session 的项目文件夹已不存在", @"The session project folder no longer exists");
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
    _statusLabel.stringValue = sent
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
    _statusLabel.stringValue = PTL(@"正在接入 Claude 并同步名称…", @"Connecting to Claude to sync the name…");
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
            self->_statusLabel.stringValue = [NSString stringWithFormat:PTL(@"本地名称已保存，Claude 名称同步失败：%@", @"Local name saved; Claude name sync failed: %@"), status ?: @""];
        }
    };
    [connection connectToSession:session];
}

- (void)renameSessionFromMenu:(NSMenuItem *)sender {
    PTSessionInfo *session = sender.representedObject;
    NSAlert *alert = [NSAlert new];
    alert.messageText = PTL(@"重命名会话", @"Rename conversation");
    [alert addButtonWithTitle:PTL(@"保存", @"Save")];
    [alert addButtonWithTitle:PTL(@"取消", @"Cancel")];
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 28)];
    name.stringValue = session.title ?: @"";
    alert.accessoryView = name;
    [alert.window setInitialFirstResponder:name];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [self renameSession:session toTitle:name.stringValue];
    }];
}

- (void)revealSessionTranscript:(NSMenuItem *)sender {
    NSString *path = [sender.representedObject isKindOfClass:NSString.class]
        ? sender.representedObject : nil;
    if (path.length == 0) return;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        _statusLabel.stringValue = PTL(@"transcript 文件已不存在", @"Transcript file no longer exists");
        return;
    }
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}

- (void)copySessionTranscriptPath:(NSMenuItem *)sender {
    NSString *path = [sender.representedObject isKindOfClass:NSString.class]
        ? sender.representedObject : nil;
    if (path.length == 0) return;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:path forType:NSPasteboardTypeString];
    _statusLabel.stringValue = PTL(@"已拷贝 transcript 路径", @"Transcript path copied");
}

- (void)openSessionProjectFolder:(NSMenuItem *)sender {
    NSString *path = [sender.representedObject isKindOfClass:NSString.class]
        ? [sender.representedObject stringByStandardizingPath] : nil;
    BOOL isDirectory = NO;
    if (path.length == 0 ||
        ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] ||
        !isDirectory) {
        _statusLabel.stringValue = PTL(@"session 的项目文件夹已不存在",
                                       @"The session project folder no longer exists");
        return;
    }
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path isDirectory:YES]];
}

// 三个地方（bridge 状态变化 / 切换选中会话 / 点击接入按钮）都会想改按钮文案，
// 各写各的会互相打脸（比如点了"正在同步…"之后 bridge 的回调又把它覆盖成别的状态）。
// 统一到这一个方法里、按同一套优先级算，其它地方只管调用它。
- (void)updateConnectButtonTitle {
    if (_connecting) {
        _connectButton.title = PTL(@"正在同步…", @"Syncing…");
        return;
    }
    BOOL sameConnection = _bridge.running && [_bridge.sessionID isEqual:_selectedSession.sessionID];
    _connectButton.title = sameConnection
        ? PTL(@"已同步", @"Synced") : PTL(@"连接 Claude", @"Sync");
    [self refreshAgentStateAndControls];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    NSInteger row = _sessionTable.selectedRow;
    PTSessionInfo *session = [self sessionForSidebarRow:row];
    if (!session) return;
    if (_homeVisible && !_applyingSessions) [self hideHome:nil];
    BOOL changed = ![_selectedSession.sessionID isEqual:session.sessionID];
    _selectedSession = session;
    _activeWorkspaceTab.sessionID = session.sessionID ?: @"";
    [self showSelectedSession];
    [self updateConnectButtonTitle];
    [self updateWorkspaceTabBar];
    if (changed && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _conversationView.alphaValue = 0.62;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.18;
            self->_conversationView.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSString *languageScript = [NSString stringWithFormat:
        @"window.setPrettyTermLanguage && window.setPrettyTermLanguage('%@'); null;",
        PTInterfaceLanguageCode()];
    [webView evaluateJavaScript:languageScript completionHandler:nil];
    if (webView == _filePreviewWebView) {
        _filePreviewWebReady = YES;
        [self renderActiveFilePreview];
        return;
    }
    if (webView == _floatingConversationView) {
        _floatingWebReady = YES;
        [self refreshFloatingConversation];
        return;
    }
    _webReady = YES;
    if (_selectedSession) [self renderSession:_selectedSession];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if (![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *body = message.body;
    if ([message.name isEqualToString:@"openTranscriptFile"]) {
        NSString *sessionID = [body[@"sessionId"] isKindOfClass:NSString.class]
            ? body[@"sessionId"] : @"";
        NSString *path = [body[@"filePath"] isKindOfClass:NSString.class]
            ? body[@"filePath"] : @"";
        PTSessionInfo *session = [self sessionWithID:sessionID];
        if (!path.isAbsolutePath) path = [session.cwd stringByAppendingPathComponent:path];
        [self openPreviewFileURL:[NSURL fileURLWithPath:path.stringByStandardizingPath]];
        [_window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }
    if ([message.name isEqualToString:@"openTranscriptEditReview"]) {
        NSString *sessionID = [body[@"sessionId"] isKindOfClass:NSString.class]
            ? body[@"sessionId"] : @"";
        NSNumber *turnIndexValue = [body[@"turnIndex"] isKindOfClass:NSNumber.class]
            ? body[@"turnIndex"] : nil;
        NSString *expectedSessionID = message.webView == _conversationView
            ? _selectedSession.sessionID
            : (message.webView == _floatingConversationView ? _floatingSessionID : nil);
        if (sessionID.length > 0 && turnIndexValue && [sessionID isEqual:expectedSessionID]) {
            [self openTranscriptEditReviewForSessionID:sessionID
                                             turnIndex:turnIndexValue.unsignedIntegerValue];
        }
        return;
    }
    if ([message.name isEqualToString:@"copyAssistantOutput"]) {
        NSString *text = [body[@"text"] isKindOfClass:NSString.class] ? body[@"text"] : @"";
        NSString *sessionID = [body[@"sessionId"] isKindOfClass:NSString.class]
            ? body[@"sessionId"] : @"";
        NSString *expectedSessionID = message.webView == _conversationView
            ? _selectedSession.sessionID
            : (message.webView == _floatingConversationView ? _floatingSessionID : nil);
        if (text.length == 0 || sessionID.length == 0 ||
            ![sessionID isEqual:expectedSessionID]) return;
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        [pasteboard clearContents];
        [pasteboard setString:text forType:NSPasteboardTypeString];
        NSString *status = [body[@"kind"] isEqual:@"code"]
            ? PTL(@"已复制代码", @"Code copied")
            : PTL(@"已复制 Claude 输出", @"Claude output copied");
        if (message.webView == _conversationView) {
            _statusLabel.stringValue = status;
        } else {
            _floatingComposerLabel.stringValue = status;
        }
        return;
    }
    if ([message.name isEqualToString:@"answerQuestion"]) {
        NSString *text = [body[@"text"] isKindOfClass:NSString.class] ? body[@"text"] : @"";
        NSString *sessionID = [body[@"sessionId"] isKindOfClass:NSString.class] ? body[@"sessionId"] : @"";
        NSString *expectedSessionID = message.webView == _conversationView
            ? _selectedSession.sessionID
            : (message.webView == _floatingConversationView ? _floatingSessionID : nil);
        if (text.length == 0 || sessionID.length == 0 || ![sessionID isEqual:expectedSessionID]) return;
        NSString *toolUseID = body[@"toolUseId"];
        NSDictionary *answers = [body[@"answers"] isKindOfClass:NSDictionary.class] ? body[@"answers"] : nil;
        for (NSString *requestID in _protocolQuestions.allKeys) {
            NSDictionary *request = _protocolQuestions[requestID];
            if ([request[@"sessionID"] isEqual:sessionID] && [request[@"toolUseId"] isEqual:toolUseID]) {
                [self writeQuestionResponseForRequestID:requestID answers:answers ?: @{}];
                return;
            }
        }
        // 复用普通聊天发送的同一路径与 sendInFlight 互斥，跟老师手打消息走同一通道。
        [self sendOutgoingMessage:text
                         imagePNGs:@[]
                      forSessionID:sessionID
                           success:nil
                  failureResponder:nil];
        return;
    }
    if (![message.name isEqualToString:@"quoteSelection"]) return;
    NSString *text = [body[@"text"] isKindOfClass:NSString.class] ? body[@"text"] : nil;
    NSString *sessionID = [body[@"sessionId"] isKindOfClass:NSString.class] ? body[@"sessionId"] : nil;
    NSString *quote = PTMarkdownQuote(text);
    PTComposerTextView *composer = nil;
    NSTextField *status = nil;
    NSString *expectedSessionID = nil;

    if (message.webView == _conversationView) {
        composer = _composerTextView;
        status = _statusLabel;
        expectedSessionID = _selectedSession.sessionID;
    } else if (message.webView == _floatingConversationView) {
        composer = _floatingComposerTextView;
        status = _floatingComposerLabel;
        expectedSessionID = _floatingSessionID;
    } else {
        return;
    }

    BOOL correctConversation = quote.length > 0 && sessionID.length > 0 &&
        [sessionID isEqual:expectedSessionID];
    if (!correctConversation) {
        status.stringValue = @"引用目标与当前对话不一致";
        return;
    }

    [composer.window makeFirstResponder:composer];
    [composer insertText:quote replacementRange:composer.selectedRange];
    status.stringValue = @"已引用 Claude 选中内容";
}

- (void)refreshSessions:(id)sender {
    if (sender == _refreshButton) [self refreshClaudeUsage:nil];
    if (sender == _refreshButton && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        _refreshButton.alphaValue = 0.35;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.24;
            self->_refreshButton.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }
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
    [self updateConnectButtonTitle];
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
                self->_statusLabel.stringValue = status;
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
            self->_statusLabel.stringValue = status;
        }
    }];
    [_window makeFirstResponder:_composerTextView];
}

- (BOOL)interruptClaudeOutputForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return NO;
    PTClaudeBridge *targetBridge = [self bridgeForSessionID:sessionID];
    if (!targetBridge.running || ![targetBridge sendEscape]) return NO;
    // Keep Stop available until Claude confirms completion of the interrupted turn.
    return YES;
}

- (void)stopSelectedClaudeOutput:(id)sender {
    (void)sender;
    NSString *sessionID = _selectedSession.sessionID;
    if ([self interruptClaudeOutputForSessionID:sessionID]) {
        _statusLabel.stringValue = PTL(@"已向 Claude Code 发送中断请求",
                                        @"Interrupt request sent to Claude Code");
    } else {
        _statusLabel.stringValue = PTL(@"当前会话没有可用的 Claude 后台连接",
                                        @"No Claude background connection is available for this conversation");
    }
}

- (void)stopFloatingClaudeOutput:(id)sender {
    (void)sender;
    NSString *sessionID = _floatingSessionID;
    if ([self interruptClaudeOutputForSessionID:sessionID]) {
        _floatingComposerLabel.stringValue = PTL(@"已向 Claude Code 发送中断请求",
                                                  @"Interrupt request sent to Claude Code");
    } else {
        _floatingComposerLabel.stringValue = PTL(@"当前会话没有可用的 Claude 后台连接",
                                                  @"No Claude background connection is available for this conversation");
    }
}

- (BOOL)sendOutgoingMessage:(NSString *)message
                  imagePNGs:(NSArray<NSData *> *)imagePNGs
               forSessionID:(NSString *)sessionID
                    success:(dispatch_block_t)success
           failureResponder:(NSResponder *)failureResponder {
    NSString *outgoingMessage = PTMessageForClaudeAttachments(message, imagePNGs.count);
    if (outgoingMessage.length == 0) return NO;
    PTClaudeBridge *targetBridge = [self bridgeForSessionID:sessionID];
    BOOL configuration = !imagePNGs.count && [self isConfigurationCommand:outgoingMessage];
    if (!configuration && _agentState.sendInFlight) {
        if ([sessionID isEqual:_floatingSessionID]) {
            _floatingComposerLabel.stringValue = PTL(@"正在提交到 Claude Code…", @"Submitting to Claude Code…");
        } else {
            _statusLabel.stringValue = PTL(@"正在提交到 Claude Code…", @"Submitting to Claude Code…");
        }
        return NO;
    }
    if (!targetBridge) {
        [self prepareBridgeForSessionID:sessionID completion:^(PTClaudeBridge *bridge) {
            if (bridge) [self sendOutgoingMessage:message imagePNGs:imagePNGs forSessionID:sessionID
                success:success failureResponder:failureResponder];
        }];
        return YES;
    }

    if (!configuration) _agentState.sendInFlight = YES;
    [self refreshAgentStateAndControls];
    [targetBridge submitMessage:outgoingMessage withImagePNGs:imagePNGs ?: @[] completion:^(BOOL sent) {
        if (sent) {
            if (success) success();
        } else {
            NSString *status = targetBridge.lastSendError ?: PTL(@"Claude 未接受消息", @"Claude did not accept the message");
            if ([sessionID isEqual:self->_floatingSessionID]) {
                self->_floatingComposerLabel.stringValue = status;
            }
            if ([sessionID isEqual:self->_selectedSession.sessionID]) {
                self->_statusLabel.stringValue = status;
                if (failureResponder) [self->_window makeFirstResponder:failureResponder];
            }
        }
        if (!configuration) self->_agentState.sendInFlight = NO;
        [self refreshAgentStateAndControls];
    }];
    return YES;
}

- (void)sendMessage:(id)sender {
    (void)sender;
    NSString *message = _composerTextView.string;
    NSArray<NSData *> *imagePNGs = [self pendingImagePNGsForClaude];
    NSArray<NSString *> *files = [self pendingFilesForClaude];
    if (!imagePNGs.count && !files.count && [self handleLocalComposerCommand:message composer:_composerTextView]) return;
    NSString *outgoing = PTMessageByAppendingClaudeAttachMarkers(message, files);
    NSString *sessionID = [_selectedSession.sessionID copy];
    PTWorkspaceTab *tab = _activeWorkspaceTab;
    NSArray *images = [tab.pendingImages copy];
    [self sendOutgoingMessage:outgoing imagePNGs:imagePNGs
                 forSessionID:sessionID success:^{
        if (![self isConfigurationCommand:outgoing]) [self beginAwaitingClaudeReplyForSessionID:sessionID];
        if (self->_activeWorkspaceTab == tab) {
            [self->_composerTextView clearAfterSuccessfulSubmissionMatchingText:message];
        } else if ([tab.draft isEqual:message]) {
            tab.draft = @"";
        }
        [tab.pendingImages removeObjectsInArray:images];
        [tab.pendingFiles removeObjectsInArray:files];
        for (NSDictionary *image in images) {
            if (![image[@"temporary"] boolValue]) continue;
            [NSFileManager.defaultManager removeItemAtPath:image[@"path"] error:nil];
            [self->_temporaryImagePaths removeObject:image[@"path"]];
        }
        if (self->_activeWorkspaceTab == tab) [self updateImagePreviews];
    } failureResponder:_composerTextView];
}

- (void)sendFloatingMessage:(id)sender {
    (void)sender;
    NSString *message = _floatingComposerTextView.string;
    NSArray<NSData *> *imagePNGs = [self floatingPendingImagePNGsForClaude];
    NSArray<NSString *> *files = [self floatingPendingFilesForClaude];
    if (!imagePNGs.count && !files.count && [self handleLocalComposerCommand:message composer:_floatingComposerTextView]) return;
    NSString *outgoing = PTMessageByAppendingClaudeAttachMarkers(message, files);
    NSString *sessionID = [_floatingSessionID copy];
    NSMutableArray *pendingImages = _floatingPendingImages;
    NSMutableArray *pendingFiles = _floatingPendingFiles;
    NSArray *images = [pendingImages copy];
    [self sendOutgoingMessage:outgoing imagePNGs:imagePNGs
                 forSessionID:sessionID success:^{
        if (![self isConfigurationCommand:outgoing]) [self beginAwaitingClaudeReplyForSessionID:sessionID];
        if ([self->_floatingSessionID isEqual:sessionID]) {
            [self->_floatingComposerTextView clearAfterSuccessfulSubmissionMatchingText:message];
        }
        [pendingImages removeObjectsInArray:images];
        [pendingFiles removeObjectsInArray:files];
        for (NSDictionary *image in images) {
            if ([image[@"temporary"] boolValue])
                [NSFileManager.defaultManager removeItemAtPath:image[@"path"] error:nil];
        }
        if ([self->_floatingSessionID isEqual:sessionID]) [self updateFloatingImagePreviews];
    } failureResponder:_floatingComposerTextView];
}

- (void)compactConversation:(id)sender {
    (void)sender;
    NSString *sessionID = [_selectedSession.sessionID copy];
    [self sendOutgoingMessage:@"/compact"
                    imagePNGs:@[]
                 forSessionID:sessionID
                      success:^{
        [self beginAwaitingClaudeReplyForSessionID:sessionID];
        self->_statusLabel.stringValue = PTL(@"已向 Claude Code 发送 /compact", @"Sent /compact to Claude Code");
    } failureResponder:nil];
}

- (BOOL)isConfigurationCommand:(NSString *)text {
    NSString *command = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [command hasPrefix:@"/model "] || [command hasPrefix:@"/effort "] || [command hasPrefix:@"/mode "] ||
        [@[@"/plan", @"/auto", @"/bypass", @"/remote-control"] containsObject:command];
}

- (BOOL)handleLocalComposerCommand:(NSString *)text composer:(PTComposerTextView *)composer {
    NSString *command = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![@[@"/config", @"/model", @"/effort", @"/mode", @"/permissions", @"/help", @"/commands"] containsObject:command]) return NO;
    [composer clearAfterSuccessfulSubmissionMatchingText:text];
    if ([@[@"/help", @"/commands"] containsObject:command]) {
        [composer insertText:@"/" replacementRange:composer.selectedRange];
        [self showClaudeCommands:composer];
        return YES;
    }
    [self showComposerOptions:composer == _floatingComposerTextView ? _floatingEffortButton : _composerEffortButton];
    if ([command isEqual:@"/config"]) [self showComposerAdvancedPage:nil];
    else if ([command isEqual:@"/model"]) [self showComposerModelPage:nil];
    else if ([@[@"/mode", @"/permissions"] containsObject:command]) [self showComposerModePage:nil];
    return YES;
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

- (void)enableRemoteControl:(id)sender {
    (void)sender;
    [self sendOutgoingMessage:@"/remote-control"
                    imagePNGs:@[]
                 forSessionID:_selectedSession.sessionID
                      success:^{
        self->_statusLabel.stringValue = PTL(@"已向 Claude Code 发送 /remote-control", @"Sent /remote-control to Claude Code");
    } failureResponder:nil];
}

- (void)changeModel:(id)sender {
    _configurationSessionID = _selectedSession.sessionID;
    [self changeComposerToModel:_modelPicker.selectedItem.representedObject];
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
    NSTextField *markLabel = [self label:@"✦" size:17 weight:NSFontWeightBold color:PTWarmAccentColor()];
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
    closeButton.fillColor = NSColor.clearColor;
    closeButton.hoverFillColor = PTWarmChipColor();
    closeButton.pressedFillColor = PTWarmBorderColor();
    closeButton.strokeColor = NSColor.clearColor;
    closeButton.cornerRadius = 15;
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

    PTAnimatedButton *submitButton = [[PTAnimatedButton alloc] initWithFrame:NSZeroRect];
    submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    submitButton.title = PTL(@"提交回答   ↗", @"Submit answers   ↗");
    submitButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    submitButton.contentTintColor = NSColor.whiteColor;
    submitButton.fillColor = PTWarmAccentColor();
    submitButton.hoverFillColor = PTWarmDynamicColor(0.720, 0.326, 0.120, 0.965, 0.620, 0.370);
    submitButton.pressedFillColor = PTWarmDynamicColor(0.535, 0.205, 0.060, 0.740, 0.350, 0.165);
    submitButton.strokeColor = PTWarmAccentColor();
    submitButton.cornerRadius = 21;
    submitButton.target = self;
    submitButton.action = @selector(submitQuestionPanel:);
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
        NSTextField *headerLabel = [self label:header size:10 weight:NSFontWeightBold color:PTWarmAccentColor()];
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
    NSTextField *plus = [self label:@"＋" size:15 weight:NSFontWeightMedium color:PTWarmAccentColor()];
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
