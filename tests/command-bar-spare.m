#import <AppKit/AppKit.h>

static CFTimeInterval gIdleSeconds = 10;
#define CGEventSourceSecondsSinceLastEventType(state, type) (gIdleSeconds)

#import "Patches/CommandBar/HideTab.m"
#import "Patches/CommandBar/HideTabButton.m"
#import "Patches/CommandBar/CommandBarSpare.m"
#import "Patches/CommandBar/CommandBarSpareMaker.m"

DPPatch DPCommandBar, DPCommandBarKeepText, DPNewTabNextToCurrent;
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
BOOL DPTesting;
char DPOverlayKey;
const uintptr_t DPFirstFill = 4;

@implementation DPCommandBarOverlay
- (NSView *)viewUnder:(NSPoint)point { return nil; }
@end

@interface DPFakeDefaults : NSObject
@property(strong) NSMutableDictionary<NSString *, id> *store;
@end
@implementation DPFakeDefaults
- (instancetype)init {
    if ((self = [super init])) _store = [NSMutableDictionary dictionary];
    return self;
}
- (NSArray *)arrayForKey:(NSString *)key { return self.store[key]; }
- (void)setObject:(id)value forKey:(NSString *)key {
    if (value) self.store[key] = value;
    else [self.store removeObjectForKey:key];
}
@end

@interface DPFakeTab : NSObject
@property(copy) NSString *tabId, *URL;
@property BOOL closed;
@end
@implementation DPFakeTab
- (void)close:(id)sender { self.closed = YES; }
@end

@interface DPFakeProfile : NSObject
@property(strong) NSMutableArray<DPFakeTab *> *appleScriptTabs;
@end
@implementation DPFakeProfile
@end

@interface DPFakeScriptWindow : NSObject
@property(copy) NSString *windowId;
@property(strong) DPFakeTab *activeTab;
@property(strong) NSMutableArray<DPFakeProfile *> *appleScriptProfiles;
- (NSArray<DPFakeTab *> *)appleScriptTabs;
@end
@implementation DPFakeScriptWindow
- (NSArray<DPFakeTab *> *)appleScriptTabs { return self.appleScriptProfiles.firstObject.appleScriptTabs ?: @[]; }
@end

@interface DPFakeAppDelegate : NSObject
@property(strong) NSMutableArray<DPFakeScriptWindow *> *appleScriptWindows;
@end
@implementation DPFakeAppDelegate
@end

@interface RenderWidgetHostViewCocoa : NSView
@end
@implementation RenderWidgetHostViewCocoa
@end

@interface DPTestWindow : NSWindow
@property(strong) NSResponder *fakeResponder;
@end
@implementation DPTestWindow
- (NSResponder *)firstResponder { return self.fakeResponder ?: super.firstResponder; }
@end

static DPFakeDefaults *gDefaults;
static DPFakeAppDelegate *gDelegate;
static NSArray<NSWindow *> *gWindows;
static NSWindow *gKeyWindow;
static BOOL gAppActive = YES, gSendActionResult = YES;
static int gSendActionCalls;
static NSMutableDictionary<NSString *, NSTextView *> *gBarTexts;
static NSMutableArray<NSNumber *> *gDismissedHiddenStates;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *gBlanks, *gSplits;

NSUserDefaults *DPSettings(void) { return (NSUserDefaults *)gDefaults; }
NSTextView *DPBarText(DPCommandBarOverlay *overlay) { return overlay.openedTab ? gBarTexts[DPTabID(overlay.openedTab)] : nil; }
void DPFocusBar(DPCommandBarOverlay *overlay) {}
void DPShowShade(DPCommandBarOverlay *overlay) {}
id DPWatchKeys(DPCommandBarOverlay *overlay) { return nil; }
void DPWatch(DPCommandBarOverlay *overlay) {}
void DPCancelCommandBar(DPCommandBarOverlay *overlay) {}
void DPShowHiddenBars(void) {}
BOOL DPHasStrip(NSWindow *window) { return NO; }
NSView *DPBlankPage(NSWindow *window) { return nil; }
void DPMakeBlank(NSView *page, NSString *tab, NSString *closing) { if (page.window && tab) [DPBlanks(page.window) addObject:tab]; }
void DPHoldAutoPip(void) {}
void DPOnLaunch(void (^block)(void)) {}

NSMutableSet<NSString *> *DPBlanks(NSWindow *window) {
    NSString *key = window.identifier ?: @"";
    return gBlanks[key] ?: (gBlanks[key] = [NSMutableSet set]);
}
NSMutableSet<NSString *> *DPSplits(NSWindow *window) {
    NSString *key = window.identifier ?: @"";
    return gSplits[key] ?: (gSplits[key] = [NSMutableSet set]);
}

NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = [item.title isEqual:title] ? item : DPMenuItemTitled(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

id DPDismiss(DPCommandBarOverlay *overlay, BOOL closing) {
    [gDismissedHiddenStates addObject:@(overlay.hidden)];
    if (overlay.openedTab) DPStandInForTab(overlay.host, DPTabID(overlay.openedTab));
    if (DPGet(overlay.host, &DPOverlayKey) == overlay) DPSet(overlay.host, &DPOverlayKey, nil);
    overlay.host = nil;
    return overlay.openedTab;
}

void DPInstallFrozenLists(void) {}
void DPFreezeLists(NSWindow *window) {}
NSArray<NSString *> *DPListedTabs(NSWindow *window) { return @[]; }
void DPRelayoutLists(void) {}
NSString *DPVerifyHiddenRows(void) { return nil; }
void DPInstallHiddenStripTab(void) {}
void DPHoldStrips(NSWindow *window) {}
void DPReleaseStrips(void) {}
NSString *DPStripTabID(NSView *tabView) { return nil; }
BOOL DPSelectionLayoutKnown(void) { return YES; }
uintptr_t *DPSelectionStyle(NSView *background) { return NULL; }
uint8_t *DPTabShape(NSView *background) { return NULL; }
NSView *DPTabShapeView(NSView *background) { return nil; }
BOOL DPStyleSelected(uintptr_t style) { return NO; }
BOOL DPDrawnSelected(NSView *background) { return NO; }
void DPNoteLook(NSView *background) {}
NSArray *DPSelectedLook(NSView *button) { return nil; }
BOOL DPSwitchingTo(NSView *background) { return NO; }
void DPEndSwitch(NSWindow *window) {}
void DPUnselectFrontTab(NSView *background, BOOL standingIn) {}
void DPGiveBackSelection(NSView *background) {}
BOOL DPHoldsSelection(NSView *background) { return NO; }
void DPInstallFrontTab(void) {}
void DPInstallPress(void) {}

static BOOL DPApp_isActive(NSApplication *self, SEL _cmd) { return gAppActive; }
static NSWindow *DPApp_keyWindow(NSApplication *self, SEL _cmd) { return gKeyWindow; }
static NSArray<NSWindow *> *DPApp_windows(NSApplication *self, SEL _cmd) { return gWindows; }
static BOOL DPApp_sendAction(NSApplication *self, SEL _cmd, SEL action, id target, id sender) {
    gSendActionCalls++;
    return gSendActionResult;
}

static DPFakeTab *DPMakeTab(NSString *tabId, NSString *url) {
    DPFakeTab *tab = [DPFakeTab new];
    tab.tabId = tabId;
    tab.URL = url;
    return tab;
}

static DPFakeTab *DPAddHiddenTab(NSWindow *window, DPFakeProfile *profile, NSString *tabId) {
    DPExpectNewTab(window);
    DPFakeTab *tab = DPMakeTab(tabId, @"");
    [profile.appleScriptTabs addObject:tab];
    DPHideTabRow(tabId, window);
    return tab;
}

static DPTestWindow *DPMakeWindow(NSString *windowId) {
    DPTestWindow *window = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 100, 100)
                                                           styleMask:NSWindowStyleMaskBorderless
                                                             backing:NSBackingStoreBuffered defer:NO];
    window.identifier = windowId;
    return window;
}

static DPCommandBarOverlay *DPMakeOverlay(NSWindow *window, DPFakeTab *opened, DPFakeTab *ret) {
    DPCommandBarOverlay *overlay = [DPCommandBarOverlay new];
    overlay.host = window;
    overlay.openedTab = opened;
    overlay.returnTab = ret;
    return overlay;
}

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gDefaults = [DPFakeDefaults new];
        gDelegate = [DPFakeAppDelegate new];
        gDelegate.appleScriptWindows = [NSMutableArray array];
        gBarTexts = [NSMutableDictionary dictionary];
        gDismissedHiddenStates = [NSMutableArray array];
        gBlanks = [NSMutableDictionary dictionary];
        gSplits = [NSMutableDictionary dictionary];
        NSApp.delegate = (id)gDelegate;

        DPHookClass(NSApp.class, @selector(isActive), (IMP)DPApp_isActive);
        DPHookClass(NSApp.class, @selector(keyWindow), (IMP)DPApp_keyWindow);
        DPHookClass(NSApp.class, @selector(windows), (IMP)DPApp_windows);
        DPHookClass(NSApp.class, @selector(sendAction:to:from:), (IMP)DPApp_sendAction);

        NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *fileRoot = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
        NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
        [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
        fileRoot.submenu = fileMenu;
        [mainMenu addItem:fileRoot];
        NSApp.mainMenu = mainMenu;

        DPHidden = [NSMutableSet set];
        DPParked = [NSMutableSet set];
        DPOwner = [NSMapTable strongToWeakObjectsMapTable];
        DPCommandBar.on = YES;
        DPCommandBarHideTab.on = YES;
        DPCommandBarHideTab.unavailable = NO;
        DPCommandBarSpare.on = YES;
        DPNewTabNextToCurrent.on = NO;

        DPTestWindow *winA = DPMakeWindow(@"win-A"), *winB = DPMakeWindow(@"win-B");
        gWindows = @[ winA, winB ];
        gKeyWindow = winA;

        DPFakeTab *pageA = DPMakeTab(@"page-A", @"http://127.0.0.1/a");
        DPFakeTab *pageB = DPMakeTab(@"page-B", @"http://127.0.0.1/b");
        DPFakeTab *unhiddenB = DPMakeTab(@"unhidden-B", @"");
        DPFakeProfile *profA = [DPFakeProfile new];
        profA.appleScriptTabs = [NSMutableArray arrayWithObjects:pageA, nil];
        DPFakeProfile *profB = [DPFakeProfile new];
        profB.appleScriptTabs = [NSMutableArray arrayWithObjects:pageB, unhiddenB, nil];
        DPFakeScriptWindow *swA = [DPFakeScriptWindow new];
        swA.windowId = @"win-A";
        swA.activeTab = pageA;
        swA.appleScriptProfiles = [NSMutableArray arrayWithObject:profA];
        DPFakeScriptWindow *swB = [DPFakeScriptWindow new];
        swB.windowId = @"win-B";
        swB.activeTab = pageB;
        swB.appleScriptProfiles = [NSMutableArray arrayWithObject:profB];
        [gDelegate.appleScriptWindows addObjectsFromArray:@[ swA, swB ]];

        DPExpectNewTab(winA);
        DPFakeTab *lateB = DPMakeTab(@"late-B", @"");
        [profB.appleScriptTabs addObject:lateB];
        DPHideTabRow(@"late-B", winB);
        CHECK(DPHidesTab(@"late-B"), "expected tab still matches DPHidesTab during the 1 s window");
        CHECK(!DPHiddenTab(@"late-B"), "unhidden tab in second window is not DPHiddenTab");
        DPCommandBarOverlay *overlayB = DPMakeOverlay(winB, lateB, pageB);
        CHECK(!DPParkSpare(overlayB) && !DPSpareIn(winB), "DPParkSpare refuses to park an unhidden expected tab");
        DPStopExpecting();

        DPFakeTab *spareA = DPAddHiddenTab(winA, profA, @"spare-A");
        CHECK(DPHiddenTab(@"spare-A"), "hidden tab in expected window is DPHiddenTab");
        DPStandInFor(winA, @"newer-bar");
        DPCommandBarOverlay *overlayOld = DPMakeOverlay(winA, spareA, pageA);
        CHECK(DPParkSpare(overlayOld) && DPSpareIn(winA) == overlayOld, "DPParkSpare parks an actually hidden tab");
        CHECK([DPGet(winA, &DPTabKey) isEqual:@"newer-bar"], "DPParkSpare preserves another bar's stand-in");
        DPDropSpare(winA);
        CHECK([gDismissedHiddenStates.lastObject boolValue] == YES, "DPDropSpare keeps spare hidden while dismissing");
        CHECK([DPGet(winA, &DPTabKey) isEqual:@"newer-bar"], "DPDropSpare preserves another bar's stand-in");

        DPFakeTab *spareA2 = DPAddHiddenTab(winA, profA, @"spare-A2");
        DPStandInFor(winA, @"spare-A2");
        DPCommandBarOverlay *overlaySelf = DPMakeOverlay(winA, spareA2, pageA);
        CHECK(DPParkSpare(overlaySelf), "DPParkSpare parks its own bar");
        CHECK(DPGet(winA, &DPTabKey) == nil, "DPParkSpare clears its own stand-in");

        NSView *pageView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [winA.contentView addSubview:pageView];
        swA.activeTab = spareA2;
        [gDismissedHiddenStates removeAllObjects];
        CHECK(DPAdoptSpare(winA, pageView), "DPAdoptSpare adopts the active spare");
        CHECK([gDismissedHiddenStates.lastObject boolValue] == YES, "DPAdoptSpare keeps spare hidden while dismissing");
        DPSet(winA, &DPOverlayKey, DPMakeOverlay(winA, spareA2, nil));
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.38]];
        CHECK(!spareA2.closed, "adopt timer does not close the tab while a command bar is open over it");
        DPSet(winA, &DPOverlayKey, nil);

        DPFakeTab *spareA3 = DPAddHiddenTab(winA, profA, @"spare-A3");
        CHECK(DPParkSpare(DPMakeOverlay(winA, spareA3, pageA)), "parks spareA3");
        swA.activeTab = spareA3;
        CHECK(DPAdoptSpare(winA, pageView), "adopts spareA3");
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.38]];
        CHECK(spareA3.closed, "adopt timer closes an unused empty spare in a multi-tab space");
        [profA.appleScriptTabs removeObject:spareA2];
        [profA.appleScriptTabs removeObject:spareA3];
        swA.activeTab = pageA;

        RenderWidgetHostViewCocoa *webA = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [winA.contentView addSubview:webA];
        winA.fakeResponder = webA;
        gIdleSeconds = 10;
        gSendActionCalls = 0;
        gSendActionResult = NO;
        DPWanted = YES;
        DPSpareUntil = 0;
        DPMakeSpare();
        CHECK(gSendActionCalls == 1 && DPWanted && DPSpareUntil == 0, "failed sendAction re-arms DPWanted and clears DPSpareUntil");

        gSendActionResult = YES;
        DPMakeSpare();
        CHECK(gSendActionCalls == 2 && !DPWanted && DPSpareUntil > CACurrentMediaTime(), "successful sendAction starts spare wait");
        DPStopExpecting();
        DPSpareUntil = CACurrentMediaTime() - 1;
        DPMakeSpare();
        CHECK(gSendActionCalls == 3, "lapsed attempt with no spare re-arms DPWanted on next tick");
        DPStopExpecting();

        DPFakeTab *spareKeep = DPAddHiddenTab(winA, profA, @"spare-keep");
        CHECK(DPParkSpare(DPMakeOverlay(winA, spareKeep, pageA)), "parks spareKeep in winA");
        DPWanted = NO;
        DPSpareUntil = 0;
        RenderWidgetHostViewCocoa *webB = [[RenderWidgetHostViewCocoa alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [winB.contentView addSubview:webB];
        winB.fakeResponder = webB;
        gKeyWindow = winB;
        gSendActionCalls = 0;
        DPMakeSpare();
        CHECK(gSendActionCalls == 0 && !DPWanted, "existing spare in another window keeps global single-spare limit");
        gKeyWindow = winA;

        DPFakeTab *leftActive = DPMakeTab(@"left-active", @""), *leftTyped = DPMakeTab(@"left-typed", @""), *leftBg = DPMakeTab(@"left-bg", @"");
        [profA.appleScriptTabs addObjectsFromArray:@[ leftActive, leftTyped, leftBg ]];
        gDefaults.store[DPSparesKey] = @[ @"left-active", @"left-typed", @"left-bg", @"spare-keep" ];

        DPCommandBarSpare.on = NO;
        DPCloseLeftSpares(@[ @"left-bg" ], YES);
        CHECK(!leftBg.closed, "DPCloseLeftSpares does nothing when the option is off");
        DPCommandBarSpare.on = YES;

        swA.activeTab = leftActive;
        gIdleSeconds = 1;
        DPCloseLeftSpares(@[ @"left-active", @"left-bg", @"spare-keep" ], NO);
        CHECK(!leftActive.closed, "active restored spare is not closed while user recently gave input");
        CHECK(leftBg.closed, "background restored spare is closed at launch");
        CHECK(!spareKeep.closed, "currently parked spare is not closed by launch cleanup");

        swA.activeTab = leftTyped;
        gIdleSeconds = 10;
        NSTextView *typedView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        typedView.string = @"hello";
        gBarTexts[@"left-typed"] = typedView;
        DPSet(winA, &DPOverlayKey, DPMakeOverlay(winA, leftTyped, nil));
        DPCloseLeftSpares(@[ @"left-typed" ], YES);
        CHECK(!leftTyped.closed, "active restored spare with text in the bar is not closed");
        DPSet(winA, &DPOverlayKey, nil);

        DPCommandBarHideTab.unavailable = YES;
        CHECK(!DPSparesOn(), "DPSparesOn is NO when Hide New Tab Until Opened is unavailable");
        DPApplySpares(&DPCommandBarSpare);
        CHECK(DPSpareTimer == nil, "timer stays nil when spares are effectively off");
        DPCommandBarHideTab.unavailable = NO;
        CHECK(DPSparesOn(), "DPSparesOn is YES when dependencies are on and available");
        DPApplySpares(&DPCommandBarSpare);
        CHECK(DPSpareTimer != nil && DPSpareTimer.valid, "apply creates the 1 Hz timer when on");
        DPCommandBarSpare.on = NO;
        DPApplySpares(&DPCommandBarSpare);
        CHECK(DPSpareTimer == nil && !DPSpareIn(winA), "turning off invalidates the timer and drops any spare");

        if (failures) return 1;
        puts("PASS: command bar spare guards, launch cleanup, and timer lifecycle");
    }
    return 0;
}
