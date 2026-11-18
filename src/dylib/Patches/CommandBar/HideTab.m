#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/CommandBarOverlay.h"

extern DPPatch DPCommandBar;

static NSMutableSet<NSString *> *DPHidden, *DPParked;
static NSMapTable<NSString *, NSWindow *> *DPOwner;  // Each hidden tab's window, weakly: a window that goes takes its hidden tabs with it.
static __weak NSWindow *DPExpectWindow;
static CFTimeInterval DPExpectUntil;
static NSSet<NSString *> *DPKnown;  // The window's tabs when a new one was asked for.

BOOL DPHiding(void) { return DPCommandBar.on && DPCommandBarHideTab.on && !DPCommandBarHideTab.unavailable; }
static BOOL DPExpecting(void) { return CACurrentMediaTime() < DPExpectUntil; }

// A tab whose window has gone isn't hidden any more.
static BOOL DPOwned(NSString *tab) {
    if ([DPOwner objectForKey:tab]) return YES;
    [DPHidden removeObject:tab];
    [DPParked removeObject:tab];
    return NO;
}

// A parked tab is hidden with no bar open, so the lists close up around it rather than hold still.
BOOL DPHidingATab(NSWindow *window) {
    if (!DPHiding()) return NO;
    for (NSString *tab in DPHidden.allObjects)
        if (DPOwned(tab) && ![DPParked containsObject:tab] && (!window || [DPOwner objectForKey:tab] == window)) return YES;
    return DPExpecting() && (!window || DPExpectWindow == window);
}

BOOL DPParksTab(NSString *tab) { return DPHidesTab(tab) && [DPParked containsObject:tab]; }

BOOL DPParkingAny(void) {
    if (!DPHiding()) return NO;
    for (NSString *tab in DPParked.allObjects) if (DPOwned(tab)) return YES;
    return NO;
}

void DPHideBlank(NSString *tabID, BOOL hidden, NSWindow *window) {
    if (!tabID || !window || (hidden ? !DPHiding() : ![DPHidden containsObject:tabID])) return;
    if (hidden) {
        [DPHidden addObject:tabID];
        [DPOwner setObject:window forKey:tabID];
    } else {
        [DPHidden removeObject:tabID];
        [DPOwner removeObjectForKey:tabID];
    }
    DPParkTab(tabID, hidden);
}

void DPParkTab(NSString *tabID, BOOL parked) {
    if (!tabID) return;
    if (parked) [DPParked addObject:tabID];
    else [DPParked removeObject:tabID];
    DPRelayoutLists();
}

BOOL DPHidesTab(NSString *tab) {
    if (!DPHiding() || !tab) return NO;
    if ([DPHidden containsObject:tab]) return DPOwned(tab);
    return DPExpecting() && DPKnown && ![DPKnown containsObject:tab];
}

void DPExpectNewTab(NSWindow *window) {
    if (!DPHiding() || (DPExpecting() && DPExpectWindow == window)) return;  // The key and the menu item it chooses both ask.
    // Every window's, so one waiting for its own new tab doesn't take another's tabs for new.
    NSMutableSet *known = [NSMutableSet setWithArray:DPListedTabs(nil)];
    for (id scripted in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"])
        for (id tab in [scripted valueForKey:@"appleScriptTabs"]) [known addObject:DPTabID(tab) ?: @""];
    for (NSView *tab in DPFindViews(DPDiaTabView)) [known addObject:DPStripTabID(tab) ?: @""];
    DPKnown = known;
    DPExpectWindow = window;
    CFTimeInterval until = DPExpectUntil = CACurrentMediaTime() + 1;
    DPFreezeLists(window);
    DPHoldStrips(window);
    // A new tab the bar doesn't open over, such as one in a split, shows once the wait is over.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC + 10 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (DPExpectUntil == until) DPStopExpecting();
    });
}

void DPStopExpecting(void) {
    if (!DPExpectUntil) return;
    DPExpectUntil = 0;
    DPKnown = nil;
    DPRelayoutLists();
}

// Only a tab made for the bar is ever hidden: one asked for in this window just now, and not there before. A tab that
// came some way not seen coming, or was already open, stays in the list.
void DPHideTabRow(NSString *tabID, NSWindow *window) {
    if (!tabID || !window || !DPHiding() || !DPExpecting() || DPExpectWindow != window || !DPKnown || [DPKnown containsObject:tabID]) return;
    [DPHidden addObject:tabID];
    [DPOwner setObject:window forKey:tabID];
    DPExpectUntil = 0;
    DPKnown = nil;
    DPFreezeLists(window);
    DPHoldStrips(window);
    DPRelayoutLists();
}

void DPShowTabRow(NSString *tabID, BOOL closing) {
    if (!tabID || ![DPHidden containsObject:tabID]) return;
    // A tab being closed stays hidden until it's gone, so it doesn't come back on the way out.
    if (closing) return (void)dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPShowTabRow(tabID, NO); });
    [DPHidden removeObject:tabID];
    [DPParked removeObject:tabID];
    [DPOwner removeObjectForKey:tabID];
    DPRelayoutLists();
}

// A window that closes, or goes full screen and lists its tabs afresh, takes its bar and hidden tabs with it.
void DPForgetWindow(NSWindow *window) {
    BOOL had = DPExpectWindow == window && DPExpectUntil;
    if (had) DPExpectUntil = 0, DPKnown = nil;
    for (NSString *tab in DPOwner.keyEnumerator.allObjects) {
        if ([DPOwner objectForKey:tab] != window) continue;
        [DPHidden removeObject:tab];
        [DPParked removeObject:tab];
        [DPOwner removeObjectForKey:tab];
        had = YES;
    }
    if (had) DPRelayoutLists();
}

static void DPApplyHideTab(DPPatch *patch) {
    for (NSView *background in DPFindViews(DPDiaTabBackground)) DPNoteLook(background);
    if (!DPHiding()) {
        DPReleaseStrips();
        DPShowHiddenBars();
    }
    DPRelayoutLists();
    DPRefreshStandIns();
}

static NSString *DPVerifyHideTab(DPPatch *patch) { return DPVerifyHiddenRows(); }

// Full screen lists the tabs afresh, as a new tab layout does, so a bar over a hidden tab closes.
static void DPCloseBar(NSWindow *window) {
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (overlay.openedTab && DPHidesTab(DPTabID(overlay.openedTab))) DPCancelCommandBar(overlay);
}

static void DPInstallHideTab(void) {
    if (!DPSelectionLayoutKnown()) {
        DPCommandBarHideTab.unavailable = YES;
        DPCommandBarHideTab.on = NO;
        NSLog(@"DiaPatches: Hide New Tab Until Opened doesn't know how this Dia lays out a tab's selection, so it stays off");
        return;
    }
    DPHidden = [NSMutableSet set];
    DPParked = [NSMutableSet set];
    DPOwner = [NSMapTable strongToWeakObjectsMapTable];
    DPInstallFrozenLists();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // The New Tab menu item, however it's chosen, before it makes the tab.
    [center addObserverForName:NSMenuWillSendActionNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSMenuItem *item = note.userInfo[@"MenuItem"];
        if ([item.title isEqualToString:@"New Tab"] && NSApp.keyWindow) DPExpectNewTab(NSApp.keyWindow);
    }];
    [center addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPForgetWindow(note.object); }];
    for (NSNotificationName name in @[ NSWindowWillEnterFullScreenNotification, NSWindowWillExitFullScreenNotification ])
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) { DPCloseBar(note.object); }];
    DPInstallHiddenStripTab();
    DPInstallStandIn();
    DPInstallPress();
}

DP_PATCH(DPCommandBarHideTab) {
    .key = @"commandBarHideTab",
    .order = 94,
    .title = @"Hide New Tab Until Opened",
    .detail = @"Keep the new tab out of the sidebar and the tab bar while the command bar is open. The New Tab button shows as selected instead, and clicking it again closes the bar. The tab shows once you choose a result. Experimental.",
    .symbol = @"eye.slash.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabListCollection, DPDiaTabListLayout, DPDiaTabStripTabs, DPDiaTabView, DPDiaTabContentView, DPDiaTabBackground, DPDiaNewTabButton, DPDiaTabSurfaceButton),
    .install = DPInstallHideTab,
    .apply = DPApplyHideTab,
    .verify = DPVerifyHideTab,
};
