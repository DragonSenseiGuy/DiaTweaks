#import <Foundation/Foundation.h>
#import "Patches/TabTitles/Title.h"

int main(void) {
    @autoreleasepool {
        NSString *raw = @"\u200D\u2061\u200B\u200C\u202C\uFEFF文档标题 - 飞书云文档";
        NSCAssert([DPDisplayTitle(raw) isEqual:@"文档标题 - 飞书云文档"], @"Mixed invisible prefix");
        NSCAssert([raw hasPrefix:@"\u200D"], @"Input string remains intact");

        NSString *prefix = [@"" stringByPaddingToLength:64 withString:@"\u200B" startingAtIndex:0];
        NSCAssert([DPDisplayTitle([prefix stringByAppendingString:@"文档标题"]) isEqual:@"文档标题"], @"Long prefix");

        const unichar stripped[] = {
            0x061C,
            0x200B, 0x200C, 0x200D, 0x200E, 0x200F,
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2060, 0x2061, 0x2062, 0x2063, 0x2064, 0x2065, 0x2066, 0x2067,
            0x2068, 0x2069, 0x206A, 0x206B, 0x206C, 0x206D, 0x206E, 0x206F,
            0xFEFF,
        };
        for (size_t i = 0; i < sizeof(stripped) / sizeof(*stripped); i++) {
            NSString *prefixed = [NSString stringWithFormat:@"%CTitle", stripped[i]];
            NSCAssert([DPDisplayTitle(prefixed) isEqual:@"Title"], @"Stripped code point U+%04X", stripped[i]);
        }

        const unichar kept[] = { 0x0020, 0x00AD, 0x200A, 0x2010, 0x2029, 0x202F, 0x205F, 0x2070, 0xFEFE };
        for (size_t i = 0; i < sizeof(kept) / sizeof(*kept); i++) {
            NSString *prefixed = [NSString stringWithFormat:@"%CTitle", kept[i]];
            NSCAssert(DPDisplayTitle(prefixed) == prefixed, @"Preserved code point U+%04X", kept[i]);
        }

        NSString *plain = @"正常标题";
        NSCAssert(DPDisplayTitle(plain) == plain, @"Plain title returns original string");
        NSCAssert([DPDisplayTitle(@"\u200B标题\u200D后缀") isEqual:@"标题\u200D后缀"], @"Interior invisible characters preserved");

        NSString *onlyInvisible = @"\u200B\uFEFF\u2060";
        NSCAssert(DPDisplayTitle(onlyInvisible) == onlyInvisible, @"All-invisible title stays non-blank");

        NSString *empty = @"";
        NSCAssert(DPDisplayTitle(empty) == empty, @"Empty title");
        NSCAssert(DPDisplayTitle(nil) == nil, @"Nil title");

        NSString *emojiTitle = @"\U0001F4C4 Release Plan";
        NSCAssert(DPDisplayTitle(emojiTitle) == emojiTitle, @"Leading surrogate pair preserved");
        NSCAssert([DPDisplayTitle([@"\u200B\uFEFF" stringByAppendingString:emojiTitle]) isEqual:emojiTitle], @"Non-BMP title after invisible prefix");

        puts("PASS: clean tab title stripping and edge cases");
    }
    return 0;
}
