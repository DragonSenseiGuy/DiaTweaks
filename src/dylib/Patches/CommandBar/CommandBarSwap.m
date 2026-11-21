#import "Patches/CommandBar/CommandBarOverlay.h"

static char DPHandingOverKey;

void DPFinishHandOver(NSWindow *window) {
    DPCommandBarOverlay *old = DPGet(window, &DPHandingOverKey);
    if (!old) return;
    DPSet(window, &DPHandingOverKey, nil);
    DPCancelCommandBar(old);
}

void DPHandOver(DPCommandBarOverlay *overlay) {
    NSWindow *window = overlay.host;
    DPFinishHandOver(window);  // One still going, so its bar doesn't stay up with nothing to close it.
    [overlay.watch invalidate];
    if (overlay.keyMonitor) [NSEvent removeMonitor:overlay.keyMonitor];
    overlay.keyMonitor = nil;
    DPSet(window, &DPOverlayKey, nil);
    DPSet(window, &DPHandingOverKey, overlay);
    __weak NSWindow *weak = window;  // With the toolbar showing, ⌘L's bar stays in it, so nothing takes over.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPFinishHandOver(weak); });
}

// Dia takes a moment to open the tab or the bar a ⌘T or ⌘L handed to it asks for, and a bar that isn't up yet can't be
// closed or swapped, so pressing them quickly would stack bars. Presses meanwhile only change which bar is wanted: each
// closes the bar it would open if that's the one wanted, or wants it. Once Dia has caught up, one press makes it so.
static char DPCatchingUpKey, DPWantKey, DPPressedKey, DPNewTabPressKey, DPAddressPressKey;

typedef NS_ENUM(NSInteger, DPBar) { DPNoBar, DPNewTabBar, DPAddressBar };

static DPBar DPBarIn(NSWindow *window) {
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    return !overlay ? DPNoBar : overlay.openedTab ? DPNewTabBar : DPAddressBar;
}

// The last press of each, to press again as it was, whatever the shortcut is.
static void DPNotePress(NSWindow *window, NSEvent *event, BOOL newTab) { DPSet(window, newTab ? &DPNewTabPressKey : &DPAddressPressKey, event); }

NSEvent *DPHandToDia(NSWindow *window, NSEvent *event, BOOL newTab) {
    NSObject *token = [NSObject new];
    DPSet(window, &DPCatchingUpKey, token);
    DPSet(window, &DPWantKey, @(newTab ? DPNewTabBar : DPAddressBar));
    DPSet(window, &DPPressedKey, nil);
    DPNotePress(window, event, newTab);
    __weak NSWindow *weak = window;  // In case what Dia opens never shows, such as ⌘L's bar staying in the toolbar.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (DPGet(weak, &DPCatchingUpKey) == token) DPDiaCaughtUp(weak);
    });
    return event;
}

BOOL DPWaitForDia(NSWindow *window, NSEvent *event, BOOL newTab) {
    if (!DPGet(window, &DPCatchingUpKey)) return NO;
    DPBar bar = newTab ? DPNewTabBar : DPAddressBar;
    DPSet(window, &DPWantKey, @([DPGet(window, &DPWantKey) integerValue] == bar ? DPNoBar : bar));
    DPSet(window, &DPPressedKey, @YES);
    DPNotePress(window, event, newTab);
    return YES;
}

void DPDiaCaughtUp(NSWindow *window) {
    if (!window || !DPGet(window, &DPCatchingUpKey)) return;
    BOOL pressed = DPGet(window, &DPPressedKey) != nil;
    DPBar want = [DPGet(window, &DPWantKey) integerValue], have = DPBarIn(window);
    NSEvent *press = DPGet(window, want == DPNewTabBar ? &DPNewTabPressKey : &DPAddressPressKey);
    char *keys[] = {&DPCatchingUpKey, &DPWantKey, &DPPressedKey, &DPNewTabPressKey, &DPAddressPressKey};
    for (size_t i = 0; i < sizeof(keys) / sizeof(*keys); i++) DPSet(window, keys[i], nil);
    if (!pressed || want == have) return;  // Pressed again only for presses made while waiting, so nothing Dia never shows loops.
    if (want == DPNoBar) return DPCancelCommandBar(DPGet(window, &DPOverlayKey));
    if (!press || !window.isKeyWindow) return;
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:press.modifierFlags timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:window.windowNumber context:nil characters:press.characters charactersIgnoringModifiers:press.charactersIgnoringModifiers
                                     isARepeat:NO keyCode:press.keyCode] atStart:NO];
}
