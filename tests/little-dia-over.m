#import "Patches/LittleDia/Route.m"

DPPatch DPLittleDia, DPLittleDiaFollowRules, DPLittleDiaRemember;
NSSize DPLittleDiaSize(void) { return NSZeroSize; }
NSRect DPLittleDiaSavedFrame(void) { return NSZeroRect; }
BOOL DPSendToLittleDia(NSDictionary *request) { return NO; }
void DPExpectLittleDiaWindow(NSRect frame, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window)) {}
void DPLinkArrived(void) {}
NSDictionary *DPNoteStackForLink(void) { return nil; }
void DPBringBackPutAway(NSWindow *little) {}
BOOL DPLittleDiaStarting(void) { return NO; }
void DPPutLittleDiaOver(NSWindow *little, NSWindow *window) {}
void DPEditLittleDiaAddress(NSWindow *window) {}

static BOOL gTabsAtTop;
BOOL DPTabsAtTop(NSWindow *window) { return gTabsAtTop; }

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
@end

static int failures;

// Window is far off screen so its whole frame counts; rects are window-relative.
static void frame(NSString *what, BOOL tabsAtTop, NSSize size, NSRect pane, NSRect want) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:(NSRect){{-30000, -30000}, size} styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    [window.contentView addSubview:[[NSClassFromString(@(DPDiaContentPane)) alloc] initWithFrame:pane]];
    [window orderFront:nil];
    gTabsAtTop = tabsAtTop;
    NSRect got = DPOverWindowFrame(window);
    got.origin.x -= NSMinX(window.frame);
    got.origin.y -= NSMinY(window.frame);
    if (!NSEqualRects(got, want)) printf("FAIL %s: %s, want %s\n", what.UTF8String, NSStringFromRect(got).UTF8String, NSStringFromRect(want).UTF8String), failures++;
    [window orderOut:nil];
}

static void remembered(NSString *what, NSRect saved, BOOL want) {
    NSArray *screens = @[ [NSValue valueWithRect:NSMakeRect(0, 0, 1440, 900)], [NSValue valueWithRect:NSMakeRect(1440, -100, 1920, 1080)] ];
    if (DPOnScreens(saved, screens) != want) printf("FAIL %s: %s should be %s\n", what.UTF8String, NSStringFromRect(saved).UTF8String, want ? "kept" : "dropped"), failures++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSSize size = NSMakeSize(1200, 800);
        frame(@"sidebar", NO, size, NSMakeRect(190, 0, 1010, 800), NSMakeRect(291, 12, 808, 776));
        frame(@"sidebar, padded page", NO, size, NSMakeRect(196, 6, 998, 788), NSMakeRect(296, 12, 798, 776));
        frame(@"top", YES, size, NSMakeRect(0, 0, 1200, 760), NSMakeRect(120, 12, 960, 736));
        frame(@"top, tabs hidden", YES, size, NSMakeRect(0, 0, 1200, 800), NSMakeRect(120, 12, 960, 776));
        frame(@"short", NO, NSMakeSize(1200, 300), NSMakeRect(190, 0, 1010, 300), NSMakeRect(291, -30, 808, 360));
        frame(@"short, tabs at the top", YES, NSMakeSize(1200, 300), NSMakeRect(0, 0, 1200, 260), NSMakeRect(120, -50, 960, 360));
        remembered(@"on the first screen", NSMakeRect(100, 20, 1180, 860), YES);
        remembered(@"on the second screen", NSMakeRect(1500, -50, 1180, 860), YES);
        remembered(@"filling a screen", NSMakeRect(0, 0, 1440, 900), YES);
        remembered(@"across two screens", NSMakeRect(1000, 50, 800, 600), NO);
        remembered(@"screen gone", NSMakeRect(3600, 50, 1180, 860), NO);
        remembered(@"too big", NSMakeRect(0, 0, 1500, 900), NO);
        remembered(@"never saved", NSZeroRect, NO);
    }
    if (failures) return 1;
    puts("PASS: over-the-page frame in both layouts, remembered frame on screen");
    return 0;
}
