#import "Patches/CommandBar/CommandBarSwap.m"
#import "Patches/CommandBar/HideTabButton.m"

DPPatch DPCommandBar = { .on = YES };
char DPOverlayKey;
const uintptr_t DPFirstFill = 4;

@implementation DPCommandBarOverlay
- (NSView *)viewUnder:(NSPoint)point { return nil; }
@end

static NSMutableSet<NSString *> *gHidden;
static NSMutableArray<DPCommandBarOverlay *> *gCancelled;
static NSMutableArray<NSEvent *> *gPosted;
static BOOL gHiding = YES, gHoldsSelection;
static int gGiveBackCalls;
static uintptr_t gStyle = 2;
static uint8_t gShape = 0;

BOOL DPHiding(void) { return gHiding; }
BOOL DPHidesTab(NSString *tabID) { return gHiding && tabID && [gHidden containsObject:tabID]; }
uintptr_t *DPSelectionStyle(NSView *background) { return &gStyle; }
uint8_t *DPTabShape(NSView *background) { return &gShape; }
NSView *DPTabShapeView(NSView *background) { return nil; }
BOOL DPStyleSelected(uintptr_t style) { return style == 0 || style >= DPFirstFill; }
BOOL DPDrawnSelected(NSView *background) { return DPStyleSelected(gStyle); }
void DPNoteLook(NSView *background) {}
NSArray *DPSelectedLook(NSView *button) { return @[ NSNull.null, @(1) ]; }
BOOL DPSwitchingTo(NSView *background) { return NO; }
void DPEndSwitch(NSWindow *window) {}
void DPUnselectFrontTab(NSView *background, BOOL standingIn) {}
void DPGiveBackSelection(NSView *background) { gGiveBackCalls++; gHoldsSelection = NO; }
BOOL DPHoldsSelection(NSView *background) { return gHoldsSelection; }
void DPInstallFrontTab(void) {}

@interface _TtC7TabList14NewTabCellView : NSView
@end
@implementation _TtC7TabList14NewTabCellView
@end

@interface TabUI_TabBackgroundView : NSView
@end
@implementation TabUI_TabBackgroundView
- (void)updateLayer {}
@end

void DPCancelCommandBar(DPCommandBarOverlay *overlay) {
    if (!overlay) return;
    [gCancelled addObject:overlay];
    if (overlay.openedTab) DPStandInForTab(overlay.host, overlay.openedTab);
    if (DPGet(overlay.host, &DPOverlayKey) == overlay) DPSet(overlay.host, &DPOverlayKey, nil);
}

@interface DPTestWindow : NSWindow
@property BOOL fakeKey;
@end
@implementation DPTestWindow
- (BOOL)isKeyWindow { return self.fakeKey; }
@end

static void DPApp_postEvent(NSApplication *self, SEL _cmd, NSEvent *event, BOOL atStart) {
    [gPosted addObject:event];
}

static NSEvent *DPKeyEvent(NSWindow *window, unsigned short keyCode, NSString *chars) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                           timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                             context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:keyCode];
}

static DPCommandBarOverlay *DPOverlay(NSWindow *window, id tab) {
    DPCommandBarOverlay *overlay = [DPCommandBarOverlay new];
    overlay.host = window;
    overlay.openedTab = tab;
    return overlay;
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(NSApp.class, @selector(postEvent:atStart:), (IMP)DPApp_postEvent);
        gHidden = [NSMutableSet setWithObjects:@"tab-1", @"tab-2", nil];
        gCancelled = [NSMutableArray array];
        gPosted = [NSMutableArray array];

        DPTestWindow *window = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 100, 100)
                                                               styleMask:NSWindowStyleMaskBorderless
                                                                 backing:NSBackingStoreBuffered defer:NO];
        window.fakeKey = YES;

        DPCommandBarOverlay *first = DPOverlay(window, @"tab-1");
        DPSet(window, &DPOverlayKey, first);
        DPStandInFor(window, @"tab-1");
        DPHandOver(first);
        DPCommandBarOverlay *second = DPOverlay(window, @"tab-2");
        DPSet(window, &DPOverlayKey, second);
        DPStandInFor(window, @"tab-2");

        DPFinishHandOver(window);
        CHECK(gCancelled.count == 1 && gCancelled.firstObject == first, "hand-over finish cancels only the old bar");
        CHECK([DPGet(window, &DPTabKey) isEqual:@"tab-2"] && DPStandingIn(window), "late cancel preserves the newer bar's stand-in");
        CHECK(DPGet(window, &DPOverlayKey) == second, "late cancel preserves the newer bar overlay");

        DPStandInForTab(window, @"tab-2");
        CHECK(DPGet(window, &DPTabKey) == nil && !DPStandingIn(window), "clearing the active bar's own tab removes the stand-in");
        DPSet(window, &DPOverlayKey, nil);

        NSEvent *cmdT = DPKeyEvent(window, 17, @"t"), *cmdL = DPKeyEvent(window, 37, @"l");
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdL, NO), "press while catching up is swallowed");
        DPSet(window, &DPOverlayKey, DPOverlay(window, @"tab-1"));
        DPDiaCaughtUp(window);
        CHECK(gPosted.count == 1 && gPosted.firstObject.keyCode == 37, "key window replays the queued swap press");
        CHECK(DPGet(window, &DPCatchingUpKey) == nil && DPGet(window, &DPWantKey) == nil, "catching-up state and want key are cleared");

        [gPosted removeAllObjects];
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdL, NO), "second swap press is swallowed while catching up");
        window.fakeKey = NO;
        DPDiaCaughtUp(window);
        CHECK(gPosted.count == 0, "non-key window does not post a replayed key event");
        CHECK(DPGet(window, &DPCatchingUpKey) == nil && DPGet(window, &DPWantKey) == nil, "non-key catch-up still clears state");
        CHECK(!DPWaitForDia(window, cmdT, YES), "window is not stuck catching up after losing key focus");

        [gCancelled removeAllObjects];
        DPCommandBarOverlay *third = DPOverlay(window, @"tab-1");
        DPSet(window, &DPOverlayKey, third);
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdT, YES), "toggle press while catching up is swallowed");
        DPDiaCaughtUp(window);
        CHECK(gCancelled.count == 1 && gCancelled.firstObject == third && gPosted.count == 0, "wanted close cancels directly without posting");
        CHECK(DPGet(window, &DPWantKey) == nil, "close path clears want key");

        [gPosted removeAllObjects];
        [gCancelled removeAllObjects];
        window.fakeKey = YES;
        DPHandToDia(window, cmdT, YES);
        CHECK(DPWaitForDia(window, cmdL, NO), "swap press queued before turning off");
        DPCommandBar.on = NO;
        DPDiaCaughtUp(window);
        CHECK(gPosted.count == 0 && gCancelled.count == 0, "turning CommandBar off prevents queued swap replay");
        CHECK(DPGet(window, &DPCatchingUpKey) == nil && DPGet(window, &DPWantKey) == nil, "off catch-up clears all state");

        DPCommandBar.on = YES;
        DPCommandBarOverlay *handed = DPOverlay(window, @"tab-1");
        DPSet(window, &DPOverlayKey, handed);
        DPHandOver(handed);
        CHECK(DPTakeHandOver(window) == handed && DPTakeHandOver(window) == nil, "DPTakeHandOver returns and clears handed-over bar");

        // Regression: HideTabButton restores DPSavedKey & DPHoldsSelection on invisible window during layout/updateLayer when off.
        Class bgCls = objc_allocateClassPair(TabUI_TabBackgroundView.class, DPDiaTabBackground, 0);
        objc_registerClassPair(bgCls);
        DPInstallStandIn();
        _TtC7TabList14NewTabCellView *newTabBtn = [[_TtC7TabList14NewTabCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
        NSView *bg = [[bgCls alloc] initWithFrame:newTabBtn.bounds];
        [newTabBtn addSubview:bg];
        [window.contentView addSubview:newTabBtn];
        gHiding = YES;
        gStyle = 2;
        gShape = 0;
        DPStandInFor(window, @"tab-1");
        CHECK(gStyle == 0 && gShape == 1 && DPGet(bg, &DPSavedKey) != nil, "New Tab button selected on non-visible window");
        gHiding = NO;
        gHoldsSelection = YES;
        gGiveBackCalls = 0;
        [bg layout];
        CHECK(gStyle == 2 && gShape == 0 && DPGet(bg, &DPSavedKey) == nil && gGiveBackCalls == 1,
              "turning hiding off restores button selection and front-tab selection once on next layout");
        [bg layout];
        CHECK(gGiveBackCalls == 1, "subsequent layouts while off do nothing");

        if (failures) return 1;
        puts("PASS: command bar swap stand-in and key-focus guards");
    }
    return 0;
}
