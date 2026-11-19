#import "Patches/CommandBar/HideTab.h"

static char DPFrozenKey, DPFrozenSizeKey;

static NSCollectionViewLayoutAttributes *DPLayout_item(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path);

NSRect DPDiaRowFrame(NSCollectionViewLayout *layout, NSIndexPath *path) {
    SEL sel = @selector(layoutAttributesForItemAtIndexPath:);
    return ((NSCollectionViewLayoutAttributes * (*)(id, SEL, NSIndexPath *)) DPOriginalIMP(layout, sel, (IMP)DPLayout_item))(layout, sel, path).frame;
}

void DPFreezeLists(NSWindow *window) {
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        if (list.window != window || DPGet(list, &DPFrozenKey)) continue;
        NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
        for (NSInteger section = 0; section < list.numberOfSections; section++)
            for (NSInteger item = 0; item < [list numberOfItemsInSection:section]; item++) {
                NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
                NSString *name = DPRowName(list, path);
                NSRect frame = DPDiaRowFrame(list.collectionViewLayout, path);  // As shown, closed up around parked rows.
                if (name && !DPIsLeftOutRow(list, path)) frames[name] = [NSValue valueWithRect:NSOffsetRect(frame, 0, -DPClosedUp(list.collectionViewLayout, frame))];
            }
        DPSet(list, &DPFrozenSizeKey, [NSValue valueWithSize:list.collectionViewLayout.collectionViewContentSize]);
        DPSet(list, &DPFrozenKey, frames);
    }
}

static NSDictionary<NSString *, NSValue *> *DPFrozen(NSCollectionView *list) {
    NSDictionary *frames = DPGet(list, &DPFrozenKey);
    if (frames && !DPHidingATab(list.window)) DPSet(list, &DPFrozenKey, frames = nil);
    return frames;
}

// The tab bar too, which a tab shown again isn't put back in until it lays out.
void DPRelayoutLists(void) {
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        DPFrozen(list);
        [list.collectionViewLayout invalidateLayout];
    }
    for (NSView *strip in DPFindViews(DPDiaTabStripTabs)) strip.needsLayout = YES;
}

static NSCollectionViewLayoutAttributes *DPFrozenAttributes(NSCollectionViewLayout *layout, NSCollectionViewLayoutAttributes *attributes) {
    NSDictionary *frames = attributes ? DPFrozen(layout.collectionView) : nil;
    if (!frames) return DPClosedAttributes(layout, attributes);
    NSString *name = DPRowName(layout.collectionView, attributes.indexPath);
    NSValue *frame = DPHidesTab(DPTabIn(name)) ? nil : frames[name ?: @""];
    attributes = [attributes copy];
    attributes.frame = frame ? frame.rectValue : NSMakeRect(NSMinX(attributes.frame), NSMinY(attributes.frame), NSWidth(attributes.frame), 0);
    attributes.hidden = !frame;
    attributes.alpha = frame ? attributes.alpha : 0;
    return attributes;
}

static NSArray *DPLayout_elements(NSCollectionViewLayout *self, SEL _cmd, NSRect rect) {
    if (!DPFrozen(self.collectionView)) {
        CGFloat up = DPParkedHeight(self);
        if (!up) return DPCallOriginal(DPLayout_elements, self, rect);
        NSMutableArray *shown = [NSMutableArray array];
        for (NSCollectionViewLayoutAttributes *each in DPCallOriginal(DPLayout_elements, self, NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), NSHeight(rect) + up))) {
            NSCollectionViewLayoutAttributes *closed = DPClosedAttributes(self, each);
            if (!closed.hidden && NSIntersectsRect(closed.frame, rect)) [shown addObject:closed];
        }
        return shown;
    }
    NSMutableArray *kept = [NSMutableArray array];
    // Where Dia has a row now may be a few rows from where it's kept. A row left out isn't listed, or its view would
    // still take the pointer.
    for (NSCollectionViewLayoutAttributes *each in DPCallOriginal(DPLayout_elements, self, NSInsetRect(rect, 0, -600))) {
        NSCollectionViewLayoutAttributes *frozen = DPFrozenAttributes(self, each);
        if (!frozen.hidden && NSIntersectsRect(frozen.frame, rect)) [kept addObject:frozen];
    }
    return kept;
}

static NSCollectionViewLayoutAttributes *DPLayout_item(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    return DPFrozenAttributes(self, DPCallOriginal(DPLayout_item, self, path));
}

// Where a row slides in from or out to as the list changes, which would show a hidden row, or slide a kept one.
static NSCollectionViewLayoutAttributes *DPLayout_appearing(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    return DPFrozenAttributes(self, DPCallOriginal(DPLayout_appearing, self, path));
}

static NSCollectionViewLayoutAttributes *DPLayout_disappearing(NSCollectionViewLayout *self, SEL _cmd, NSIndexPath *path) {
    return DPFrozenAttributes(self, DPCallOriginal(DPLayout_disappearing, self, path));
}

static NSSize DPLayout_size(NSCollectionViewLayout *self, SEL _cmd) {
    NSSize size = DPCallOriginal(DPLayout_size, self);
    if (DPFrozen(self.collectionView)) return [DPGet(self.collectionView, &DPFrozenSizeKey) sizeValue];
    return NSMakeSize(size.width, size.height - DPParkedHeight(self));
}

void DPInstallFrozenLists(void) {
    DPInstallParkedRows();
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForItemAtIndexPath:), (IMP)DPLayout_item);
    DPHook(DPDiaTabListLayout, @selector(layoutAttributesForElementsInRect:), (IMP)DPLayout_elements);
    DPHook(DPDiaTabListLayout, @selector(collectionViewContentSize), (IMP)DPLayout_size);
    DPHook(DPDiaTabListLayout, @selector(initialLayoutAttributesForAppearingItemAtIndexPath:), (IMP)DPLayout_appearing);
    DPHook(DPDiaTabListLayout, @selector(finalLayoutAttributesForDisappearingItemAtIndexPath:), (IMP)DPLayout_disappearing);
}
