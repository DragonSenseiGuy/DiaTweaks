#import "Patches/CompactTabRows/CompactTabRows.h"

@interface _TtC7TabList11TabListView : NSView
@end
@implementation _TtC7TabList11TabListView
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return NSDragOperationMove; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info { return YES; }
@end

@interface _TtCC7TabList11TabListView14CollectionView : NSCollectionView
@end
@implementation _TtCC7TabList11TabListView14CollectionView
@end

@interface ArcDraggingWindow : NSWindow
@end
@implementation ArcDraggingWindow
- (BOOL)isVisible { return YES; }
@end

@interface Drag : NSObject
@property NSPoint draggingLocation;
@end
@implementation Drag
@end

NSString *DPChoice(DPPatch *patch) { return patch->defaultChoice; }

#import "Patches/CompactTabRows/CompactTabRows.m"

static id<NSDraggingDestination> DPList(NSArray<NSArray<NSValue *> *> *moves) {
    NSView *tabList = [[NSClassFromString(@(DPDiaTabList)) alloc] initWithFrame:NSMakeRect(0, 0, 200, 600)];
    NSCollectionView *list = [[NSClassFromString(@(DPDiaTabListCollection)) alloc] initWithFrame:NSMakeRect(0, 0, 200, 600)];
    list.collectionViewLayout = [NSCollectionViewFlowLayout new];
    DPSet(list.collectionViewLayout, &DPMovesKey, moves);
    [tabList addSubview:list];
    return (id<NSDraggingDestination>)tabList;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
        DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
        DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
        DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);

        NSArray *moves = @[ @[ [NSValue valueWithRect:NSMakeRect(0, 100, 200, 37)], [NSValue valueWithRect:NSMakeRect(0, 100, 200, 51)] ] ];
        id<NSDraggingDestination> compacted = DPList(moves), plain = DPList(nil);

        NSWindow *dragging = [[ArcDraggingWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskBorderless
                                                                    backing:NSBackingStoreBuffered defer:YES];
        NSView *tab = [[NSView alloc] initWithFrame:NSMakeRect(10, 20, 100, 30)];
        [dragging.contentView addSubview:tab];
        Drag *drag = [Drag new];
        drag.draggingLocation = NSMakePoint(50, 480);
        id<NSDraggingInfo> info = (id<NSDraggingInfo>)drag;
        NSPoint home = tab.frame.origin;

        [compacted draggingUpdated:info];
        NSCAssert(NSMinY(tab.frame) != home.y, @"over compacted rows the tab is put back under the pointer");
        tab.frame = NSMakeRect(home.x, home.y, 100, 30);

        NSCAssert([compacted prepareForDragOperation:info] && [compacted performDragOperation:info], @"drops go through");
        [plain draggingEntered:info];
        NSCAssert(NSEqualPoints(tab.frame.origin, home), @"a drop's offset isn't applied to the next drag");

        [compacted draggingUpdated:info];
        tab.frame = NSMakeRect(home.x, home.y, 100, 30);
        [compacted prepareForDragOperation:info];
        [plain draggingUpdated:info];
        NSCAssert(NSEqualPoints(tab.frame.origin, home), @"nor one a drop left after its first step");

        NSArray *small = @[ @[ [NSValue valueWithRect:NSMakeRect(0, 100, 200, 30)], [NSValue valueWithRect:NSMakeRect(0, 100, 200, 41)] ] ];
        NSCAssert(fabs(DPTabListDiaY(small, 115) - 120.5) < 0.01, @"inside a smaller row");
        NSCAssert(fabs(DPTabListDiaY(small, 140) - 151) < 0.01, @"below a smaller row");
        puts("all drag offset checks passed");
    }
}
