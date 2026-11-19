#import "Patches/LittleDia/Profile.m"

static int failures;

static void label(NSString *what, NSString *profile, NSUInteger profiles, NSString *want) {
    NSString *got = DPOpenInLabel(profile, profiles);
    if (![got isEqual:want]) printf("FAIL %s: \"%s\", want \"%s\"\n", what.UTF8String, got.UTF8String, want.UTF8String), failures++;
}

int main(void) {
    @autoreleasepool {
        label(@"one profile", @"Personal", 1, @"Open in Dia");
        label(@"no profiles known", @"Personal", 0, @"Open in Dia");
        label(@"two profiles", @"Personal", 2, @"Open in Personal");
        label(@"many profiles", @"Work", 5, @"Open in Work");
        label(@"name not known yet", nil, 2, @"Open in Dia");
        label(@"empty name", @"", 2, @"Open in Dia");
        label(@"name of spaces", @"  ", 2, @"Open in Dia");
        label(@"name of Braille's blank cell", @"\u2800", 3, @"Open in Dia");
        label(@"padded name", @" Work\u2800", 2, @"Open in Work");
    }
    if (failures) return 1;
    puts("PASS: the Open button names the profile only when there are several");
    return 0;
}
