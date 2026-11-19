#import "HideToolbar.h"

static char DPPermissionToolbarKey;

BOOL DPToolbarHasPermissionRequest(DPToolbarHover *hover) {
    return hover.permissionPopovers.anyObject != nil;
}

static DPToolbarHover *DPToolbarForAnchor(NSView *anchor) {
    for (NSView *view = anchor; view; view = view.superview)
        if (DPIsKind(view, DPDiaContentPane)) return [DPToolbarHover attachToPane:view];
    return nil;
}

static void DPTrackPermissionPopover(NSPopover *popover, DPToolbarHover *hover) {
    DPToolbarHover *previous = DPGet(popover, &DPPermissionToolbarKey);
    if (previous == hover) return;
    [previous.permissionPopovers removeObject:popover];
    if (hover && !hover.permissionPopovers) hover.permissionPopovers = [NSHashTable weakObjectsHashTable];
    [hover.permissionPopovers addObject:popover];
    DPSet(popover, &DPPermissionToolbarKey, hover);

    if (DPHideToolbar.on || DPHideToolbar.progress > 0) {
        if (previous.pane) DPApplyToolbar(previous.pane);
        if (hover.pane) DPApplyToolbar(hover.pane);
    }
}

static void DPPermissionPopover_show(NSPopover *self, SEL _cmd, NSRect rect, NSView *anchor, NSRectEdge edge) {
    // AppKit positions the popover synchronously against Dia's site menu button.
    DPTrackPermissionPopover(self, DPToolbarForAnchor(anchor));
    DPCallOriginal(DPPermissionPopover_show, self, rect, anchor, edge);
    if (!self.isShown) DPTrackPermissionPopover(self, nil);
}

static void DPPermissionPopover_didClose(NSPopover *self, SEL _cmd, NSNotification *note) {
    DPCallOriginal(DPPermissionPopover_didClose, self, note);
    DPTrackPermissionPopover(self, nil);
}

void DPInstallToolbarPermissionReveal(void) {
    Class popover = objc_getClass(DPDiaWebsitePermissionPopover);
    SEL show = @selector(showRelativeToRect:ofView:preferredEdge:), close = @selector(popoverDidClose:);
    if (!class_getInstanceMethod(popover, show) || !class_getInstanceMethod(popover, close)) return;
    DPHookClass(popover, show, (IMP)DPPermissionPopover_show);
    DPHookClass(popover, close, (IMP)DPPermissionPopover_didClose);
}
