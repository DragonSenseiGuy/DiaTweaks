#import "StdPatch/StdPatch.h"

extern DPPatch DPShowAddressField;

typedef void (*DPHoverHandler)(bool hovered, void *context __attribute__((swift_context))) __attribute__((swiftcall));

static id DPDelayedTracker(NSView *field) { return (__bridge id)*(void **)DPIvar(field, "hoverTracker"); }

static NSTrackingArea *DPHoverArea(NSView *field) {
    for (NSTrackingArea *area in field.trackingAreas)
        if (DPIsKind(area.owner, DPDiaHoverTracker)) return area;
    return nil;
}

static BOOL DPShowsHover(NSView *field) {
    id delayed = DPDelayedTracker(field);
    return delayed && *(BOOL *)DPIvar(delayed, "isHoverActive");
}

static void DPSetHover(NSView *field, BOOL hovered) {
    id delayed = DPDelayedTracker(field), tracker = DPHoverArea(field).owner;
    if (!delayed || !tracker) return;
    *(BOOL *)DPIvar(tracker, "isHovered") = hovered;
    *(BOOL *)DPIvar(delayed, "isHoverActive") = hovered;
    *(BOOL *)DPIvar(delayed, "isIncidentalHover") = NO;
    void **handler = DPIvar(delayed, "onUpdate");
    if (handler[0]) ((DPHoverHandler)handler[0])(hovered, handler[1]);
}

static Class DPAddressFieldClass;

static BOOL DPKeepsHover(id tracker) {
    if (!DPShowAddressField.on) return NO;
    id view = objc_loadWeak((__autoreleasing id *)DPIvar(tracker, "view"));
    return DPAddressFieldClass && [view isKindOfClass:DPAddressFieldClass];
}

static void DPTracker_mouseEntered(id self, SEL _cmd, NSEvent *event) {
    if (!DPKeepsHover(self)) DPCallOriginal(DPTracker_mouseEntered, self, event);
}
static void DPTracker_mouseMoved(id self, SEL _cmd, NSEvent *event) {
    if (!DPKeepsHover(self)) DPCallOriginal(DPTracker_mouseMoved, self, event);
}
static void DPTracker_mouseExited(id self, SEL _cmd, NSEvent *event) {
    if (!DPKeepsHover(self)) DPCallOriginal(DPTracker_mouseExited, self, event);
}

static void DPField_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPField_layout, self);
    if (DPShowAddressField.on && !DPShowsHover(self)) DPSetHover(self, YES);
}

// Hide Toolbar lifts the invisible bar above the pane, where a bounds check still catches a pointer outside the pane.
static BOOL DPPointerOver(NSView *field) {
    NSWindow *window = field.window;
    NSView *content = window.contentView;
    if (!window.isKeyWindow || !content || field.hiddenOrHasHiddenAncestor) return NO;
    for (NSView *view = field; view; view = view.superview) if (view.alphaValue <= 0.01) return NO;
    NSPoint point = content.superview ? [content.superview convertPoint:window.mouseLocationOutsideOfEventStream fromView:nil]
                                      : window.mouseLocationOutsideOfEventStream;
    return [[content hitTest:point] isDescendantOf:field];
}

static void DPApplyShowAddressField(DPPatch *patch) {
    for (NSView *field in DPFindViews(DPDiaAddressField)) DPSetHover(field, patch->on || DPPointerOver(field));
}

static NSString *DPVerifyShowAddressField(DPPatch *patch) {
    for (NSView *field in DPFindViews(DPDiaAddressField)) {
        if (field.hiddenOrHasHiddenAncestor || !DPHoverArea(field)) continue;
        if (patch->on && !DPShowsHover(field)) return @"address field hides its background and buttons";
        if (!patch->on && DPShowsHover(field) && !DPPointerOver(field)) return @"address field stays highlighted";
    }
    return nil;
}

static void DPInstallShowAddressField(void) {
    DPAddressFieldClass = objc_getClass(DPDiaAddressField);
    DPHook(DPDiaHoverTracker, @selector(mouseEntered:), (IMP)DPTracker_mouseEntered);
    DPHook(DPDiaHoverTracker, @selector(mouseMoved:), (IMP)DPTracker_mouseMoved);
    DPHook(DPDiaHoverTracker, @selector(mouseExited:), (IMP)DPTracker_mouseExited);
    DPHook(DPDiaAddressField, @selector(layout), (IMP)DPField_layout);
}

DP_PATCH(DPShowAddressField) {
    .key = @"showAddressField",
    .order = 48,
    .title = @"Always Show Address Field",
    .detail = @"Show the address field’s background and its bookmark, split view and site buttons without pointing at it.",
    .symbol = @"link.circle.fill",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaAddressField, DPDiaHoverTracker),
    .disabledBy = @"hideToolbar",
    .install = DPInstallShowAddressField,
    .apply = DPApplyShowAddressField,
    .verify = DPVerifyShowAddressField,
};
