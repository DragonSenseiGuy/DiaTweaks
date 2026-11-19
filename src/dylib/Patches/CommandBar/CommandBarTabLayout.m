#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/HideTab.h"

static char DPRefocusKey;

BOOL DPInTabLayout(NSView *view) {
    for (; view; view = view.superview) {
        const char *name = object_getClassName(view);
        if (strstr(name, "TabSidebar") || strstr(name, "TabStrip")) return YES;
    }
    return NO;
}

NSEvent *DPTabLayoutMouseDown(DPCommandBarOverlay *overlay, NSEvent *event) {
    if ([overlay.panel hitTest:[overlay convertPoint:event.locationInWindow fromView:nil]]) return event;  // In the bar, which may lie over the sidebar.
    NSView *under = [overlay viewUnder:[overlay.superview convertPoint:event.locationInWindow fromView:nil]];
    NSView *button = under, *tabView = under;
    while (button && !DPIsNewTabButton(button)) button = button.superview;
    while (tabView && !DPIsKind(tabView, DPDiaTabView)) tabView = tabView.superview;
    if (!DPInTabLayout(under) || (button && DPHidesTab(DPTabID(overlay.openedTab)))) return event;
    BOOL onFront = tabView && overlay.returnTab && [DPStripTabID(tabView) isEqual:DPTabID(overlay.returnTab)];
    if (onFront && event.clickCount < 2) {
        if (event.type == NSEventTypeLeftMouseDown) DPSet(overlay, &DPRefocusKey, @YES);
        dispatch_async(dispatch_get_main_queue(), ^{ DPFocusBar(overlay); });
        return event;
    }
    NSWindow *window = overlay.host;
    NSString *tab = DPTabID(overlay.openedTab), *front = DPActiveTabID(window);
    DPCancelCommandBar(overlay);
    if (onFront) return nil;  // Not on to Dia, which would take it as a double click and rename the tab.
    // Only a tab or a favorite is switched to; the sidebar's empty space and its buttons aren't.
    NSView *favorite = under;
    while (favorite && !strstr(object_getClassName(favorite), "TabDockItemView")) favorite = favorite.superview;
    if (event.type == NSEventTypeLeftMouseDown && (tabView || favorite)) DPStandInWhileSwitching(window, tab, front);
    return event;
}

// Dia may give the page the keyboard as the tab the bar is over is clicked.
void DPTabLayoutMouseUp(DPCommandBarOverlay *overlay) {
    if (!DPGet(overlay, &DPRefocusKey)) return;
    DPSet(overlay, &DPRefocusKey, nil);
    dispatch_async(dispatch_get_main_queue(), ^{ DPFocusBar(overlay); });
}
