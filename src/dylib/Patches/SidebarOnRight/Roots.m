#import "SidebarOnRight.h"

static NSMapTable<NSView *, NSView *> *DPSidebars;  // Each root, and the sidebar it was found for.
static NSMapTable<NSView *, NSView *> *DPRoots;     // Each sidebar, and its root.
static NSHashTable<NSView *> *DPChain;              // Views between a root and the sidebar or a page.
static Class DPBackground;

static NSView *DPSidebarOf(NSView *root) {
    NSView *sidebar = [DPSidebars objectForKey:root];
    return root.window && sidebar.window == root.window ? sidebar : nil;
}

// The root a view is mirrored in: its superview's, for the root's own subviews, the chain and the window background's tiles.
NSView *DPRootFor(NSView *view) {
    NSView *parent = view.superview;
    if (!parent || !([DPChain containsObject:view] || [DPSidebars objectForKey:parent] || (DPBackground && [parent isKindOfClass:DPBackground]))) return nil;
    for (NSView *up = parent; up; up = up.superview)
        if ([DPSidebars objectForKey:up]) return DPSidebarOf(up) ? up : nil;
    return nil;
}

// A new page or floating sidebar joins its window's chain, and the views above it move over.
void DPJoinChain(NSView *view) {
    if (!DPSidebarOnRight.on || [DPChain containsObject:view]) return;
    NSView *root = view.superview;
    while (root && ![DPSidebars objectForKey:root]) root = root.superview;
    if (!DPSidebarOf(root)) return;
    for (NSView *v = view; v && v != root; v = v.superview) {
        [DPChain addObject:v];
        if (v != view) v.frame = v.frame;
    }
}

static void DPCollect(NSView *view, const char *className, NSMutableArray<NSView *> *found) {
    if (DPIsKind(view, className)) [found addObject:view];
    for (NSView *sub in view.subviews) DPCollect(sub, className, found);
}

// The root is the closest view holding the sidebar and every page. Found again only when the sidebar moves, or when forced.
void DPRegisterSidebar(NSView *sidebar, BOOL force) {
    NSWindow *window = sidebar.window;
    NSView *root = [DPRoots objectForKey:sidebar];
    if (!force && root && [sidebar isDescendantOf:root] && DPSidebarOf(root) == sidebar) return;
    root = sidebar.superview;
    if (!window || !root) return;
    NSMutableArray<NSView *> *targets = [NSMutableArray arrayWithObject:sidebar];
    DPCollect(window.contentView, DPDiaContentContainer, targets);
    DPCollect(window.contentView, DPDiaFloatingSidebar, targets);
    for (NSView *target in targets) while (root && ![target isDescendantOf:root]) root = root.superview;
    if (!root) return;
    [DPSidebars setObject:sidebar forKey:root];
    [DPRoots setObject:root forKey:sidebar];
    for (NSView *target in targets)
        for (NSView *v = target; v && v != root; v = v.superview) [DPChain addObject:v];
    for (NSView *v in root.subviews) v.frame = v.frame;
    for (NSView *v in DPChain.allObjects) if ([v isDescendantOf:root]) v.frame = v.frame;
    NSMutableArray<NSView *> *backgrounds = [NSMutableArray new];
    if (DPBackground) DPCollect(root, DPDiaWindowBackground, backgrounds);
    for (NSView *background in backgrounds) for (NSView *tile in background.subviews) tile.frame = tile.frame;
}

BOOL DPHasSidebarIn(NSWindow *window) {
    for (NSView *root in DPSidebars.keyEnumerator.allObjects) if (root.window == window && DPSidebarOf(root)) return YES;
    return NO;
}

NSView *DPDockedSidebarIn(NSWindow *window) {
    for (NSView *root in DPSidebars.keyEnumerator.allObjects) {
        NSView *sidebar = root.window == window ? DPSidebarOf(root) : nil;
        BOOL floating = NO;
        for (NSView *up = sidebar; up; up = up.superview) floating |= DPIsKind(up, DPDiaFloatingSidebar);
        if (sidebar && !floating && !sidebar.hiddenOrHasHiddenAncestor) return sidebar;
    }
    return nil;
}

void DPInstallRoots(void) {
    DPSidebars = [NSMapTable weakToWeakObjectsMapTable];
    DPRoots = [NSMapTable weakToWeakObjectsMapTable];
    DPChain = [NSHashTable weakObjectsHashTable];
    DPBackground = objc_getClass(DPDiaWindowBackground);
}
