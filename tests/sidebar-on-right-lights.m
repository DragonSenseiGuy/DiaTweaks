// Sidebar on Right's window buttons in the top left corner, on real AppKit windows without Dia.
#import "StdPatch/Views.m"
#import "StdPatch/Hook.m"
#import <objc/message.h>
#import "Patches/SidebarOnRight/SidebarOnRight.h"

DPPatch DPSidebarOnRight, HideWindowControls;
static BOOL hasSidebar = YES;
static NSPoint pointer;
DPPatch *DPPatchNamed(NSString *key) { return [key isEqual:@"hideTrafficLights"] ? &HideWindowControls : NULL; }
BOOL DPHasSidebarIn(NSWindow *window) { return hasSidebar; }
static NSPoint FakePointer(void) { return pointer; }

#import "Patches/SidebarOnRight/Lights.m"

static int failures;
static void Check(BOOL yes, NSString *message) {
    printf("%s %s\n", yes ? "ok  " : "FAIL", message.UTF8String);
    if (!yes) failures++;
}

static void Wait(NSTimeInterval seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }

static NSRect InWindow(NSView *view) { return [view convertRect:view.bounds toView:nil]; }

static NSPoint OnScreen(NSWindow *window, NSPoint point) { return [window convertPointToScreen:point]; }

static NSPoint CloseCenter(DPLightsStrip *strip) {
    NSRect close = InWindow(strip.buttons.firstObject);
    return NSMakePoint(NSMidX(close), NSMidY(close));
}

static NSView *HitIn(DPLightsStrip *strip, NSPoint inWindow) {
    return [strip hitTest:[strip.superview convertPoint:inWindow fromView:nil]];
}

static void CheckCorner(NSWindow *window, DPLightsStrip *strip, NSString *when) {
    NSRect frame = InWindow(strip), close = InWindow(strip.buttons.firstObject);
    CGFloat height = NSHeight(window.contentView.superview.bounds);
    Check(fabs(NSMinX(frame)) < 0.5 && fabs(NSMaxY(frame) - height) < 0.5, [NSString stringWithFormat:@"strip is in the top left corner %@", when]);
    Check(fabs(NSMinX(close) - DPLightsInset) < 0.5 && fabs(height - NSMaxY(close) - DPLightsInset) < 0.5,
          [NSString stringWithFormat:@"close button sits %g pt from the corner %@", DPLightsInset, when]);
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    DPLightsPointer = FakePointer;
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 800, 600) styleMask:mask backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    [window orderFront:nil];

    DPUpdateLights(window);
    Check(!DPLightsStripIn(window), @"no strip while the patch is off");

    DPSidebarOnRight.on = YES;
    DPUpdateLights(window);
    DPLightsStrip *strip = (DPLightsStrip *)DPLightsStripIn(window);
    Check(strip && !strip.hidden && strip.superview == window.contentView.superview, @"strip joins the window's frame view");
    Check(strip.superview.subviews.lastObject == strip, @"strip is above everything else");
    Check(strip.buttons.count == 3, @"close, minimize and zoom buttons");
    CheckCorner(window, strip, @"");

    NSPoint close = CloseCenter(strip);
    Check(!strip.revealed && strip.alphaValue < 0.01, @"buttons are out of sight at first");
    Check(HitIn(strip, close) == nil, @"clicks in the corner reach the page while out of sight");

    pointer = OnScreen(window, close);
    [strip mouseEntered:nil];
    Check(strip.revealed && strip.inside, @"pointer in the corner reveals the buttons");
    Check(HitIn(strip, close) == strip.buttons.firstObject, @"revealed close button takes the click");
    Check(((BOOL (*)(id, SEL, id))objc_msgSend)(strip, @selector(_mouseInGroup:), strip.buttons.firstObject), @"buttons show their symbols on hover");

    pointer = OnScreen(window, NSMakePoint(400, 300));
    [strip mouseExited:nil];
    Check(strip.revealed && !strip.inside, @"buttons linger a moment after the pointer leaves");
    Wait(DPLightsLinger + 0.3);
    Check(!strip.revealed, @"buttons hide once the pointer has been away");

    // Hover.m mirrors events at the window's edges, so an enter can arrive while the pointer is really at the right edge.
    pointer = OnScreen(window, NSMakePoint(797, 590));
    [strip mouseEntered:nil];
    Check(!strip.revealed, @"a mirrored enter from the right edge reveals nothing");

    pointer = OnScreen(window, close);
    [strip mouseExited:nil];
    Check(strip.revealed, @"pointer really in the corner reveals even on an exit event");
    pointer = OnScreen(window, NSMakePoint(400, 300));
    Wait(DPLightsLinger + 0.3);
    Check(!strip.revealed, @"the watch timer hides them without another event");

    Class diaLights = objc_allocateClassPair(NSView.class, DPDiaTrafficLights, 0);
    objc_registerClassPair(diaLights);
    NSView *dia = [[diaLights alloc] initWithFrame:NSMakeRect(0, 0, 60, 20)];
    [window.contentView addSubview:dia];
    DPUpdateLights(window);
    Check(strip.hidden, @"strip stands down while Dia shows its own buttons");
    pointer = OnScreen(window, close);
    [strip mouseEntered:nil];
    Check(!strip.revealed, @"no reveal while Dia shows its own buttons");
    dia.hidden = YES;
    DPUpdateLights(window);
    Check(!strip.hidden, @"strip returns once Dia's buttons are hidden");

    HideWindowControls.on = YES;
    DPUpdateLights(window);
    Check(strip.hidden && !DPSidebarOnRightTakesLights(window), @"Hide Window Controls wins");
    HideWindowControls.on = NO;

    hasSidebar = NO;
    DPUpdateLights(window);
    Check(strip.hidden, @"no strip without a sidebar, such as with tabs at the top");
    hasSidebar = YES;
    DPUpdateLights(window);

    [window setFrame:NSMakeRect(120, 120, 1000, 700) display:YES];
    CheckCorner(window, strip, @"after a resize");

    NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(300, 300, 500, 400) styleMask:mask backing:NSBackingStoreBuffered defer:NO];
    other.releasedWhenClosed = NO;
    [other orderFront:nil];
    DPUpdateLights(other);
    Check(DPLightsStripIn(other) && DPLightsStripIn(other) != strip, @"each window gets its own strip");

    DPUpdateLights(window);
    close = CloseCenter(strip);
    pointer = OnScreen(window, close);
    [strip mouseEntered:nil];
    [strip.buttons.firstObject performClick:nil];
    Wait(0.2);
    Check(!window.isVisible && other.isVisible, @"close button closes its own window");

    [window orderFront:nil];
    DPSidebarOnRight.on = NO;
    DPUpdateLights(window);
    Check(strip.hidden && !strip.revealed, @"strip goes when the patch turns off");

    printf("%s\n", failures ? "sidebar-on-right-lights: FAILED" : "sidebar-on-right-lights: all passed");
    return failures ? 1 : 0;
} }
