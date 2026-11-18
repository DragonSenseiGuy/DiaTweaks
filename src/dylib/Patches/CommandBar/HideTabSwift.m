#import "Patches/CommandBar/HideTab.h"

// The selection code writes Swift fields by their address, so it runs only on the layout it was made for, read from
// Dia's own type records: a tab background's selectionStyle is a SelectionStyle? whose one payload is a
// SelectedTabBackgroundStyle whose one payload is an NSColor, which makes an opaque fill the color's address, the translucent
// one 0 and every other case a small number; its shape view's shape is a two case enum, one byte.

enum { DPClassType = 16, DPEnumType = 18 };  // A Swift type descriptor's kind.

static const uint8_t *DPRelative(const uint8_t *at) {
    int32_t offset = *(const int32_t *)at;
    return offset ? at + offset : NULL;
}

// The mangled name of the type a field is declared with, or of a case's payload.
static const uint8_t *DPFieldType(const uint8_t *type, const char *field) {
    const uint8_t *fields = type ? DPRelative(type + 16) : NULL;
    uint16_t size = fields ? *(const uint16_t *)(fields + 10) : 0;
    uint32_t count = fields ? *(const uint32_t *)(fields + 12) : 0;
    for (uint32_t i = 0; size >= 12 && i < MIN(count, 256); i++) {
        const uint8_t *record = fields + 16 + i * size;
        const char *name = (const char *)DPRelative(record + 8);
        if (name && !strcmp(name, field)) return DPRelative(record + 4);
    }
    return NULL;
}

// The type a mangled name refers to by its descriptor, if nothing but `suffix` follows.
static const uint8_t *DPTypeNamed(const uint8_t *name, const char *suffix) {
    if (!name || (name[0] != 1 && name[0] != 2) || strcmp((const char *)name + 5, suffix)) return NULL;
    const uint8_t *type = DPRelative(name + 1);
    return name[0] == 1 || !type ? type : *(const uint8_t *const *)type;
}

static BOOL DPIsType(const uint8_t *type, uint32_t kind, const char *name, uint32_t payloads, uint32_t empties) {
    const char *called = type ? (const char *)DPRelative(type + 8) : NULL;
    if (!called || (*(const uint32_t *)type & 0x1f) != kind || strcmp(called, name)) return NO;
    return kind != DPEnumType || ((*(const uint32_t *)(type + 20) & 0xffffff) == payloads && *(const uint32_t *)(type + 24) == empties);
}

BOOL DPSelectionLayoutKnown(void) {
    // A Swift class's metadata is its Objective-C class, whose bits at 32 say it is Swift, then its type record at 64.
    const uintptr_t *metadata = (__bridge void *)objc_getClass(DPDiaTabBackground);
    const uint8_t *type = metadata && (metadata[4] & 3) ? (const uint8_t *)metadata[8] : NULL;
    const uint8_t *style = DPTypeNamed(DPFieldType(type, "selectionStyle"), "Sg"), *fill = DPTypeNamed(DPFieldType(style, "primary"), "");
    const uint8_t *shapeView = DPTypeNamed(DPFieldType(type, "$__lazy_storage_$_tabShapeView"), "Sg"), *shape = DPTypeNamed(DPFieldType(shapeView, "shape"), "");
    const uint8_t *color = DPFieldType(fill, "opaque");
    return DPIsType(type, DPClassType, "TabBackgroundView", 0, 0) && DPIsType(style, DPEnumType, "SelectionStyle", 1, 1) &&
           DPIsType(fill, DPEnumType, "SelectedTabBackgroundStyle", 1, 1) && color && !strcmp((const char *)color, "So7NSColorC") &&
           DPIsType(shapeView, DPClassType, "TabShapeView", 0, 0) && DPIsType(shape, DPEnumType, "SelectedTabShape", 0, 2);
}
