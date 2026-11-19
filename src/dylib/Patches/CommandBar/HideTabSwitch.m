#import "Patches/CommandBar/HideTab.h"

static char DPLeavingKey;

BOOL DPSwitchingTo(NSView *background) {
    NSString *leaving = DPGet(background.window, &DPLeavingKey), *tab = leaving && DPIsKind(background.superview, DPDiaTabView) && DPDrawnSelected(background) ? DPStripTabID(background.superview) : nil;
    return tab && ![tab isEqual:leaving];
}

static void DPEndSwitchFrom(NSWindow *window, NSString *leaving) {
    if (!leaving || ![DPGet(window, &DPLeavingKey) isEqual:leaving]) return;
    DPSet(window, &DPLeavingKey, nil);
    DPStandInFor(window, nil);
}

void DPEndSwitch(NSWindow *window) { DPEndSwitchFrom(window, DPGet(window, &DPLeavingKey)); }

void DPStandInWhileSwitching(NSWindow *window, NSString *tabID, NSString *leaving) {
    if (!window || !tabID || !leaving) return;
    DPSet(window, &DPLeavingKey, leaving);
    for (NSView *background in DPFindViews(DPDiaTabBackground))  // Dia has switched already.
        if (background.window == window && DPSwitchingTo(background)) return DPEndSwitchFrom(window, leaving);
    DPStandInFor(window, tabID);
    __weak NSWindow *weak = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPEndSwitchFrom(weak, leaving); });
}
