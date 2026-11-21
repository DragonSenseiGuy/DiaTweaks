#import "Patches/Peek/Peek.h"

// Normalize status text and click URLs identically without handing paths to NSURL, whose double-escaping varies across macOS versions.
NSString *DPPeekLinkKey(NSString *address) {
    static NSCharacterSet *legal, *delims;
    static NSRegularExpression *barePercent;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        legal = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#@!$&'()*+,;=%"];
        delims = [NSCharacterSet characterSetWithCharactersInString:@"/?#"];
        barePercent = [NSRegularExpression regularExpressionWithPattern:@"%(?![0-9A-Fa-f]{2})" options:0 error:nil];
    });
    if ([address hasPrefix:@"https://"]) address = [address substringFromIndex:8];
    if ([address hasPrefix:@"http://"]) address = [address substringFromIndex:7];
    NSUInteger end = [address rangeOfCharacterFromSet:delims].location;
    if (end == NSNotFound) end = address.length;
    NSString *host = [address substringToIndex:end], *rest = [address substringFromIndex:end];
    if (![host canBeConvertedToEncoding:NSASCIIStringEncoding])
        host = [[NSURL URLWithString:[@"http://" stringByAppendingString:host]].absoluteString substringFromIndex:7] ?: host;
    if ([rest containsString:@"%"])
        rest = [barePercent stringByReplacingMatchesInString:rest options:0 range:NSMakeRange(0, rest.length) withTemplate:@"%25"];
    NSRange hash = [rest rangeOfString:@"#"];
    if (hash.length) rest = [[rest substringToIndex:NSMaxRange(hash)] stringByAppendingString:[[rest substringFromIndex:NSMaxRange(hash)] stringByReplacingOccurrencesOfString:@"#" withString:@"%23"]];
    address = [host stringByAppendingString:[rest stringByAddingPercentEncodingWithAllowedCharacters:legal] ?: rest];
    return [address hasSuffix:@"/"] ? [address substringToIndex:address.length - 1] : address;
}
