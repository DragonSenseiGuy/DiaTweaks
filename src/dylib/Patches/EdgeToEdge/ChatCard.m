#import "EdgeToEdge.h"

NSView *DPRoundedContent(NSView *container) {
    return DPFindView(container, ^BOOL(NSView *v) { return v != container && v.layer.masksToBounds && v.layer.cornerRadius > 0; });
}

// Dia allows the docked side chat down to 320 pt even on wide windows, where 320 <= width / 4.
static BOOL DPIsChatCard(NSView *v, NSSize size) {
    return !v.hidden && v.layer.masksToBounds && v.layer.cornerRadius > 0
        && NSWidth(v.bounds) > MIN(size.width / 4, 240) && NSHeight(v.bounds) > size.height / 2;
}

NSView *DPChatCard(NSView *container) {
    NSView *content = DPRoundedContent(container);
    if (!content) return nil;
    NSSize size = content.bounds.size;
    for (NSView *root in content.subviews) {
        if (root.hidden) continue;
        for (NSView *host in root.subviews) {
            if (host.hidden || (NSMinX(host.frame) < 2 && NSMinY(host.frame) < 2)) continue;
            if (DPIsChatCard(host, size)) return host;
            for (NSView *card in host.subviews) if (DPIsChatCard(card, size)) return card;
        }
    }
    return nil;
}
