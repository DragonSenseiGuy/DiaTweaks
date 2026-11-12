#import "StdPatch/Hide.h"
#import "Patches/SidebarOnRight/SidebarOnRight.h"

extern DPPatch DPHideTrafficLights;
static const CGFloat DPPinnedTabsInset = 6;
static char DPLightsKey, DPStackFrameKey;

static BOOL DPIsTrafficLights(NSView *view) { return DPIsKind(view, DPDiaTrafficLights); }

// Sidebar on Right moves the buttons out of the sidebar to the window's corner, so the header lays out without them too.
static BOOL DPLightsOut(NSView *header) { return DPHideTrafficLights.on || DPSidebarOnRightTakesLights(header.window); }

static NSRect DPLaidOutStack(NSView *stack) { return [DPDiaValue(stack, &DPStackFrameKey, @(stack.frame)) rectValue]; }

// The header's stack keeps room for hidden views. Out of the stack, the lights aren't subviews, so the header holds them.
// Without the lights the profile button lines up with the pinned tabs, keeping its right edge.
static void DPSidebarHeader_layout(NSView *self, SEL _cmd) {
    NSView *lights = DPFindView(self, ^BOOL(NSView *view) { return DPIsTrafficLights(view); });
    if (lights) DPSet(self, &DPLightsKey, @[ lights, lights.superview ]);
    NSArray *held = DPGet(self, &DPLightsKey);
    NSStackView *stack = held.lastObject;
    if (![stack isKindOfClass:NSStackView.class]) return DPCallOriginal(DPSidebarHeader_layout, self);
    [stack setVisibilityPriority:DPLightsOut(self) ? NSStackViewVisibilityPriorityNotVisible : NSStackViewVisibilityPriorityMustHold forView:held.firstObject];
    DPCallOriginal(DPSidebarHeader_layout, self);
    if (!DPMayAdjust(stack)) return;
    NSRect laidOut = DPLaidOutStack(stack), frame = laidOut;
    if (DPLightsOut(self) && NSMinX(laidOut) > DPPinnedTabsInset) {
        frame.origin.x = DPPinnedTabsInset;
        frame.size.width = NSMaxX(laidOut) - DPPinnedTabsInset;
    }
    DPOverride(stack, &DPStackFrameKey, @(laidOut), @(frame));
    stack.frame = frame;
}

static void DPInstallHideTrafficLights(void) { DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPSidebarHeader_layout); }

static NSString *DPVerifyHideTrafficLights(DPPatch *patch) {
    NSString *problem = DPVerifyHides(patch);
    if (problem) return problem;
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        NSStackView *stack = [DPGet(header, &DPLightsKey) lastObject];
        if (![stack isKindOfClass:NSStackView.class] || header.hiddenOrHasHiddenAncestor) continue;
        NSRect laidOut = DPLaidOutStack(stack);
        BOOL out = patch->on || DPSidebarOnRightTakesLights(header.window);
        CGFloat left = out ? MIN(NSMinX(laidOut), DPPinnedTabsInset) : NSMinX(laidOut);
        if (fabs(NSMinX(stack.frame) - left) > 0.5) return out ? @"profile button isn't in line with the pinned tabs" : @"profile button moved";
        if (fabs(NSMaxX(stack.frame) - NSMaxX(laidOut)) > 0.5) return @"header buttons moved";
    }
    return nil;
}

DP_PATCH(DPHideTrafficLights) {
    .key = @"hideTrafficLights",
    .order = 98,
    .title = @"Hide Window Controls",
    .detail = @"Hide the close, minimize and zoom buttons. ⌘W, ⌘M and the Window menu still work.",
    .symbol = @"ellipsis",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaTrafficLights, DPDiaSidebarHeader),
    .hides = DPIsTrafficLights,
    .install = DPInstallHideTrafficLights,
    .verify = DPVerifyHideTrafficLights,
};
