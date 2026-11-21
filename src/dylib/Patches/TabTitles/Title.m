#import "Title.h"

NSString *DPDisplayTitle(NSString *title) {
    NSUInteger length = title.length, prefix = 0;
    while (prefix < length) {
        unichar c = [title characterAtIndex:prefix];
        BOOL invisible = (c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E)
            || (c >= 0x2060 && c <= 0x206F) || c == 0xFEFF;
        if (!invisible) break;
        prefix++;
    }
    return prefix && prefix < length ? [title substringFromIndex:prefix] : title;
}
