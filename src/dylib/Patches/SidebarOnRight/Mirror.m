#import "SidebarOnRight.h"

static NSHashTable<NSView *> *DPMirrored;   // Views off Dia's x, to put back when the patch turns off.
static __unsafe_unretained NSView *DPBusy;  // The view these hooks are setting, so its nested calls pass through.
static char DPXKey;
static void (*DPSetFrame)(id, SEL, NSRect);
static void (*DPSetFrameOrigin)(id, SEL, NSPoint);
static void (*DPSetFrameSize)(id, SEL, NSSize);

CGFloat DPMirroredX(NSView *superview, CGFloat x, CGFloat width) {
    NSRect bounds = superview.bounds;
    return NSMinX(bounds) + NSMaxX(bounds) - x - width;
}

// Where the view goes. Only our own frame set again (by AppKit or a re-layout) keeps Dia's last x; any other frame is
// Dia's. An x alone can't tell: a page that fills the window as the sidebar closes has the x we gave it beside the sidebar.
static NSRect DPMirrorFrame(NSView *view, NSRect frame, BOOL keepX) {
    if (!DPSidebarOnRight.on || view == DPBusy || !DPRootFor(view)) return frame;
    NSArray *last = DPGet(view, &DPXKey);
    BOOL ours = last && (keepX || NSEqualRects([last[1] rectValue], frame));
    CGFloat dia = ours ? [last[0] doubleValue] : NSMinX(frame), x = DPMirroredX(view.superview, dia, NSWidth(frame));
    if (x != NSMinX(frame) && !DPMayAdjust(view)) return frame;
    frame.origin.x = x;
    DPSet(view, &DPXKey, @[ @(dia), [NSValue valueWithRect:frame] ]);
    [DPMirrored addObject:view];
    return frame;
}

// Another patch's hook may move the edges after ours, so what counts as our frame is the one the view ends up with.
static void DPRemember(NSView *view) {
    NSArray *last = DPSidebarOnRight.on ? DPGet(view, &DPXKey) : nil;
    if (last && !NSEqualRects([last[1] rectValue], view.frame)) DPSet(view, &DPXKey, @[ last[0], [NSValue valueWithRect:view.frame] ]);
}

static void DPView_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    frame = DPMirrorFrame(self, frame, NO);
    NSView *busy = DPBusy;
    DPBusy = self;
    DPSetFrame(self, _cmd, frame);
    DPBusy = busy;
    DPRemember(self);
}

static void DPView_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    if (DPSidebarOnRight.on && self != DPBusy) origin = DPMirrorFrame(self, (NSRect){origin, self.frame.size}, NO).origin;
    NSView *busy = DPBusy;
    DPBusy = self;
    DPSetFrameOrigin(self, _cmd, origin);
    DPBusy = busy;
    DPRemember(self);
}

// AppKit may set the size after the origin, so the left edge follows to keep the mirrored right edge in place.
static void DPView_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    BOOL ours = DPSidebarOnRight.on && self != DPBusy;
    NSView *busy = DPBusy;
    DPBusy = self;
    DPSetFrameSize(self, _cmd, size);
    DPBusy = busy;
    if (!ours || ![DPMirrored containsObject:self]) return;
    NSPoint origin = DPMirrorFrame(self, self.frame, YES).origin;
    DPBusy = self;
    DPSetFrameOrigin(self, @selector(setFrameOrigin:), origin);
    DPBusy = busy;
    DPRemember(self);
}

// The pages, the floating sidebar and the background tiles have setFrame: hooks of their own in other patches.
static void DPDiaView_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (!DPIsKind(self, DPDiaWindowBackgroundTile)) DPJoinChain(self);
    frame = DPMirrorFrame(self, frame, NO);
    NSView *busy = DPBusy;
    DPBusy = self;
    DPCallOriginal(DPDiaView_setFrame, self, frame);
    DPBusy = busy;
    DPRemember(self);
}

// Mirroring twice puts a view back, even where another patch has moved its edges since.
void DPUnmirrorWindows(void) {
    for (NSView *view in DPMirrored.allObjects) {
        BOOL mirrored = DPRootFor(view) != nil;
        DPSet(view, &DPXKey, nil);
        if (!mirrored) continue;
        NSRect frame = view.frame;
        frame.origin.x = DPMirroredX(view.superview, NSMinX(frame), NSWidth(frame));
        view.frame = frame;
    }
    [DPMirrored removeAllObjects];
}

void DPInstallMirror(void) {
    DPInstallRoots();
    DPMirrored = [NSHashTable weakObjectsHashTable];
    // Every frame change in the app comes through here, so they call what was there directly instead of looking it up.
    DPSetFrame = (void (*)(id, SEL, NSRect))method_getImplementation(class_getInstanceMethod(NSView.class, @selector(setFrame:)));
    DPSetFrameOrigin = (void (*)(id, SEL, NSPoint))method_getImplementation(class_getInstanceMethod(NSView.class, @selector(setFrameOrigin:)));
    DPSetFrameSize = (void (*)(id, SEL, NSSize))method_getImplementation(class_getInstanceMethod(NSView.class, @selector(setFrameSize:)));
    DPHookClass(NSView.class, @selector(setFrame:), (IMP)DPView_setFrame);
    DPHookClass(NSView.class, @selector(setFrameOrigin:), (IMP)DPView_setFrameOrigin);
    DPHookClass(NSView.class, @selector(setFrameSize:), (IMP)DPView_setFrameSize);
    for (const char *const *name = DPClasses(DPDiaContentContainer, DPDiaFloatingSidebar, DPDiaWindowBackgroundTile); *name; name++)
        if (objc_getClass(*name)) DPHook(*name, @selector(setFrame:), (IMP)DPDiaView_setFrame);
}
