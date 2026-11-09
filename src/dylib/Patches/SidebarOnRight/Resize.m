#import "SidebarOnRight.h"

// Dia's resize handle works out the sidebar's width from where the pointer is, as if the sidebar were on the left. So a
// drag that starts on the sidebar's inner edge goes to the handle with the pointer mirrored across the window.
static __weak NSView *DPHandle;
static BOOL DPInMouseDown;

NSEvent *DPMirroredEvent(NSEvent *event) {
    NSWindow *window = event.window;
    CGEventRef cg = event.CGEvent ? CGEventCreateCopy(event.CGEvent) : NULL;
    if (!window || !cg) return event;
    CGPoint point = CGEventGetLocation(cg);
    point.x = 2 * NSMinX(window.frame) + NSWidth(window.frame) - point.x;
    CGEventSetLocation(cg, point);
    CGEventSetIntegerValueField(cg, kCGMouseEventDeltaX, -CGEventGetIntegerValueField(cg, kCGMouseEventDeltaX));
    NSEvent *mirrored = [NSEvent eventWithCGEvent:cg];
    CFRelease(cg);
    if (mirrored.window == window) return mirrored;
    // Without the window the location would be on screen, so keep it and lose the delta instead.
    NSPoint location = event.locationInWindow;
    location.x = NSWidth(window.frame) - location.x;
    return [NSEvent mouseEventWithType:event.type location:location modifierFlags:event.modifierFlags timestamp:event.timestamp
                          windowNumber:event.windowNumber context:nil eventNumber:event.eventNumber clickCount:event.clickCount pressure:event.pressure];
}

static BOOL DPThinAndTall(NSView *view, NSRect sidebar) {
    if (view.hiddenOrHasHiddenAncestor || [view isKindOfClass:NSScroller.class]) return NO;
    NSRect r = [view convertRect:view.bounds toView:nil];
    return NSWidth(r) > 0 && NSWidth(r) <= 16 && NSHeight(r) >= NSHeight(sidebar) / 2;
}

static BOOL DPInPage(NSView *view) {
    for (NSView *up = view; up; up = up.superview) if (DPIsKind(up, DPDiaContentContainer)) return YES;
    return NO;
}

// The handle is a thin view along the sidebar's edge: mirrored beside the pages if it sits outside the sidebar, or left at
// the window's edge if it's inside.
static NSView *DPHandleAt(NSWindow *window, NSPoint point) {
    NSView *sidebar = DPDockedSidebarIn(window);
    if (!sidebar) return nil;
    NSRect s = [sidebar convertRect:sidebar.bounds toView:nil];
    if (point.x < NSMinX(s) - 3 || point.x > NSMinX(s) + 5 || point.y < NSMinY(s) || point.y > NSMaxY(s)) return nil;
    NSView *hit = [window.contentView.superview hitTest:point];
    if (hit && ![hit isDescendantOf:sidebar] && !DPInPage(hit) && DPThinAndTall(hit, s)) return hit;
    return DPFindView(sidebar, ^BOOL(NSView *view) {
        return view != sidebar && DPThinAndTall(view, s) && fabs(NSMaxX([view convertRect:view.bounds toView:nil]) - NSMaxX(s)) < 1;
    });
}

static void DPWindow_sendEvent(NSWindow *self, SEL _cmd, NSEvent *event) {
    NSView *handle = DPHandle;
    if (!DPSidebarOnRight.on) return DPCallOriginal(DPWindow_sendEvent, self, event);
    if (event.type == NSEventTypeLeftMouseDown && (handle = DPHandleAt(self, event.locationInWindow))) {
        DPHandle = handle;
        DPInMouseDown = YES;
        [handle mouseDown:DPMirroredEvent(event)];
        DPInMouseDown = NO;
        return;
    }
    if (handle && handle.window == self && event.type == NSEventTypeLeftMouseDragged) return [handle mouseDragged:DPMirroredEvent(event)];
    if (handle && handle.window == self && event.type == NSEventTypeLeftMouseUp) {
        DPHandle = nil;
        return [handle mouseUp:DPMirroredEvent(event)];
    }
    DPCallOriginal(DPWindow_sendEvent, self, event);
}

// A handle that tracks the drag itself inside mouseDown: reads the events here instead.
static NSEvent *DPApp_nextEvent(NSApplication *self, SEL _cmd, NSEventMask mask, NSDate *until, NSRunLoopMode mode, BOOL dequeue) {
    NSEvent *event = DPCallOriginal(DPApp_nextEvent, self, mask, until, mode, dequeue);
    if (!DPInMouseDown || !DPHandle || !(event.type == NSEventTypeLeftMouseDragged || event.type == NSEventTypeLeftMouseUp)) return event;
    if (event.type == NSEventTypeLeftMouseUp && dequeue) DPHandle = nil;
    return DPMirroredEvent(event);
}

void DPInstallResize(void) {
    DPHook(DPDiaWindow, @selector(sendEvent:), (IMP)DPWindow_sendEvent);
    DPHookClass(NSApplication.class, @selector(nextEventMatchingMask:untilDate:inMode:dequeue:), (IMP)DPApp_nextEvent);
}
