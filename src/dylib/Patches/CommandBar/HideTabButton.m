#import "Patches/CommandBar/HideTab.h"

static char DPTabKey, DPSavedKey;

BOOL DPIsNewTabButton(NSView *view) {
    return DPIsKind(view, DPDiaNewTabButton) || (DPIsKind(view, DPDiaTabSurfaceButton) && DPIsKind(view.superview, DPDiaTabStripTabs));
}

static BOOL DPStandingIn(NSWindow *window) { return DPHidesTab(DPGet(window, &DPTabKey)); }

static void DPSelectButton(NSView *background, BOOL selected) {
    uintptr_t *style = DPSelectionStyle(background);
    uint8_t *shape = DPTabShape(background);
    NSArray *saved = DPGet(background, &DPSavedKey);
    if (!style || !shape || selected == (saved != nil)) return;
    if (selected) {
        NSArray *look = DPSelectedLook(background.superview);
        if (!look || DPStyleSelected(*style)) return;
        uintptr_t original = *style;
        *style = look[0] == NSNull.null ? 0 : (uintptr_t)CFBridgingRetain(look[0]);
        uint8_t was = *shape;
        *shape = [look[1] unsignedCharValue];
        // Retain look[0] in saved so its pointer address can't be reused before restore.
        DPSet(background, &DPSavedKey, @[ @(original), @(was), @(*style), @(*shape), look[0] ]);
    } else {
        DPSet(background, &DPSavedKey, nil);
        // Release only if Dia hasn't overwritten the style with one it owns.
        if (*style == [saved[2] unsignedLongValue]) {
            if (*style >= DPFirstFill) CFRelease((CFTypeRef)(void *)*style);
            *style = [saved[0] unsignedLongValue];
        }
        if (*shape == [saved[3] unsignedCharValue]) *shape = [saved[1] unsignedCharValue];
    }
    DPTabShapeView(background).needsLayout = YES;
    background.needsLayout = background.needsDisplay = YES;
}

static void DPSelectButtons(NSWindow *window) {
    BOOL standingIn = DPStandingIn(window);
    for (NSView *background in DPFindViews(DPDiaTabBackground))
        if (background.window == window && DPIsNewTabButton(background.superview)) DPSelectButton(background, standingIn);
}

static void DPHideFrontTab(NSView *background) {
    BOOL standingIn = DPStandingIn(background.window), front = standingIn && DPDrawnSelected(background) && DPIsKind(background.superview, DPDiaTabView);
    if (DPSwitchingTo(background)) return;
    DPUnselectFrontTab(background, standingIn);
    if (front) DPSelectButtons(background.window);
}

static void DPRefresh(NSWindow *window) {
    NSArray<NSView *> *backgrounds = DPFindViews(DPDiaTabBackground);
    BOOL standingIn = DPStandingIn(window);
    for (NSView *background in backgrounds)
        if (background.window == window && DPIsNewTabButton(background.superview)) DPSelectButton(background, standingIn);
    for (NSView *background in backgrounds) {
        if (background.window != window || !DPIsKind(background.superview, DPDiaTabView)) continue;
        if (!standingIn) DPGiveBackSelection(background);
        else if (DPDrawnSelected(background)) {
            DPHideFrontTab(background);
            DPTabShapeView(background).needsLayout = YES;
            background.needsLayout = background.needsDisplay = YES;
        }
    }
}

void DPStandInFor(NSWindow *window, NSString *tabID) {
    if (!window) return;
    DPSet(window, &DPTabKey, tabID);
    DPRefresh(window);
}

void DPStandInForTab(NSWindow *window, NSString *tabID) {
    if (window && [DPGet(window, &DPTabKey) isEqual:tabID]) DPStandInFor(window, nil);
}

void DPRefreshStandIns(void) {
    for (NSWindow *window in NSApp.windows) DPRefresh(window);
}

static void DPTabBackground_updateLayer(NSView *self, SEL _cmd) {
    if (!DPHiding()) return DPCallOriginal(DPTabBackground_updateLayer, self);
    DPNoteLook(self);
    if (DPSwitchingTo(self)) DPEndSwitch(self.window);
    DPHideFrontTab(self);
    DPCallOriginal(DPTabBackground_updateLayer, self);
}

static void DPTabBackground_layout(NSView *self, SEL _cmd) {
    if (!DPHiding()) return DPCallOriginal(DPTabBackground_layout, self);
    DPHideFrontTab(self);
    DPCallOriginal(DPTabBackground_layout, self);
    if (DPIsNewTabButton(self.superview)) DPSelectButton(self, DPStandingIn(self.window));
}

NSString *DPVerifyStandIn(NSWindow *window, NSString *tabID) {
    BOOL standingIn = DPHidesTab(tabID);
    for (NSView *background in DPFindViews(DPDiaTabBackground)) {
        if (background.window != window || background.isHiddenOrHasHiddenAncestor) continue;
        if (DPIsNewTabButton(background.superview)) {
            if (standingIn && !DPDrawnSelected(background) && DPSelectedLook(background.superview)) return @"the New Tab button isn't selected while the new tab is hidden";
            if (!standingIn && DPGet(background, &DPSavedKey)) return @"the New Tab button stays selected once the bar closes";
        } else if (DPIsKind(background.superview, DPDiaTabView)) {
            if (standingIn && DPDrawnSelected(background)) return @"the tab in front still looks selected behind the bar";
            if (!standingIn && DPHoldsSelection(background)) return @"the tab in front doesn't look selected once the bar closes";
        }
    }
    return nil;
}

void DPInstallStandIn(void) {
    DPHook(DPDiaTabBackground, @selector(updateLayer), (IMP)DPTabBackground_updateLayer);
    DPHook(DPDiaTabBackground, @selector(layout), (IMP)DPTabBackground_layout);
    DPInstallFrontTab();
}
