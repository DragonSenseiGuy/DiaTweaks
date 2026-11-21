#import "Patches/CommandBar/HideTab.h"
#import "Patches/CommandBar/Tabs.h"

static char DPTakenKey;
static uintptr_t DPNoSelection;

@interface DPTakenSelection : NSObject
@property uintptr_t selection, written;
@end

@implementation DPTakenSelection
- (void)dealloc {
    if (self.selection) CFRelease((CFTypeRef)(void *)self.selection);
}
@end

static uintptr_t DPFindNoSelection(void) {
    for (NSView *view in DPFindViews(DPDiaTabBackground)) {
        uintptr_t *style = DPSelectionStyle(view);
        if (style && DPStyleNone(*style)) return DPNoSelection = *style;
    }
    return 0;
}

void DPUnselectFrontTab(NSView *background, BOOL standingIn) {
    uintptr_t *style = DPSelectionStyle(background);
    if (style && DPStyleNone(*style)) DPNoSelection = *style;
    if (standingIn && !DPNoSelection) DPFindNoSelection();
    if (!standingIn || !style || !DPStyleSelected(*style) || !DPNoSelection || !DPIsKind(background.superview, DPDiaTabView)) return;
    DPTakenSelection *taken = DPGet(background, &DPTakenKey) ?: [DPTakenSelection new];
    if (taken.selection) CFRelease((CFTypeRef)(void *)taken.selection);
    taken.selection = *style;
    taken.written = *style = DPNoSelection;
    DPSet(background, &DPTakenKey, taken);
}

void DPGiveBackSelection(NSView *background) {
    DPTakenSelection *taken = DPGet(background, &DPTakenKey);
    if (!taken) return;
    DPSet(background, &DPTakenKey, nil);
    uintptr_t *style = DPSelectionStyle(background);
    if (style && *style == taken.written && [DPStripTabID(background.superview) isEqual:DPActiveTabID(background.window)]) {
        *style = taken.selection;
        taken.selection = 0;
    }
    DPTabShapeView(background).needsLayout = YES;
    background.needsLayout = background.needsDisplay = YES;
}

BOOL DPHoldsSelection(NSView *background) { return DPGet(background, &DPTakenKey) != nil; }

static void DPTabBackground_prepareForReuse(NSView *self, SEL _cmd) {
    DPSet(self, &DPTakenKey, nil);
    DPCallOriginal(DPTabBackground_prepareForReuse, self);
}

void DPInstallFrontTab(void) { DPHook(DPDiaTabBackground, @selector(prepareForReuse), (IMP)DPTabBackground_prepareForReuse); }
