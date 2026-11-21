#import "Patches/CommandBar/HideTab.h"

NSString *DPRowName(NSCollectionView *list, NSIndexPath *path) {
    Ivar implVar = list.dataSource ? class_getInstanceVariable(object_getClass(list.dataSource), "_impl") : NULL;
    id impl = implVar ? object_getIvar(list.dataSource, implVar) : nil;
    if (![impl respondsToSelector:@selector(itemIdentifierForIndexPath:)]) return nil;
    return [[impl performSelector:@selector(itemIdentifierForIndexPath:) withObject:path] description];
}

NSString *DPTabIn(NSString *rowName) {
    NSRange tab = rowName ? [rowName rangeOfString:@".tab("] : NSMakeRange(NSNotFound, 0);
    return tab.location == NSNotFound ? nil : DPUUIDsIn([rowName substringFromIndex:tab.location]).firstObject;
}

NSArray<NSString *> *DPListedTabs(NSWindow *window) {
    NSMutableArray *tabs = [NSMutableArray array];
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        if (window && list.window != window) continue;
        for (NSInteger section = 0; section < list.numberOfSections; section++)
            for (NSInteger item = 0; item < [list numberOfItemsInSection:section]; item++)
                [tabs addObject:DPTabIn(DPRowName(list, [NSIndexPath indexPathForItem:item inSection:section])) ?: @""];
    }
    return tabs;
}

// Pinned tabs sit above SectionID.pinned, so resetting regular there leaves only unpinned tabs.
BOOL DPOnlyListedTab(NSString *tab, NSString *closing, NSWindow *window) {
    NSMutableArray<NSString *> *regular = [NSMutableArray array];
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        if (list.window != window) continue;
        for (NSInteger section = 0; section < list.numberOfSections; section++)
            for (NSInteger item = 0; item < [list numberOfItemsInSection:section]; item++) {
                NSString *name = DPRowName(list, [NSIndexPath indexPathForItem:item inSection:section]);
                if ([name containsString:@"SectionID.pinned"]) { [regular removeAllObjects]; continue; }
                NSString *rowTab = DPTabIn(name);
                if (rowTab && ![rowTab isEqual:closing]) [regular addObject:rowTab];
            }
    }
    return !regular.count || (regular.count == 1 && [regular.firstObject isEqual:tab]);
}

NSString *DPVerifyHiddenRows(void) {
    for (NSCollectionView *list in DPFindViews(DPDiaTabListCollection)) {
        if (list.isHiddenOrHasHiddenAncestor) continue;
        for (NSIndexPath *path in list.indexPathsForVisibleItems) {
            NSView *row = [list itemAtIndexPath:path].view;
            NSString *tab = DPTabIn(DPRowName(list, path));
            BOOL hidden = DPHidesTab(tab), drawn = !row.isHiddenOrHasHiddenAncestor && row.alphaValue > 0 && NSHeight(row.frame) > 0;
            if (hidden && drawn) return @"the new tab's row shows while the bar is open";
            if (tab && !hidden && !drawn && NSHeight(row.frame) == 0) return @"a tab's row is still left out";
        }
    }
    return nil;
}
