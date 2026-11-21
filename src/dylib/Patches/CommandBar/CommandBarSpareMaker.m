#import "Patches/CommandBar/CommandBarOverlay.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/AutoPip.h"

extern DPPatch DPNewTabNextToCurrent, DPCommandBarSpare;
static __weak NSWindow *DPSpareWindow;  // While a spare is being made there: its bar is parked as soon as it's up.
static CFTimeInterval DPSpareUntil;
static BOOL DPWanted = YES;  // At launch, and once a spare's been used or let go, rather than every moment Dia's left alone.
static NSTimer *DPSpareTimer;

void DPWantSpare(void) { DPWanted = YES; }
void DPNotMakingSpare(void) { DPSpareUntil = 0; }

static void DPDropUnwantedSpares(void) {
    for (NSWindow *window in NSApp.windows)
        if (DPSpareIn(window) && (!DPSparesOn() || DPHasStrip(window))) DPDropSpare(window);
}

// With no spare, one is made once Dia has been left alone for a moment, since making a tab holds it up for about a tenth
// of a second. Only while it's in front, so it never comes forward by itself, only over a page with nothing open, and
// never full screen, where going to the new tab and back would end it.
static void DPMakeSpare(void) {
    DPDropUnwantedSpares();
    NSWindow *window = NSApp.keyWindow;
    // The cheap checks first: this runs every second.
    if (DPTesting || !DPSparesOn() || !NSApp.isActive || NSApp.modalWindow || !window || window.attachedSheet) return;
    if (CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType) < 2 || NSEvent.pressedMouseButtons) return;
    if (window.styleMask & NSWindowStyleMaskFullScreen) return;
    // One left in another space, after switching, goes, so the next is made in this one. Looked for now and then: it's costly.
    static CFTimeInterval lookedAt;
    DPCommandBarOverlay *spare = DPSpareIn(window);
    if (spare && CACurrentMediaTime() - lookedAt > 3) {
        lookedAt = CACurrentMediaTime();
        if (!DPScriptTab(window, DPTabID(spare.openedTab))) DPDropSpare(window);
    }
    BOOL anySpare = NO;
    for (NSWindow *other in NSApp.windows) anySpare |= DPSpareIn(other) != nil;
    if (!DPWanted && !anySpare && CACurrentMediaTime() >= DPSpareUntil) DPWanted = YES;
    if (!DPWanted) return;
    if (DPSpareIn(window) || DPGet(window, &DPOverlayKey) || DPHidingATab(window) || DPHasStrip(window) || !DPScriptWindow(window)) return;
    for (NSWindow *child in window.childWindows) if (child.visible) return;
    NSString *front = DPActiveTabID(window);
    if (!front || [DPSplits(window) containsObject:front] || [DPBlanks(window) containsObject:front] || DPBlankPage(window)) return;
    if (![[DPScriptTab(window, front) valueForKey:@"URL"] description].length) return;
    if (!DPIsKind(window.firstResponder, "RenderWidgetHostViewCocoa")) return;  // Not while typing in Dia's own fields.
    NSMenuItem *item = DPMenuItemTitled(NSApp.mainMenu, @"New Tab");
    if (!item.action) return;
    DPSpareWindow = window;
    DPSpareUntil = CACurrentMediaTime() + 1;
    DPWanted = NO;
    DPExpectNewTab(window);
    __weak NSResponder *typing = window.firstResponder;
    DPHoldAutoPip();  // As choosing New Tab does, which sending its action doesn't.
    if (![NSApp sendAction:item.action to:item.target from:item]) {
        DPSpareUntil = 0;
        DPStopExpecting();
        return DPWantSpare();
    }
    for (int ms = 0; ms <= 300; ms += 300)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            NSView *view = (NSView *)typing, *now = (NSView *)window.firstResponder;
            BOOL typingElsewhere = [now isKindOfClass:NSTextView.class] && !now.isHiddenOrHasHiddenAncestor;  // Such as the toolbar's address.
            if (view.window == window && now != view && !typingElsewhere && !DPGet(window, &DPOverlayKey)) [window makeFirstResponder:view];
        });
}

void DPParkIfSpare(DPCommandBarOverlay *overlay) {
    if (overlay.host != DPSpareWindow || CACurrentMediaTime() >= DPSpareUntil) return;
    DPSpareUntil = 0;
    overlay.hidden = YES;  // Before it's ever drawn.
    if (DPParkSpare(overlay)) return;
    DPCancelCommandBar(overlay);
    DPWantSpare();
}

BOOL DPSparesOn(void) { return DPHiding() && DPCommandBarSpare.on && !DPNewTabNextToCurrent.on; }

static void DPUpdateSpareTimer(void) {
    if (DPSparesOn()) {
        if (!DPSpareTimer) DPSpareTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { DPMakeSpare(); }];
    } else {
        [DPSpareTimer invalidate];
        DPSpareTimer = nil;
    }
}

static void DPInstallSpares(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:DPPatchesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        DPDropUnwantedSpares();
        DPUpdateSpareTimer();
    }];
    DPOnLaunch(^{ DPUpdateSpareTimer(); });
    // Those Dia brought back from last time, once its windows are back, and again in case one was slow. Each stays noted
    // until it's closed or found in use, as Dia may quit again before it's looked for.
    NSArray *left = [DPSettings() arrayForKey:@"commandBarSpares"];
    for (int delay = 3; left.count && delay <= 12; delay += 9)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPCloseLeftSpares(left, delay > 3); });
}

static void DPApplySpares(DPPatch *patch) {
    DPDropUnwantedSpares();
    DPUpdateSpareTimer();
}

static NSString *DPVerifySpares(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows)
        if (DPSpareIn(window) && !DPSparesOn()) return @"a spare is still kept with the option off";
    return nil;
}

DP_PATCH(DPCommandBarSpare) {
    .key = @"commandBarSpare",
    .order = 95,
    .title = @"Open the Bar Instantly",
    .detail = @"Keep a new tab ready, hidden, so the command bar opens at once instead of waiting for Dia to make one. Needs Hide New Tab Until Opened and tabs in the sidebar, and isn't used with Open New Tabs Next to Current. Experimental.",
    .symbol = @"bolt.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaNewTabPage, DPDiaTabListCollection, DPDiaTabListLayout),
    .install = DPInstallSpares,
    .apply = DPApplySpares,
    .verify = DPVerifySpares,
};
