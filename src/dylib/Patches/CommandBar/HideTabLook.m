#import "Patches/CommandBar/HideTab.h"

static char DPRowLookKey, DPStripLookKey;
static NSArray *DPLastRowLook, *DPLastStripLook;

// Swift SelectionStyle? layout: 0 = translucent fill, 1 = secondary, 2+ (< DPFirstFill) = none, >= DPFirstFill = NSColor*.
const uintptr_t DPFirstFill = 1 << 16;

BOOL DPStyleSelected(uintptr_t style) { return style == 0 || style >= DPFirstFill; }
BOOL DPStyleNone(uintptr_t style) { return style >= 2 && style < DPFirstFill; }

NSView *DPIvarView(NSView *view, const char *name) {
    void **storage = DPIvar(view, name);
    return storage ? (__bridge NSView *)*storage : nil;
}

uintptr_t *DPSelectionStyle(NSView *background) { return DPIvar(background, "selectionStyle"); }
NSView *DPTabShapeView(NSView *background) { return DPIvarView(background, "$__lazy_storage_$_tabShapeView"); }
uint8_t *DPTabShape(NSView *background) { return DPIvar(DPTabShapeView(background), "shape"); }
BOOL DPDrawnSelected(NSView *background) {
    uintptr_t *style = DPSelectionStyle(background);
    return style && DPStyleSelected(*style);
}

BOOL DPInStrip(NSView *view) {
    Class cls = objc_getClass(DPDiaTabStripTabs);
    if (!cls) return NO;
    while (view && ![view isKindOfClass:cls]) view = view.superview;
    return view != nil;
}

void DPNoteLook(NSView *background) {
    if (!DPHiding() || !background.window || !DPIsKind(background.superview, DPDiaTabView)) return;
    uintptr_t *style = DPSelectionStyle(background);
    uint8_t *shape = style && DPStyleSelected(*style) ? DPTabShape(background) : NULL;
    if (!shape) return;
    id fill = *style ? (__bridge id)(void *)*style : NSNull.null;
    if (![fill isKindOfClass:NSColor.class] && fill != NSNull.null) return;
    BOOL strip = DPInStrip(background);
    NSArray *look = @[ fill, @(*shape) ];
    DPSet(background.window, strip ? &DPStripLookKey : &DPRowLookKey, look);
    *(strip ? &DPLastStripLook : &DPLastRowLook) = look;
}

NSArray *DPSelectedLook(NSView *button) {
    BOOL strip = DPInStrip(button);
    return DPGet(button.window, strip ? &DPStripLookKey : &DPRowLookKey) ?: (strip ? DPLastStripLook : DPLastRowLook);
}
