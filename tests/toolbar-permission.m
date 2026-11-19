#import "Patches/HideToolbar/HideToolbar.h"

DPPatch DPRevealToolbarOnHover, DPShowToolbarWithSidebar, DPShowToolbarOnNewTab, DPShowToolbarWithTopTabs;
BOOL DPBesideSidebar(NSView *view) { return NO; }
BOOL DPLittleDiaIsOver(NSWindow *window) { return NO; }
void DPRepaintTabs(NSWindow *window) {}

@interface _TtC11ContentPane15ContentPaneView : NSView
@end
@implementation _TtC11ContentPane15ContentPaneView
- (BOOL)isFlipped { return YES; }
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC11BookmarkBar15BookmarkBarView : NSView
@end
@implementation _TtC11BookmarkBar15BookmarkBarView
@end

@interface _TtC13NavigationBar31WebsitePermissionRequestPopover : NSPopover
@property BOOL rejectShow, opened;
@property NSUInteger closes;
- (void)popoverDidClose:(NSNotification *)note;
@end
@implementation _TtC13NavigationBar31WebsitePermissionRequestPopover
- (BOOL)isShown { return self.opened; }
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)anchor preferredEdge:(NSRectEdge)edge {
    NSView *bar = anchor.superview;
    NSPoint point = NSMakePoint(NSMidX(bar.frame), NSMidY(bar.frame));
    self.opened = !self.rejectShow && bar.alphaValue == 1 && NSMinY(bar.frame) == 0 && [bar hitTest:point];
}
- (void)popoverDidClose:(NSNotification *)note {
    self.opened = NO;
    self.closes++;
}
@end

typedef _TtC13NavigationBar31WebsitePermissionRequestPopover PermissionPopover;

static NSView *DPSiteButton(void) {
    NSView *pane = [[NSClassFromString(@(DPDiaContentPane)) alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    NSView *bar = [[NSClassFromString(@(DPDiaToolbar)) alloc] initWithFrame:NSMakeRect(0, 0, 300, 40)];
    [pane addSubview:bar];
    [pane addSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 40, 300, 160)]];
    NSView *button = [[NSView alloc] initWithFrame:NSMakeRect(100, 0, 30, 40)];
    [bar addSubview:button];
    [pane layout];
    return button;
}

static void DPShow(PermissionPopover *popover, NSView *button) {
    [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSMaxYEdge];
}

int main(void) {
    @autoreleasepool {
        DPHideToolbar.on = YES;
        DPHideToolbar.progress = 1;
        DPHideToolbar.install();
        NSView *first = DPSiteButton(), *second = DPSiteButton();
        NSView *firstBar = first.superview, *secondBar = second.superview;
        __attribute__((objc_precise_lifetime)) NSArray *panes = @[firstBar.superview, secondBar.superview];
        NSCAssert(firstBar.alphaValue == 0 && secondBar.alphaValue == 0, @"both toolbars start hidden");

        PermissionPopover *prompt = [PermissionPopover new];
        DPShow(prompt, first);
        NSCAssert(prompt.shown && firstBar.alphaValue == 1, @"Dia opens the popover against an already visible, clickable toolbar");
        NSCAssert(secondBar.alphaValue == 0, @"the other pane stays hidden");

        PermissionPopover *replacement = [PermissionPopover new];
        DPShow(replacement, first);
        [prompt popoverDidClose:nil];
        NSCAssert(prompt.closes == 1 && replacement.shown && firstBar.alphaValue == 1, @"closing an earlier prompt keeps the next prompt visible");
        [replacement popoverDidClose:nil];
        NSCAssert(replacement.closes == 1 && firstBar.alphaValue == 0 && NSMaxY(firstBar.frame) == 0, @"closing the last prompt restores the hidden toolbar");

        prompt.rejectShow = YES;
        DPShow(prompt, first);
        NSCAssert(!prompt.shown && firstBar.alphaValue == 0, @"a popover that fails to open does not leave the toolbar visible");

        DPHideToolbar.on = NO;
        DPHideToolbar.progress = 0;
        [panes[0] layout];
        prompt.rejectShow = NO;
        DPShow(prompt, first);
        NSCAssert(prompt.shown, @"a normally visible toolbar still opens the website prompt");
        DPHideToolbar.on = YES;
        DPHideToolbar.progress = 1;
        [panes[0] layout];
        NSCAssert(firstBar.alphaValue == 1, @"turning on Hide Toolbar does not interrupt a pending request");
        [prompt popoverDidClose:nil];
        NSCAssert(firstBar.alphaValue == 0, @"closing the prompt honors the changed preference");
        puts("all website permission toolbar checks passed");
    }
}
