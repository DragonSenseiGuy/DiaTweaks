#import "StdPatch/StdPatch.h"

// Where Dia has the pointer on the tab list, which it works out from the rows as it laid them out. moves holds each
// row's frame now and as Dia laid it out, as @[now, then].
CGFloat DPTabListDiaY(NSArray<NSArray<NSValue *> *> *moves, CGFloat y);
// info, with the pointer at location (in the window) in place of where it is.
id<NSDraggingInfo> DPDraggingInfoAt(id<NSDraggingInfo> info, NSPoint location);
