#import "ProfileColorPicker.h"

@implementation DPProfileColorWell
- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    if (!newWindow && self.isActive) [self deactivate];
    [super viewWillMoveToWindow:newWindow];
}
- (void)dealloc {
    if (self.isActive) [self deactivate];
}
@end

@interface DPProfileHexField ()
@property (weak) DPProfileColorRow *row;
@end

@implementation DPProfileHexField
- (void)controlTextDidChange:(NSNotification *)note {
    NSString *canonical = nil;
    if (DPColorFromSixDigitHex(self.stringValue, &canonical)) [self.row applyHex:canonical fromField:YES];
}

- (void)commitText {
    NSString *trimmed = [self.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return [self.row clearColor];
    NSString *canonical = nil;
    if (DPColorFromHex(trimmed, &canonical)) {
        self.stringValue = canonical;
        [self.row applyHex:canonical fromField:YES];
    } else {
        self.stringValue = DPSavedProfileHexForSpace(self.row.spaceID) ?: @"";
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    [self commitText];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector {
    if (selector == @selector(insertNewline:)) {
        [self commitText];
        [self.window makeFirstResponder:nil];
        return YES;
    }
    if (selector == @selector(cancelOperation:)) {
        self.stringValue = DPSavedProfileHexForSpace(self.row.spaceID) ?: @"";
        [self.window makeFirstResponder:nil];
        return YES;
    }
    return NO;
}
@end

@implementation DPProfileColorRow {
    BOOL _syncing;
}

static NSColor *DPPlaceholderWellColor(void) {
    return [NSColor colorWithSRGBRed:0.78 green:0.78 blue:0.80 alpha:1.0];
}

- (instancetype)initWithSpaceID:(NSString *)spaceID font:(NSFont *)font textColor:(NSColor *)textColor {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _spaceID = [spaceID copy];

    NSTextField *label = [NSTextField labelWithString:@"Custom Color"];
    label.font = font;
    label.textColor = textColor;

    _well = [[DPProfileColorWell alloc] initWithFrame:NSMakeRect(0, 0, 52, 24)];
    _well.colorWellStyle = NSColorWellStyleExpanded;
    _well.supportsAlpha = NO;
    _well.continuous = YES;
    _well.target = self;
    _well.action = @selector(wellChanged:);
    _well.accessibilityLabel = @"Custom profile color";

    _hexField = [DPProfileHexField textFieldWithString:@""];
    _hexField.row = self;
    _hexField.delegate = _hexField;
    _hexField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _hexField.alignment = NSTextAlignmentCenter;
    _hexField.bezelStyle = NSTextFieldRoundedBezel;
    _hexField.placeholderString = @"#RRGGBB";
    _hexField.accessibilityLabel = @"Custom profile color hex";

    NSImage *clearIcon = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Clear custom color"];
    _clearButton = [NSButton buttonWithImage:clearIcon target:self action:@selector(clearColor)];
    _clearButton.bordered = NO;
    _clearButton.bezelStyle = NSBezelStyleInline;
    _clearButton.contentTintColor = NSColor.secondaryLabelColor;
    _clearButton.toolTip = @"Use preset color";
    _clearButton.accessibilityLabel = @"Clear custom color";

    NSStackView *controls = [NSStackView stackViewWithViews:@[ _well, _hexField, _clearButton ]];
    controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controls.alignment = NSLayoutAttributeCenterY;
    controls.spacing = 6;

    for (NSView *v in @[ label, controls ]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:42],
        [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [controls.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_well.widthAnchor constraintEqualToConstant:52],
        [_well.heightAnchor constraintEqualToConstant:24],
        [_hexField.widthAnchor constraintEqualToConstant:86],
        [_clearButton.widthAnchor constraintEqualToConstant:18],
        [_clearButton.heightAnchor constraintEqualToConstant:18],
    ]];
    [self syncFromDefaults:YES];
    return self;
}

- (void)syncFromDefaults:(BOOL)forceField {
    _syncing = YES;
    NSString *hex = DPSavedProfileHexForSpace(self.spaceID);
    NSColor *color = DPColorFromHex(hex, NULL);
    self.well.color = color ?: DPPlaceholderWellColor();
    if (forceField || !self.hexField.currentEditor) self.hexField.stringValue = hex ?: @"";
    self.clearButton.hidden = (color == nil);
    _syncing = NO;
}

- (void)wellChanged:(id)sender {
    if (_syncing) return;
    NSString *hex = DPHexFromColor(self.well.color);
    if (hex) [self applyHex:hex fromField:NO];
}

- (void)applyHex:(NSString *)canonical fromField:(BOOL)fromField {
    NSColor *color = DPColorFromHex(canonical, &canonical);
    if (!color || !self.spaceID) return;
    DPSetProfileHexForSpace(self.spaceID, canonical);
    _syncing = YES;
    if (!fromField) self.hexField.stringValue = canonical;
    self.well.color = color;
    self.clearButton.hidden = NO;
    _syncing = NO;
    DPRefreshProfileColors();
}

- (void)clearColor {
    if (self.well.isActive) [self.well deactivate];
    if (self.spaceID) DPSetProfileHexForSpace(self.spaceID, nil);
    [self syncFromDefaults:YES];
    DPRefreshProfileColors();
}
@end
