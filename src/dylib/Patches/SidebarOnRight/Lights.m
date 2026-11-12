#import "SidebarOnRight.h"

// With the sidebar on the right, Dia's window buttons would ride along in its header, far from the window's corner. Like
// Zen's, they stay in the top left corner instead, out of sight until the pointer goes there. Hide Window Controls wins,
// and in full screen macOS slides the buttons in with the menu bar, so Dia's stay where they are.
static const CGFloat DPLightsInset = 14;  // The close button from the window's corner, where Dia puts it with tabs at the top.
static const CGFloat DPLightsSpacing = 20;
static const CGFloat DPLightsPad = 7;  // The backdrop around the buttons.
static const NSTimeInterval DPLightsLinger = 0.4;
static char DPStripKey;

// Where the pointer really is. Hover.m mirrors +[NSEvent mouseLocation] and events at the window's edges, so this asks
// the window server instead.
static NSPoint DPRealPointer(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint point = event ? CGEventGetLocation(event) : CGPointZero;
    if (event) CFRelease(event);
    return NSMakePoint(point.x, NSHeight(NSScreen.screens.firstObject.frame) - point.y);
}
static NSPoint (*DPLightsPointer)(void) = DPRealPointer;

BOOL DPSidebarOnRightTakesLights(NSWindow *window) {
    static DPPatch *hide;
    hide = hide ?: DPPatchNamed(@"hideTrafficLights");
    return DPSidebarOnRight.on && window && !(hide && hide->on) && !(window.styleMask & NSWindowStyleMaskFullScreen);
}

// Dia's own buttons showing anywhere in the window, such as in the toolbar while the sidebar is closed.
BOOL DPDiaLightsShowIn(NSWindow *window) {
    NSView *top = window.contentView.superview ?: window.contentView;
    return DPFindView(top, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTrafficLights) && !v.hiddenOrHasHiddenAncestor && v.alphaValue > 0.01; }) != nil;
}

static BOOL DPWantsStrip(NSWindow *window) {
    return DPSidebarOnRightTakesLights(window) && DPHasSidebarIn(window) && !DPDiaLightsShowIn(window);
}

@interface DPLightsStrip : NSView
@property(nonatomic) BOOL revealed, inside;
@property(nonatomic) NSTimeInterval insideAt;
@property(nonatomic, strong) NSTimer *watch;
@property(nonatomic, copy) NSArray<NSButton *> *buttons;
@end

@implementation DPLightsStrip

- (instancetype)initForWindow:(NSWindow *)window {
    NSWindowButton kinds[] = {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton};
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSButton *button = [NSWindow standardWindowButton:kinds[i] forStyleMask:window.styleMask];
        if (button) [buttons addObject:button];
    }
    NSSize size = buttons.firstObject ? buttons.firstObject.frame.size : NSMakeSize(14, 16);
    CGFloat width = 2 * DPLightsSpacing + size.width;
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, width + 2 * DPLightsInset, size.height + 2 * DPLightsInset)])) return nil;
    self.wantsLayer = YES;
    self.alphaValue = 0;
    NSVisualEffectView *backdrop = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(DPLightsInset - DPLightsPad, DPLightsInset - DPLightsPad, width + 2 * DPLightsPad, size.height + 2 * DPLightsPad)];
    backdrop.material = NSVisualEffectMaterialTitlebar;
    backdrop.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    backdrop.state = NSVisualEffectStateActive;
    backdrop.wantsLayer = YES;
    backdrop.layer.cornerRadius = NSHeight(backdrop.frame) / 2;
    backdrop.layer.masksToBounds = YES;
    [self addSubview:backdrop];
    [buttons enumerateObjectsUsingBlock:^(NSButton *button, NSUInteger i, BOOL *stop) {
        [button setFrameOrigin:NSMakePoint(DPLightsInset + i * DPLightsSpacing, DPLightsInset)];
        [self addSubview:button];
    }];
    _buttons = [buttons copy];
    return self;
}

- (void)dealloc { [_watch invalidate]; }

// Out of sight, clicks in the corner reach the page.
- (NSView *)hitTest:(NSPoint)point { return self.revealed && !self.hidden ? [super hitTest:point] : nil; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingAreas.count) return;
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect;
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)event { [self refresh]; }
- (void)mouseExited:(NSEvent *)event { [self refresh]; }

// AppKit's buttons show their symbols while the pointer is over the group they're in.
- (BOOL)_mouseInGroup:(NSButton *)button { return self.inside; }

- (void)setRevealed:(BOOL)revealed animated:(BOOL)animated {
    if (revealed == _revealed) return;
    _revealed = revealed;
    if (!animated) {
        self.alphaValue = revealed ? 1 : 0;
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = revealed ? 0.12 : 0.2;
        self.animator.alphaValue = revealed ? 1 : 0;
    }];
}

// Enter and exit events at the window's edge may be mirrored ones, so the pointer's real place decides, checked again
// while the buttons show until it has been away for a moment.
- (void)refresh {
    NSWindow *window = self.window;
    BOOL wanted = window && !self.hidden && DPWantsStrip(window);
    BOOL inside = wanted && NSPointInRect(DPLightsPointer(), [window convertRectToScreen:[self convertRect:self.bounds toView:nil]]);
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (inside) self.insideAt = now;
    if (inside != self.inside) {
        self.inside = inside;
        for (NSButton *button in self.buttons) button.needsDisplay = YES;
    }
    BOOL revealed = wanted && (inside || (self.revealed && now - self.insideAt < DPLightsLinger));
    [self setRevealed:revealed animated:YES];
    if (revealed && !self.watch) {
        __weak DPLightsStrip *weakSelf = self;
        self.watch = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
        [NSRunLoop.mainRunLoop addTimer:self.watch forMode:NSRunLoopCommonModes];
    } else if (!revealed) {
        [self.watch invalidate];
        self.watch = nil;
    }
}

@end

NSView *DPLightsStripIn(NSWindow *window) { return window ? DPGet(window, &DPStripKey) : nil; }

// The strip sits over everything in the window's frame view, pinned to the top left corner.
void DPUpdateLights(NSWindow *window) {
    if (!window) return;
    DPLightsStrip *strip = DPGet(window, &DPStripKey);
    NSView *frameView = window.contentView.superview;
    if (!frameView || !DPWantsStrip(window)) {
        strip.hidden = YES;
        [strip setRevealed:NO animated:NO];
        [strip.watch invalidate];
        strip.watch = nil;
        return;
    }
    if (!strip) {
        strip = [[DPLightsStrip alloc] initForWindow:window];
        DPSet(window, &DPStripKey, strip);
    }
    if (strip.superview != frameView || frameView.subviews.lastObject != strip) [frameView addSubview:strip positioned:NSWindowAbove relativeTo:nil];
    NSRect bounds = frameView.bounds;
    strip.autoresizingMask = NSViewMaxXMargin | (frameView.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
    [strip setFrameOrigin:NSMakePoint(NSMinX(bounds), frameView.isFlipped ? NSMinY(bounds) : NSMaxY(bounds) - NSHeight(strip.frame))];
    strip.hidden = NO;
}

// Layout runs many times a frame while the sidebar moves, so a window is looked at once per run loop turn.
void DPScheduleLights(NSWindow *window) {
    static NSHashTable<NSWindow *> *pending;
    pending = pending ?: [NSHashTable weakObjectsHashTable];
    if (!window || [pending containsObject:window]) return;
    if (!DPSidebarOnRight.on && !DPGet(window, &DPStripKey)) return;
    [pending addObject:window];
    __weak NSWindow *weakWindow = window;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = weakWindow;
        if (!window) return;
        [pending removeObject:window];
        DPUpdateLights(window);
    });
}

static void DPHeader_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPHeader_layout, self);
    DPScheduleLights(self.window);
}

void DPInstallLights(void) {
    DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPHeader_layout);
    NSArray<NSNotificationName> *names = @[ NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification, NSWindowDidResizeNotification ];
    for (NSNotificationName name in names)
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSWindow *window = note.object;
            if (!DPGet(window, &DPStripKey)) return;
            // Dia's buttons go back into the header, or come out of it, as full screen changes.
            for (NSView *header in DPFindViews(DPDiaSidebarHeader)) if (header.window == window) header.needsLayout = YES;
            DPScheduleLights(window);
        }];
}
