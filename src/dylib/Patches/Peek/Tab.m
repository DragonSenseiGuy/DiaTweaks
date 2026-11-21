#import "Patches/Peek/Peek.h"
#import "Patches/CommandBar/Tabs.h"

static id DPTabState(NSView *tab) {
    return DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue");
}

// selectionStyle is nil on an unselected pinned tab, "none" on other unselected tabs, above/below beside the selection.
static BOOL DPTabSelected(NSView *tab) {
    NSString *style = [[DPSwiftValue(DPTabState(tab), @"selectionStyle") description] lowercaseString];
    return style && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"];
}

static NSView *DPFindTabIn(NSWindow *window, BOOL (^match)(NSView *tab)) {
    const char *kinds[2] = {DPDiaTabView, DPDiaPinnedTab};
    for (int i = 0; i < 2; i++)
        for (NSView *tab in DPFindViews(kinds[i]))
            if (tab.window == window && match(tab)) return tab;
    return nil;
}

static NSString *DPPeekPageID(id page) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = @[@"identifier", @"id", @"contentID", @"contentId", @"uuid"]; });
    for (NSString *key in keys) {
        NSString *value = [DPSwiftValue((NSObject *)page, key) description];
        if (value.length >= 32 && [value containsString:@"-"]) return value;
    }
    return nil;
}

static NSView *DPPeekOriginTab(NSWindow *window, id source) {
    NSString *sourceID = DPPeekPageID(source);
    __block NSView *selected = nil;
    NSView *exact = DPFindTabIn(window, ^BOOL(NSView *tab) {
        if (sourceID && [[DPTabState(tab) description] containsString:sourceID]) return YES;
        if (!selected && DPTabSelected(tab)) selected = tab;
        return NO;
    });
    return exact ?: selected;
}

// An icon tile's links already leave in a new tab, but a pinned row's stay in it, and only its menu says it is pinned.
BOOL DPPeekInPinnedRow(NSWindow *window, id page) {
    NSView *tab = DPPeekOriginTab(window, page);
    NSMenuItem *unpin = tab && !DPIsKind(tab, DPDiaPinnedTab) ? [DPTabContextMenu(tab) itemWithTitle:@"Unpin"] : nil;
    return unpin && !unpin.hidden && unpin.enabled;
}

static NSString *DPPeekTabContentKey(NSView *tab) {
    NSString *state = [DPTabState(tab) description];
    NSRange mark = [state rangeOfString:@"contentIDs: ["];
    if (mark.location == NSNotFound || state.length < NSMaxRange(mark) + 36) return nil;
    NSString *key = [state substringWithRange:NSMakeRange(NSMaxRange(mark), 36)];
    return [key containsString:@"-"] ? key : nil;
}

static NSView *DPPeekTabWithContent(NSWindow *window, NSString *key) {
    return DPFindTabIn(window, ^BOOL(NSView *tab) { return [[DPTabState(tab) description] containsString:key]; });
}

static BOOL DPTabIsTop(NSView *tab) {
    for (NSView *view = tab; view; view = view.superview)
        if ([NSStringFromClass(view.class) containsString:@"TabStrip"]) return YES;
    return NO;
}

@interface DPPeekTabBadge : NSView
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic, copy) NSString *contentKey, *frontIDAtOpen;
@property (nonatomic) BOOL pinned;
@property (nonatomic, strong) NSTrackingArea *tabTracking;
@property (nonatomic, weak) NSView *trackedTab;
@property (nonatomic, strong) NSTimer *watch;
@end

@implementation DPPeekTabBadge
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [self.trackedTab removeTrackingArea:self.tabTracking];
    self.tabTracking = nil;
    if (!self.superview || self.pinned) return;
    self.tabTracking = [[NSTrackingArea alloc] initWithRect:self.superview.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self.superview addTrackingArea:self.tabTracking];
    self.trackedTab = self.superview;
}

- (void)mouseEntered:(NSEvent *)event { if (!self.pinned) self.hidden = YES; }
- (void)mouseExited:(NSEvent *)event { self.hidden = NO; }

- (void)watch:(NSTimer *)timer {
    DPPeekCard *peek = self.peek;
    if (!peek || peek.closing) return [self stop];
    NSView *tab = self.superview;
    if (!self.contentKey) {
        // A pinned tab's state is briefly unreadable at times; only a readable, unselected one means it was left.
        if (self.pinned && tab && DPTabState(tab) && !DPTabSelected(tab)) [self closePeek];
        return;
    }
    tab = DPPeekTabWithContent(peek.window, self.contentKey);
    if (!tab) {
        // A missing row says nothing (the sidebar builds rows lazily); only the tab closing or another coming to the front does.
        NSString *front = DPActiveTabID(peek.window);
        if (!peek.source || (self.frontIDAtOpen && front && ![front isEqual:self.frontIDAtOpen])) [self closePeek];
        return;
    }
    if (self.superview != tab) [tab addSubview:self];
    if (!DPTabSelected(tab)) [self closePeek];
}

- (void)closePeek {
    [self stop];
    [self.peek close:DPPeekClose];
}

- (void)dealloc { [_watch invalidate]; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self stop];
}

- (void)stop {
    [self.watch invalidate];
    self.watch = nil;
}
@end

void DPPeekShowTabBadge(DPPeekCard *peek, id source) {
    NSView *tab = DPPeekOriginTab(peek.window, source);
    if (!tab) return;
    BOOL pinned = DPIsKind(tab, DPDiaPinnedTab), top = DPTabIsTop(tab);
    NSTextField *eyes = [NSTextField labelWithString:@"👀"];
    eyes.font = [NSFont systemFontOfSize:pinned ? 11 : 12];
    eyes.alignment = NSTextAlignmentCenter;
    [eyes sizeToFit];
    CGFloat w = NSWidth(eyes.frame), h = NSHeight(eyes.frame);
    NSRect frame;
    NSAutoresizingMaskOptions resize;
    if (pinned) {
        frame = NSMakeRect(top ? NSMidX(tab.bounds) - w / 2 : NSMaxX(tab.bounds) - w - 2, tab.isFlipped ? 2 : NSMaxY(tab.bounds) - h - 2, w, h);
        resize = (top ? NSViewMinXMargin | NSViewMaxXMargin : NSViewMinXMargin) | (tab.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
    } else {
        frame = NSMakeRect(NSMaxX(tab.bounds) - w - 6, NSMidY(tab.bounds) - h / 2, w, h);
        resize = NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    }
    DPPeekTabBadge *badge = [[DPPeekTabBadge alloc] initWithFrame:frame];
    badge.autoresizingMask = resize;
    badge.peek = peek;
    badge.pinned = pinned;
    badge.contentKey = DPPeekTabContentKey(tab);
    badge.frontIDAtOpen = DPActiveTabID(peek.window);
    eyes.frame = NSOffsetRect(badge.bounds, 0, !pinned && top ? 2 : 0);
    eyes.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [badge addSubview:eyes];
    [tab addSubview:badge];
    peek.tabBadge = badge;
    __weak DPPeekTabBadge *weak = badge;
    badge.watch = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:YES block:^(NSTimer *timer) {
        DPPeekTabBadge *me = weak;
        if (me) [me watch:timer];
        else [timer invalidate];
    }];
}

void DPPeekHideTabBadge(DPPeekCard *peek) {
    [(DPPeekTabBadge *)peek.tabBadge stop];
    [peek.tabBadge removeFromSuperview];
    peek.tabBadge = nil;
}
