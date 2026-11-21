#import "Patches/CommandBar/CommandBarSwap.m"
#import "Patches/CommandBar/HideTabButton.m"

char DPOverlayKey;
const uintptr_t DPFirstFill = 4;

@implementation DPCommandBarOverlay
- (NSView *)viewUnder:(NSPoint)point { return nil; }
@end

static NSMutableSet<NSString *> *gHidden;
static NSMutableArray<DPCommandBarOverlay *> *gCancelled;
static NSMutableArray<NSEvent *> *gPosted;

BOOL DPHiding(void) { return YES; }
BOOL DPHidesTab(NSString *tabID) { return tabID && [gHidden containsObject:tabID]; }
uintptr_t *DPSelectionStyle(NSView *background) { return NULL; }
uint8_t *DPTabShape(NSView *background) { return NULL; }
NSView *DPTabShapeView(NSView *background) { return nil; }
BOOL DPStyleSelected(uintptr_t style) { return NO; }
BOOL DPDrawnSelected(NSView *background) { return NO; }
void DPNoteLook(NSView *background) {}
NSArray *DPSelectedLook(NSView *button) { return nil; }
BOOL DPSwitchingTo(NSView *background) { return NO; }
void DPEndSwitch(NSWindow *window) {}
void DPUnselectFrontTab(NSView *background, BOOL standingIn) {}
void DPGiveBackSelection(NSView *background) {}
BOOL DPHoldsSelection(NSView *background) { return NO; }
void DPInstallFrontTab(void) {}

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

        if (failures) return 1;
        puts("PASS: command bar swap stand-in and key-focus guards");
    }
    return 0;
}
