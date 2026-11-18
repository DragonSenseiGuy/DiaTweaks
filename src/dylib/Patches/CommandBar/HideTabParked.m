#import "Patches/CommandBar/HideTab.h"

static char DPParkedRowsKey;

// A list that isn't held still, such as one made as the tab layout changes, closes up around every hidden tab's row.
BOOL DPIsLeftOutRow(NSCollectionView *list, NSIndexPath *path) { return DPHidesTab(DPTabIn(DPRowName(list, path))); }

CGFloat DPClosedUp(NSCollectionViewLayout *layout, NSRect frame) {
    CGFloat up = 0;
    for (NSValue *row in DPGet(layout, &DPParkedRowsKey))
        if (NSMinY(row.rectValue) < NSMinY(frame)) up += NSHeight(row.rectValue);
    return up;
}

CGFloat DPParkedHeight(NSCollectionViewLayout *layout) { return DPClosedUp(layout, NSMakeRect(0, CGFLOAT_MAX, 0, 0)); }

NSCollectionViewLayoutAttributes *DPClosedAttributes(NSCollectionViewLayout *layout, NSCollectionViewLayoutAttributes *attributes) {
    if (!attributes || !DPGet(layout, &DPParkedRowsKey)) return attributes;
    attributes = [attributes copy];
    NSRect frame = attributes.frame;
    if (attributes.representedElementCategory == NSCollectionElementCategoryItem && DPIsLeftOutRow(layout.collectionView, attributes.indexPath)) {
        attributes.frame = NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), 0);
        attributes.hidden = YES;
        attributes.alpha = 0;
    } else {
        attributes.frame = NSOffsetRect(frame, 0, -DPClosedUp(layout, frame));
    }
    return attributes;
}

static void DPLayout_prepare(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepare, self);
    if (!DPParkingAny() && !DPHidingATab(self.collectionView.window) && !DPGet(self, &DPParkedRowsKey)) return;
    NSCollectionView *list = self.collectionView;
    NSMutableArray<NSValue *> *rows = [NSMutableArray array];
    for (NSInteger section = 0; section < list.numberOfSections; section++)
        for (NSInteger item = 0; item < [list numberOfItemsInSection:section]; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
            if (DPIsLeftOutRow(list, path)) [rows addObject:[NSValue valueWithRect:DPDiaRowFrame(self, path)]];
        }
    DPSet(self, &DPParkedRowsKey, rows.count ? rows : nil);
}

void DPInstallParkedRows(void) { DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepare); }
