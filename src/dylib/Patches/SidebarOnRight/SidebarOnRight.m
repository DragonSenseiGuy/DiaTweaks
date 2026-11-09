#import "SidebarOnRight.h"

static void DPSidebar_viewDidLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPSidebar_viewDidLayout, self);
    if (DPSidebarOnRight.on) DPRegisterSidebar(self.view, NO);
}

static void DPInstallSidebarOnRight(void) {
    DPHook(DPDiaSidebarController, @selector(viewDidLayout), (IMP)DPSidebar_viewDidLayout);
    DPInstallMirror();
    DPInstallResize();
    DPInstallHover();
}

// The sidebar slides across instead of jumping.
static void DPApplySidebarOnRight(DPPatch *patch) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.25;
        context.allowsImplicitAnimation = YES;
        if (!patch->on) return DPUnmirrorWindows();
        for (NSView *header in DPFindViews(DPDiaSidebarHeader)) DPRegisterSidebar(header.superview, YES);
    }];
}

static BOOL DPFloating(NSView *view) {
    for (NSView *up = view; up; up = up.superview) if (DPIsKind(up, DPDiaFloatingSidebar)) return YES;
    return NO;
}

// A sidebar slid out of the window, or tabs at the top, pass. A docked one must sit beside the pages, not under them.
static NSString *DPVerifySidebarOnRight(DPPatch *patch) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        NSView *sidebar = header.superview;
        NSWindow *window = sidebar.window;
        if (!window || sidebar.hiddenOrHasHiddenAncestor) continue;
        NSRect s = [sidebar convertRect:sidebar.bounds toView:nil];
        CGFloat width = NSWidth(window.frame), left = NSMinX(s), right = width - NSMaxX(s);
        if (NSWidth(s) < 1 || NSMaxX(s) <= 0 || NSMinX(s) >= width) continue;
        if (patch->on && right > left) return @"the sidebar is on the left";
        if (!patch->on && left > right) return @"the sidebar is on the right";
        if (DPFloating(sidebar)) continue;
        for (NSView *container in DPFindViews(DPDiaContentContainer)) {
            if (container.window != window || container.hiddenOrHasHiddenAncestor) continue;
            NSRect c = [container convertRect:container.bounds toView:nil];
            if (patch->on ? NSMaxX(c) > NSMinX(s) + 0.5 : NSMinX(c) < NSMaxX(s) - 0.5) return @"the page overlaps the sidebar";
        }
    }
    return nil;
}

DP_PATCH(DPSidebarOnRight) {
    .key = @"sidebarOnRight",
    .order = 77,
    .title = @"Sidebar on Right",
    .detail = @"Move the sidebar to the right side of the window. It opens, closes and resizes from there.",
    .symbol = @"sidebar.right",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaSidebarController, DPDiaSidebarHeader, DPDiaContentContainer, DPDiaWindow),
    .install = DPInstallSidebarOnRight,
    .apply = DPApplySidebarOnRight,
    .verify = DPVerifySidebarOnRight,
};
