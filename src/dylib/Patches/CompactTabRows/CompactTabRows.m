#import "Patches/CompactTabRows/CompactTabRows.h"

extern DPPatch DPCompactTabRows;

static NSString *const DPSmallRows = @"small";
static const CGFloat DPOldRowHeight = 37, DPSmallRowHeight = 30;

static BOOL DPSmall(void) { return DPCompactTabRows.on && [DPChoice(&DPCompactTabRows) isEqual:DPSmallRows]; }

static CGFloat DPRowTarget(void) { return DPSmall() ? DPSmallRowHeight : DPOldRowHeight; }

CGFloat DPCompactRowHeight(void) { return DPRowTarget(); }

// The attributes Dia keeps, not the moved copies Collapse Pinned Tabs hands out.
static NSArray<NSCollectionViewLayoutAttributes *> *DPKeptAttributes(NSCollectionViewLayout *layout) {
    NSArray *(*elements)(id, SEL, NSRect) = (void *)DPDiaIMP(objc_getClass(DPDiaTabListLayout), @selector(layoutAttributesForElementsInRect:));
    return elements(layout, @selector(layoutAttributesForElementsInRect:), NSMakeRect(-1e5, -1e5, 2e5, 1e7));
}

static CGFloat DPRowHeight(NSArray<NSCollectionViewLayoutAttributes *> *all) {
    NSCountedSet<NSNumber *> *heights = [NSCountedSet set];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem) [heights addObject:@(round(NSHeight(a.frame) * 2) / 2)];
    NSNumber *row = nil;
    for (NSNumber *each in heights) if (!row || [heights countForObject:each] > [heights countForObject:row]) row = each;
    return row.doubleValue;
}

static char DPMovesKey;

typedef void (*DPHeightHandler)(double height, void *context __attribute__((swift_context))) __attribute__((swiftcall));

// A group's card is sized when its list reports its height, and Dia reports it only when it sets the height, not when we lower it.
static void DPReportHeight(NSCollectionViewLayout *layout, double height) {
    NSView *list = layout.collectionView;
    while (list && !DPIsKind(list, DPDiaTabList)) list = list.superview;
    void **handler = list ? DPIvar(list, "onPreferredHeightUpdated") : NULL;
    if (handler && handler[0]) ((DPHeightHandler)handler[0])(height + layout.collectionView.enclosingScrollView.contentInsets.top, handler[1]);
}

static void DPLayout_prepareLayout(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepareLayout, self);
    if (!DPCompactTabRows.on) return DPSet(self, &DPMovesKey, nil);
    double *contentHeight = DPIvar(self, "contentHeight");  // Dia's layout hands out the attributes it keeps, so changing them changes it.
    NSArray<NSCollectionViewLayoutAttributes *> *all = DPKeptAttributes(self);
    CGFloat height = DPRowHeight(all), cut = height - DPRowTarget();
    if (!contentHeight || cut < 0.5) return;
    NSMutableArray<NSValue *> *rows = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem && NSHeight(a.frame) >= height - 0.5)
            [rows addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(a.frame), NSMinY(a.frame), NSWidth(a.frame), height)]];
    NSMutableArray<NSArray<NSValue *> *> *moves = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all) {
        NSRect frame = a.frame;
        for (NSValue *value in rows) {
            NSRect row = value.rectValue;
            // A folder's first row starts 3 pt up into its header.
            if (NSMaxY(row) <= NSMinY(a.frame) + 3.5) frame.origin.y -= cut;
            else if (NSMinY(row) >= NSMinY(a.frame) - 0.5 && NSMaxY(row) <= NSMaxY(a.frame) + 0.5) frame.size.height -= cut;
        }
        if (a.representedElementCategory == NSCollectionElementCategoryItem)
            [moves addObject:@[ [NSValue valueWithRect:frame], [NSValue valueWithRect:a.frame] ]];
        a.frame = frame;
    }
    *contentHeight -= cut * rows.count;
    DPSet(self, &DPMovesKey, moves);
    DPReportHeight(self, *contentHeight);
}

// Collapse Pinned's hooks install after these, so run first and have already taken its header out of the point.
CGFloat DPTabListDiaY(NSArray<NSArray<NSValue *> *> *moves, CGFloat y) {
    NSArray<NSValue *> *inside = nil, *above = nil;
    for (NSArray<NSValue *> *move in moves) {
        NSRect now = move[0].rectValue;
        if (y >= NSMinY(now) && y < NSMaxY(now) && (!inside || NSHeight(now) < NSHeight(inside[0].rectValue))) inside = move;
        if (NSMaxY(now) <= y && (!above || NSMaxY(now) > NSMaxY(above[0].rectValue))) above = move;
    }
    if (inside) {
        NSRect now = inside[0].rectValue, then = inside[1].rectValue;
        return NSMinY(then) + (y - NSMinY(now)) * NSHeight(then) / NSHeight(now);
    }
    return above ? y - NSMaxY(above[0].rectValue) + NSMaxY(above[1].rectValue) : y;
}

@interface DPCompactDrag : NSProxy
@property (nonatomic, strong) id<NSDraggingInfo> info;
@property (nonatomic) NSPoint location;
@end

@implementation DPCompactDrag
- (NSPoint)draggingLocation { return self.location; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [(NSObject *)self.info methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.info]; }
- (BOOL)respondsToSelector:(SEL)sel { return [(NSObject *)self.info respondsToSelector:sel]; }
- (BOOL)conformsToProtocol:(Protocol *)protocol { return [(NSObject *)self.info conformsToProtocol:protocol]; }
- (BOOL)isKindOfClass:(Class)cls { return [(NSObject *)self.info isKindOfClass:cls]; }
@end

static NSPoint DPDragPointer, DPDragHanded;
static BOOL DPDragHandedSet;

id<NSDraggingInfo> DPDraggingInfoAt(id<NSDraggingInfo> info, NSPoint location) {
    DPCompactDrag *drag = [DPCompactDrag alloc];
    drag.info = info;
    drag.location = location;
    id<NSDraggingInfo> pointer = info;
    while (object_getClass(pointer) == DPCompactDrag.class) pointer = ((DPCompactDrag *)pointer).info;
    DPDragPointer = pointer.draggingLocation;
    DPDragHanded = location;
    DPDragHandedSet = YES;
    return (id<NSDraggingInfo>)drag;
}

// Dia draws the dragged tab where it is told the pointer is, which with these proxies is a point in its own row geometry: put the tab back under the pointer.
void DPPlaceDraggedTab(void) {
    if (!DPDragHandedSet) return;
    DPDragHandedSet = NO;
    CGFloat up = DPDragPointer.y - DPDragHanded.y;
    if (fabs(up) < 0.5) return;
    for (NSWindow *window in NSApp.windows) {
        if (!window.visible || !strstr(object_getClassName(window), "ArcDraggingWindow")) continue;
        for (NSView *tab in window.contentView.subviews)
            [tab setFrameOrigin:NSMakePoint(NSMinX(tab.frame), NSMinY(tab.frame) + (tab.superview.isFlipped ? -up : up))];
    }
}

static id<NSDraggingInfo> DPDiaDrag(NSView *tabList, id<NSDraggingInfo> info) {
    NSCollectionView *list = (NSCollectionView *)DPFindView(tabList, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabListCollection); });
    NSArray *moves = DPGet(list.collectionViewLayout, &DPMovesKey);
    if (!moves) return info;
    NSPoint point = [list convertPoint:info.draggingLocation fromView:nil];
    point.y = DPTabListDiaY(moves, point.y);
    return DPDraggingInfoAt(info, [list convertPoint:point toView:nil]);
}

static NSDragOperation DPTabList_entered(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    NSDragOperation operation = DPCallOriginal(DPTabList_entered, self, DPDiaDrag(self, info));
    DPPlaceDraggedTab();
    return operation;
}
static NSDragOperation DPTabList_updated(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    NSDragOperation operation = DPCallOriginal(DPTabList_updated, self, DPDiaDrag(self, info));
    DPPlaceDraggedTab();
    return operation;
}
// A drop places nothing, so what it handed down must not wait for the next drag to place a tab by it.
static BOOL DPDropped(BOOL result) {
    DPDragHandedSet = NO;
    return result;
}
static BOOL DPTabList_prepare(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPDropped(DPCallOriginal(DPTabList_prepare, self, DPDiaDrag(self, info))); }
static BOOL DPTabList_perform(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPDropped(DPCallOriginal(DPTabList_perform, self, DPDiaDrag(self, info))); }

static char DPDiaFontKey;

// A tab's, folder's or New Tab row's title: the labels in the list that aren't a tab's second line.
static BOOL DPIsRowTitle(NSView *label) {
    if (DPIsKind(label.superview, DPDiaTransitioningLabel)) return NO;
    for (NSView *view = label.superview; view; view = view.superview) if (DPIsKind(view, DPDiaTabListCollection)) return YES;
    return NO;
}

static void DPLabel_layout(NSTextField *self, SEL _cmd) {
    DPCallOriginal(DPLabel_layout, self);
    BOOL small = DPSmall();
    if ((!small && !DPGet(self, &DPDiaFontKey)) || !DPIsRowTitle(self) || !DPMayAdjust(self)) return;
    NSFont *dia = DPDiaValue(self, &DPDiaFontKey, self.font), *shown = small ? [NSFont fontWithDescriptor:dia.fontDescriptor size:dia.pointSize - 1] : dia;
    if ([self.font isEqual:shown]) return;
    DPSet(self, &DPDiaFontKey, nil);
    if (small) DPOverride(self, &DPDiaFontKey, dia, shown);
    self.font = shown;
    self.superview.needsLayout = YES;
}

static void DPGroupCell_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGroupCell_layout, self);
    if (!DPCompactTabRows.on || NSHeight(self.bounds) <= DPRowTarget() + 0.5) return;
    for (NSView *header in self.subviews) {
        CGFloat extra = NSHeight(header.frame) - (DPRowTarget() - 3);
        if (!DPIsKind(header, DPDiaTabGroupBackground) && extra > 0.5 && NSHeight(header.frame) < DPOldRowHeight + 1.5 && NSMinY(header.frame) > 1)
            [header setFrameOrigin:NSMakePoint(NSMinX(header.frame), NSMinY(header.frame) - extra / 2)];
    }
}

static void DPInstallCompactTabRows(void) {
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepareLayout);
    DPHook(DPDiaTabGroupCell, @selector(layout), (IMP)DPGroupCell_layout);
    DPHook(DPDiaFeatheredLabel, @selector(layout), (IMP)DPLabel_layout);
    DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
    DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
    DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
    DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);
}

static void DPApplyCompactTabRows(DPPatch *patch) {
    for (NSView *view in DPFindViews(DPDiaTabListCollection)) [((NSCollectionView *)view).collectionViewLayout invalidateLayout];
    for (NSView *label in DPFindViews(DPDiaFeatheredLabel)) {
        label.needsLayout = YES;
        [label layoutSubtreeIfNeeded];
    }
}

static NSString *DPVerifyCompactTabRows(DPPatch *patch) {
    for (NSView *view in DPFindViews(DPDiaTabListCollection)) {
        NSArray *all = DPKeptAttributes(((NSCollectionView *)view).collectionViewLayout);
        if (patch->on && DPRowHeight(all) > DPRowTarget() + 0.5) return [NSString stringWithFormat:@"tab rows are taller than %g pt", DPRowTarget()];
    }
    for (NSTextField *label in DPFindViews(DPDiaFeatheredLabel)) {
        if (!DPIsRowTitle(label) || label.hiddenOrHasHiddenAncestor) continue;
        if ((label.font.pointSize < ((NSFont *)DPDiaValue(label, &DPDiaFontKey, label.font)).pointSize) != DPSmall()) return @"a row's title has the wrong size";
    }
    return nil;
}

static NSMenu *DPRowSizeChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Row Size"];
    [menu addItemWithTitle:@"Compact" action:nil keyEquivalent:@""].representedObject = @"compact";
    [menu addItemWithTitle:@"Small" action:nil keyEquivalent:@""].representedObject = DPSmallRows;
    return menu;
}

DP_PATCH(DPCompactTabRows) {
    .key = @"compactTabRows",
    .order = 77,
    .section = @"Sidebar & Tab Bar",
    .title = @"Compact Tab Rows",
    .detail = @"Make the sidebar's tabs and folders as short as before Dia 1.57, so more fit. Choose Small for rows shorter still, with smaller titles.",
    .symbol = @"rectangle.compress.vertical",
    .tint = @"systemTealColor",
    .choice = @"compactTabRowsSize",
    .defaultChoice = @"compact",
    .choices = DPRowSizeChoices,
    .classes = DPClasses(DPDiaTabListLayout, DPDiaTabListCollection, DPDiaTabList, DPDiaTabGroupCell, DPDiaTabGroupBackground, DPDiaFeatheredLabel, DPDiaTransitioningLabel),
    .install = DPInstallCompactTabRows,
    .apply = DPApplyCompactTabRows,
    .verify = DPVerifyCompactTabRows,
};
