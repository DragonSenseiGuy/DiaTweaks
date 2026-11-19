#import "Patches/CommandBar/HideTab.h"

static char DPBeforeKey, DPHiddenKey, DPDiaFrameKey, DPSettledKey;
static NSHashTable<NSView *> *DPHeldStrips;
static CFRunLoopObserverRef DPStripObserver;
static BOOL DPPlacing;

NSString *DPStripTabID(NSView *tabView) {
    NSView *content = DPFindView(tabView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabContentView); });
    NSString *tab = [DPSwiftValue(DPSwiftValue(DPSwiftValue(content, @"viewModel"), @"delegate"), @"tabID") description];
    return tab ? DPUUIDsIn(tab).firstObject : nil;
}

static NSRect DPDiaFrame(NSView *view) {
    NSValue *dia = DPGet(view, &DPDiaFrameKey);
    return dia ? dia.rectValue : view.frame;
}

// Dia slides what it moves, so a view kept in place loses its slide, or it would slide away and back.
static void DPStopSliding(NSView *view) {
    for (NSString *key in view.layer.animationKeys) {
        CAAnimation *animation = [view.layer animationForKey:key];
        NSString *path = [animation isKindOfClass:CAPropertyAnimation.class] ? ((CAPropertyAnimation *)animation).keyPath : nil;
        if ([path hasPrefix:@"position"] || [path hasPrefix:@"bounds"] || [path hasPrefix:@"frame"]) [view.layer removeAnimationForKey:key];
    }
}

static void DPPlace(NSView *view, NSRect frame) {
    if (NSEqualRects(view.frame, frame)) return;
    DPPlacing = YES;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        context.allowsImplicitAnimation = NO;
        [CATransaction setDisableActions:YES];
        view.frame = frame;
    }];
    DPPlacing = NO;
}

// A held strip's tabs and + button keep the frames they had, whichever Dia sets; the frame Dia meant is kept for letting go.
static BOOL DPPin(NSView *view, NSRect *frame) {
    NSView *strip = DPHeldStrips.count && !DPPlacing && DPHiding() ? view.superview : nil;
    if (!strip || ![DPHeldStrips containsObject:strip]) return NO;
    NSValue *before = [DPGet(strip, &DPBeforeKey) objectForKey:view];
    DPSet(view, &DPDiaFrameKey, [NSValue valueWithRect:*frame]);
    if (before) *frame = before.rectValue;
    return before != nil;
}

static void DPTabView_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    BOOL pinned = DPPin(self, &frame);
    DPCallOriginal(DPTabView_setFrame, self, frame);
    if (pinned) DPStopSliding(self);
}

static void DPPlusButton_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    BOOL pinned = DPPin(self, &frame);
    DPCallOriginal(DPPlusButton_setFrame, self, frame);
    if (pinned) DPStopSliding(self);
}

static void DPHold(NSView *strip);

// Before Core Animation commits what's drawn this turn, and only while a strip is held.
static void DPWatchStrips(void) {
    if (DPStripObserver) return;
    DPStripObserver = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, YES, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        NSArray<NSView *> *strips = DPHeldStrips.allObjects;
        for (NSView *strip in strips) DPHold(strip);
        if (strips.count) return;
        CFRunLoopObserverInvalidate(observer);
        CFRelease(observer);
        DPStripObserver = NULL;
    });
    CFRunLoopAddObserver(CFRunLoopGetMain(), DPStripObserver, kCFRunLoopCommonModes);
}

void DPHoldStrips(NSWindow *window) {
    for (NSView *strip in DPFindViews(DPDiaTabStripTabs)) {
        if (strip.window != window || [DPHeldStrips containsObject:strip]) continue;
        NSMapTable<NSView *, NSValue *> *before = [NSMapTable weakToStrongObjectsMapTable];
        for (NSView *view in strip.subviews) [before setObject:[NSValue valueWithRect:view.frame] forKey:view];
        DPSet(strip, &DPBeforeKey, before);
        DPSet(strip, &DPHiddenKey, [NSHashTable weakObjectsHashTable]);
        DPSet(strip, &DPSettledKey, [NSHashTable weakObjectsHashTable]);
        [DPHeldStrips addObject:strip];
        DPWatchStrips();
    }
}

static void DPRelease(NSView *strip) {
    [DPHeldStrips removeObject:strip];
    for (NSView *view in [DPGet(strip, &DPHiddenKey) allObjects]) view.hidden = NO;
    for (NSView *view in strip.subviews) {
        DPPlace(view, DPDiaFrame(view));
        DPSet(view, &DPDiaFrameKey, nil);
    }
    DPSet(strip, &DPBeforeKey, nil);
    DPSet(strip, &DPHiddenKey, nil);
    DPSet(strip, &DPSettledKey, nil);
}

// A strip that isn't held, such as one made as the tab layout changes, just leaves the hidden tab out.
static void DPLeaveOut(NSView *strip) {
    NSHashTable<NSView *> *hidden = DPGet(strip, &DPHiddenKey);
    if (!DPHidingATab(strip.window) && !DPParkingAny() && !hidden.count) return;
    for (NSView *view in strip.subviews) {
        NSString *tab = DPIsKind(view, DPDiaTabView) ? DPStripTabID(view) : nil;
        BOOL out = tab && DPHidesTab(tab);
        if (out && !view.hidden) {
            if (!hidden) DPSet(strip, &DPHiddenKey, hidden = [NSHashTable weakObjectsHashTable]);
            view.hidden = YES;
            [hidden addObject:view];
        } else if (!out && [hidden containsObject:view]) {
            view.hidden = NO;
            [hidden removeObject:view];
        }
    }
}

static void DPHold(NSView *strip) {
    NSMapTable<NSView *, NSValue *> *before = DPGet(strip, &DPBeforeKey);
    if (!before) return DPLeaveOut(strip);
    if (!DPHidingATab(strip.window)) return DPRelease(strip);
    NSHashTable<NSView *> *hidden = DPGet(strip, &DPHiddenKey), *settled = DPGet(strip, &DPSettledKey);
    for (NSView *view in strip.subviews) {
        NSValue *frame = [before objectForKey:view];
        // Which tab a view shows costs a few reads, every pass of the run loop while the bar is open: a tab that was there
        // before and isn't hidden is asked once.
        NSString *tab = !(frame && [settled containsObject:view]) && DPIsKind(view, DPDiaTabView) ? DPStripTabID(view) : nil;
        // A tab the bar isn't hiding that wasn't there before, such as one another app opened, lets the strip go.
        if (!frame && tab && !DPHidesTab(tab)) return DPRelease(strip);
        if (frame && !(tab && DPHidesTab(tab))) {
            if (!NSEqualRects(view.frame, frame.rectValue)) DPSet(view, &DPDiaFrameKey, [NSValue valueWithRect:view.frame]);  // What a view not hooked here was given.
            DPPlace(view, frame.rectValue);
            DPStopSliding(view);
            [settled addObject:view];
        } else if (!view.hidden) {
            view.hidden = YES;
            [hidden addObject:view];
        }
    }
}

static void DPStrip_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPStrip_layout, self);
    DPHold(self);
}

void DPReleaseStrips(void) {
    for (NSView *strip in DPHeldStrips.allObjects) DPRelease(strip);
}

void DPInstallHiddenStripTab(void) {
    DPHeldStrips = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaTabStripTabs, @selector(layout), (IMP)DPStrip_layout);
    DPHook(DPDiaTabView, @selector(setFrame:), (IMP)DPTabView_setFrame);
    DPHook(DPDiaTabSurfaceButton, @selector(setFrame:), (IMP)DPPlusButton_setFrame);
}
