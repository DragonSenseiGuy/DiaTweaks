#import "StdPatch/StdPatch.h"

// moves: per row, @[frame now, frame as Dia laid it out].
CGFloat DPTabListDiaY(NSArray<NSArray<NSValue *> *> *moves, CGFloat y);
id<NSDraggingInfo> DPDraggingInfoAt(id<NSDraggingInfo> info, NSPoint location);
void DPPlaceDraggedTab(void);
// The height a row has with the tweak's current size, 37 pt when it's off.
CGFloat DPCompactRowHeight(void);
