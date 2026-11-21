#import "StdPatch/StdPatch.h"

extern DPPatch DPPinnedTabCloseButton, DPPinnedTabMinusButton;

id DPViewModelDelegate(NSView *view);
NSView *DPEnclosingTab(NSView *view);
void DPRelayoutTabContents(void);

id DPAttributes(NSView *content);
BOOL DPIsOpenPinned(NSView *content);
BOOL DPClickKeepingTab(NSView *content, void (^click)(void));
BOOL DPCloseKeepingTab(NSView *content);
