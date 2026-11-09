#import "SidebarOnRight.h"

// Dia reveals the hidden sidebar when the pointer reaches the window's left edge, checking where the pointer is now as
// mouse-moved events arrive. So while the sidebar is hidden, the pointer at either edge, or over the
// revealed sidebar, is mirrored for all of them: the right edge opens it, the left one doesn't, and it stays out.
static const CGFloat DPEdge = 6;

static NSWindow *DPDiaWindowAt(NSPoint screen) {
    Class dia = objc_getClass(DPDiaWindow);
    for (NSWindow *window in NSApp.windows)
        if (window.visible && dia && [window isKindOfClass:dia] && NSPointInRect(screen, NSInsetRect(window.frame, -2, -2))) return window;
    return nil;
}

// In compact mode Dia may keep the docked sidebar unhidden but squeezed or off the window, so it counts as open only
// when a usable width of it shows.
static BOOL DPDockedOpenIn(NSWindow *window) {
    NSView *docked = DPDockedSidebarIn(window);
    if (!docked) return NO;
    NSRect shown = NSIntersectionRect([docked convertRect:docked.bounds toView:nil], window.contentView.bounds);
    return NSWidth(shown) >= 20;
}

// The floating sidebar Dia slides out, while the docked one is closed: the one already mirrored, else the outermost one,
// which joins now so even the first reveal comes from the right. Before Dia makes one, the window's content view stands
// in, so the edges still mirror. Nil when there's nothing to mirror.
static NSView *DPFloatingIn(NSWindow *window) {
    if (!window || !DPHasSidebarIn(window) || DPDockedOpenIn(window)) return nil;
    NSView *outermost = nil;
    for (NSView *f in DPFindViews(DPDiaFloatingSidebar)) {
        if (f.window != window) continue;
        if (DPRootFor(f)) return f;
        BOOL nested = NO;
        for (NSView *up = f.superview; up; up = up.superview) nested |= DPIsKind(up, DPDiaFloatingSidebar);
        if (!nested && !outermost) outermost = f;
    }
    if (outermost) {
        DPJoinChain(outermost);
        if (DPRootFor(outermost)) return outermost;
    }
    return window.contentView;
}

// Monitors also get the pointer over the revealed sidebar mirrored, so Dia keeps it out. The window doesn't, so the
// sidebar's own rows still highlight under the pointer.
static NSEvent *DPEdgeMirrored(NSEvent *event, BOOL overSidebar) {
    static __weak NSEvent *lastEvent;
    static NSWindow *__weak lastWindow;
    static NSView *__weak lastFloating;
    if (!DPSidebarOnRight.on || event.type != NSEventTypeMouseMoved) return event;
    NSPoint screen = event.window ? [event.window convertPointToScreen:event.locationInWindow] : event.locationInWindow;
    NSWindow *window = event.window ?: DPDiaWindowAt(screen);
    if (event != lastEvent || window != lastWindow) lastFloating = DPFloatingIn(window);  // Once per event, not per monitor.
    lastEvent = event;
    lastWindow = window;
    NSView *floating = lastFloating;
    CGFloat x = window ? screen.x - NSMinX(window.frame) : screen.x;
    BOOL edge = window && (x <= DPEdge || x >= NSWidth(window.frame) - DPEdge);
    if (!floating) return event;
    BOOL over = overSidebar && floating != window.contentView && !floating.hiddenOrHasHiddenAncestor &&
                NSPointInRect([window convertPointFromScreen:screen], [floating convertRect:floating.bounds toView:nil]);
    if (!edge && !over) return event;
    if (event.window) return DPMirroredEvent(event);
    CGEventRef cg = event.CGEvent ? CGEventCreateCopy(event.CGEvent) : NULL;
    if (!cg) return event;
    CGPoint point = CGEventGetLocation(cg);
    point.x = 2 * NSMinX(window.frame) + NSWidth(window.frame) - point.x;
    CGEventSetLocation(cg, point);
    NSEvent *mirrored = [NSEvent eventWithCGEvent:cg];
    CFRelease(cg);
    return mirrored ?: event;
}

static id DPEvent_addMonitor(id self, SEL _cmd, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) {
    if (!(mask & NSEventMaskMouseMoved) || !handler) return DPCallOriginal(DPEvent_addMonitor, self, mask, handler);
    NSEvent *(^mirroring)(NSEvent *) = ^NSEvent *(NSEvent *event) {
        NSEvent *mirrored = DPEdgeMirrored(event, YES);
        NSEvent *result = handler(mirrored);
        return result == mirrored ? event : result;  // Dispatch the real event, which sendEvent: mirrors again.
    };
    return DPCallOriginal(DPEvent_addMonitor, self, mask, mirroring);
}

// Dia may also read where the pointer is now rather than from the event, so that is mirrored the same way.
static BOOL DPMirrorsScreenPoint(NSPoint screen, NSWindow **into) {
    static __weak NSView *known;
    static __weak NSWindow *knownWindow;
    static NSTimeInterval lookedAt;
    if (!DPSidebarOnRight.on) return NO;
    NSWindow *window = DPDiaWindowAt(screen);
    if (!window) return NO;
    // This runs whenever anything asks where the pointer is, so the view walk happens at most twice a second.
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if ((knownWindow != window || now - lookedAt > 0.5)) {
        lookedAt = now;
        knownWindow = window;
        known = DPFloatingIn(window);
    }
    NSView *floating = known;
    if (!floating || floating.window != window) return NO;
    CGFloat x = screen.x - NSMinX(window.frame);
    BOOL edge = x <= DPEdge || x >= NSWidth(window.frame) - DPEdge;
    BOOL over = floating != window.contentView && !floating.hiddenOrHasHiddenAncestor &&
                NSPointInRect([window convertPointFromScreen:screen], [floating convertRect:floating.bounds toView:nil]);
    *into = window;
    return edge || over;
}

static NSPoint DPEvent_mouseLocation(id self, SEL _cmd) {
    NSPoint screen = DPCallOriginal(DPEvent_mouseLocation, self);
    NSWindow *window;
    if (DPMirrorsScreenPoint(screen, &window)) screen.x = 2 * NSMinX(window.frame) + NSWidth(window.frame) - screen.x;
    return screen;
}

static NSPoint DPWindow_mouseLocationOutside(NSWindow *self, SEL _cmd) {
    NSPoint local = DPCallOriginal(DPWindow_mouseLocationOutside, self);
    NSWindow *window;
    if (DPMirrorsScreenPoint([self convertPointToScreen:local], &window) && window == self) local.x = NSWidth(self.frame) - local.x;
    return local;
}

static void DPApp_sendEvent(NSApplication *self, SEL _cmd, NSEvent *event) {
    DPCallOriginal(DPApp_sendEvent, self, DPEdgeMirrored(event, NO));
}

void DPInstallHover(void) {
    DPHookClass(object_getClass(NSEvent.class), @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)DPEvent_addMonitor);
    DPHookClass(NSApplication.class, @selector(sendEvent:), (IMP)DPApp_sendEvent);
    DPHookClass(object_getClass(NSEvent.class), @selector(mouseLocation), (IMP)DPEvent_mouseLocation);
    DPHookClass(NSWindow.class, @selector(mouseLocationOutsideOfEventStream), (IMP)DPWindow_mouseLocationOutside);
}
