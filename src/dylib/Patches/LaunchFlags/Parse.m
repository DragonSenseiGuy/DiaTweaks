#import "LaunchFlags.h"

static BOOL DPIsSpace(unichar c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }

static BOOL DPIsASCIIAlnum(unichar c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'); }

static BOOL DPIsSwitchNameChar(unichar c) { return DPIsASCIIAlnum(c) || c == '-' || c == '_' || c == '.'; }

static BOOL DPIsValidLaunchFlag(NSString *token) {
    if (token.length < 3 || ![token hasPrefix:@"--"]) return NO;
    if (!DPIsASCIIAlnum([token characterAtIndex:2])) return NO;
    NSRange eq = [token rangeOfString:@"="];
    NSUInteger nameEnd = eq.location == NSNotFound ? token.length : eq.location;
    for (NSUInteger i = 2; i < nameEnd; i++)
        if (!DPIsSwitchNameChar([token characterAtIndex:i])) return NO;
    for (NSUInteger i = nameEnd; i < token.length; i++) {
        unichar c = [token characterAtIndex:i];
        if (c == '\0' || c == '\r' || c == '\n') return NO;
    }
    return YES;
}

NSArray<NSString *> *DPParseLaunchFlags(NSString *text, NSArray<NSString *> *__autoreleasing *ignored, BOOL *unclosedQuote) {
    if (unclosedQuote) *unclosedQuote = NO;
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    NSMutableArray<NSString *> *bad = ignored ? [NSMutableArray array] : nil;
    if (![text isKindOfClass:NSString.class] || !text.length) {
        if (ignored) *ignored = @[];
        return flags;
    }

    NSUInteger length = text.length, i = 0;
    while (i < length) {
        while (i < length && DPIsSpace([text characterAtIndex:i])) i++;
        if (i >= length) break;
        if ([text characterAtIndex:i] == '#') {
            while (i < length && [text characterAtIndex:i] != '\n') i++;
            continue;
        }

        NSMutableString *token = [NSMutableString string];
        unichar quote = 0;
        while (i < length) {
            unichar c = [text characterAtIndex:i++];
            if (quote) {
                if (c == quote) {
                    quote = 0;
                } else if (quote == '"' && c == '\\' && i < length) {
                    unichar next = [text characterAtIndex:i];
                    if (next == '"' || next == '\\') {
                        [token appendFormat:@"%C", next];
                        i++;
                    } else {
                        [token appendString:@"\\"];
                    }
                } else if (c != '\0') {
                    [token appendFormat:@"%C", c];
                }
                continue;
            }
            if (DPIsSpace(c)) break;
            if (c == '\'' || c == '"') {
                quote = c;
            } else if (c == '\\' && i < length) {
                unichar next = [text characterAtIndex:i];
                if (DPIsSpace(next) || next == '\'' || next == '"' || next == '\\') {
                    if (next != '\r' && next != '\n') [token appendFormat:@"%C", next];
                    i++;
                } else {
                    [token appendString:@"\\"];
                }
            } else if (c != '\0') {
                [token appendFormat:@"%C", c];
            }
        }

        if (quote) {
            if (unclosedQuote) *unclosedQuote = YES;
            break;
        }
        if (!token.length) continue;
        if (DPIsValidLaunchFlag(token)) {
            if (![flags containsObject:token]) [flags addObject:token];
        } else {
            [bad addObject:token];
        }
    }

    if (ignored) *ignored = bad;
    return flags;
}

NSString *DPFormatLaunchFlagsArray(NSArray *items) {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *s = item;
        if (!s.length) continue;
        BOOL quote = [s hasPrefix:@"#"] || [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound
            || [s containsString:@"\""] || [s containsString:@"'"] || [s containsString:@"\\"];
        if (!quote) {
            [lines addObject:s];
            continue;
        }
        NSString *escaped = [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
            stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        [lines addObject:[NSString stringWithFormat:@"\"%@\"", escaped]];
    }
    return [lines componentsJoinedByString:@"\n"];
}
