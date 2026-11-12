#import "TurnOffAI.h"

// Rows hidden through the table itself: the chat suggestion, Settings' Apps and Skills panes, the chat shortcuts, and
// the chat sounds.
#define DPDiaSuggestionsView   "_TtC15BoostCommandBar15SuggestionsView"
#define DPDiaShortcutsPane     "_TtC11Preferences45KeyboardShortcutsPreferencePaneViewController"
#define DPDiaPreferencesTable  "_TtC11Preferences20PreferencesTableView"
#define DPDiaSuggestionCell    "_TtC15BoostCommandBar23SuggestionTableViewCell"
#define DPDiaIconContainer     "_TtC15BoostCommandBar17IconContainerView"

static char DPAIRowsKey, DPPickKey;

static BOOL DPFoldsRows(NSTableView *table) {
    id owner = table.delegate;
    return DPIsKind(owner, DPDiaSuggestionsView) || DPIsKind(owner, DPDiaSettingsSidebar) || DPIsKind(owner, DPDiaShortcutsPane)
        || DPIsKind(owner, DPDiaPreferencesTable);
}

static BOOL DPIsAIRowView(NSTableView *table, NSView *row) {
    BOOL sidebar = DPIsKind(table.delegate, DPDiaSettingsSidebar), suggestions = DPIsKind(table.delegate, DPDiaSuggestionsView);
    return DPFindView(row, ^BOOL(NSView *view) {
        if ([view isKindOfClass:NSImageView.class]) return [view.accessibilityLabel isEqual:@"chat"];
        // A suggestion's text is what was typed or a page's title, which can start with "Chat with" too. Only the icon
        // says the row is Dia's chat.
        if (suggestions) return NO;
        NSString *text = [view isKindOfClass:NSTextField.class] ? [(NSTextField *)view stringValue] : view.accessibilityLabel;
        if (sidebar) return [text isEqual:@"Apps"] || [text isEqual:@"Skills"];
        return DPIsAITitle(text);
    }) != nil;
}

#pragma mark Typed row

static CFTimeInterval gArrowAt;  // When the command bar was last given ↑ or ↓.

static BOOL DPArrowJustPressed(void) { return CACurrentMediaTime() - gArrowAt < 0.3; }

static NSString *DPTrimmed(NSString *text) { return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

static NSView *DPBarOf(NSView *view) {
    while (view && !DPIsKind(view, DPDiaCommandBar)) view = view.superview;
    return view;
}

static NSTextView *DPInputOf(NSTableView *table) {
    return (NSTextView *)DPFindView(DPBarOf(table), ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
}

static NSTableView *DPSuggestionsOf(NSView *input) {
    return (NSTableView *)DPFindView(DPBarOf(input), ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTableView.class] && DPIsKind(((NSTableView *)view).delegate, DPDiaSuggestionsView);
    });
}

static NSView *DPRowCell(NSTableView *table, NSInteger row) {
    return DPFindView([table rowViewAtRow:row makeIfNecessary:YES], ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSuggestionCell); });
}

// The first row showing whose text is exactly what was typed, "— Google" trailing in a label of its own; -1 if none.
static NSInteger DPTypedRow(NSTableView *table, NSString *typed) {
    NSIndexSet *hidden = DPGet(table, &DPAIRowsKey);
    for (NSInteger row = 0; row < table.numberOfRows; row++) {
        if ([hidden containsIndex:row]) continue;
        NSView *cell = DPRowCell(table, row);
        if (DPFindView(cell, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class] && [DPTrimmed(((NSTextField *)view).stringValue) isEqual:typed]; }))
            return row;
    }
    return -1;
}

static NSImageView *DPIconIn(NSView *root) {
    NSView *container = DPFindView(root, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaIconContainer); });
    return (NSImageView *)DPFindView(container, ^BOOL(NSView *view) { return [view isKindOfClass:NSImageView.class]; });
}

// The search engine's name trailing a row's text, "— Google" read as "Google"; nil if the row has no such label.
static NSString *DPTrailingName(NSView *cell, NSString *typed) {
    __block NSString *label;
    DPFindView(cell, ^BOOL(NSView *view) {
        NSString *text = [view isKindOfClass:NSTextField.class] ? DPTrimmed(((NSTextField *)view).stringValue) : nil;
        if (text.length && ![text isEqual:typed]) label = text;
        return label != nil;
    });
    if (label.length < 2 || ![@"—–-" containsString:[label substringToIndex:1]]) return nil;
    return DPTrimmed([label substringFromIndex:1]);
}

// Dia's pick can't be changed from here (a table's selection only shows it), and while it is the hidden chat row the bar
// still looks like chat. So the button and the icon say what Return will do instead, as Dia does when it picks that row.
static void DPShowTypedAction(NSTableView *table) {
    if (!DPTurnOffAI.on || !DPGet(table, &DPPickKey)) return;
    NSView *bar = DPBarOf(table);
    NSString *typed = DPTrimmed(DPInputOf(table).string ?: @"");
    NSInteger row = typed.length ? DPTypedRow(table, typed) : -1;
    NSView *cell = row < 0 ? nil : DPRowCell(table, row);
    NSString *name = DPTrailingName(cell, typed);
    NSImageView *rowIcon = DPIconIn(cell), *fieldIcon = DPIconIn(DPFindView(bar, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarInput); }));
    NSView *button = DPFindView(bar, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaCommandBarButton) && DPFindView(view, ^BOOL(NSView *sub) { return [sub isKindOfClass:NSImageView.class] && DPHasLabel(sub, @"Return"); });
    });
    NSTextField *label = (NSTextField *)DPFindView(button, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    if (name && label && ![label.stringValue isEqual:name]) label.stringValue = name;
    if (rowIcon.image && fieldIcon && fieldIcon.image != rowIcon.image) {
        fieldIcon.image = rowIcon.image;
        fieldIcon.accessibilityLabel = rowIcon.accessibilityLabel;
    }
}

static void DPPickedHiddenRow(NSTableView *table) {
    DPSet(table, &DPPickKey, @YES);
    dispatch_async(dispatch_get_main_queue(), ^{ DPShowTypedAction(table); });
}

// Return on the hidden chat row clicks the row for what was typed. With none it does nothing: chat is cut off, so
// letting it through would only open a chat that can't answer.
static BOOL DPOpenTypedRow(NSTextView *text) {
    NSTableView *table = DPSuggestionsOf(text);
    NSString *typed = DPTrimmed(text.string);
    if (!DPGet(table, &DPPickKey) || text.hasMarkedText || !typed.length) return NO;
    NSInteger row = DPTypedRow(table, typed);
    NSView *cell = row < 0 ? nil : DPRowCell(table, row);
    DPSet(table, &DPPickKey, nil);
    if (!cell) return YES;
    NSEvent *key = NSApp.currentEvent;
    NSPoint middle = [cell convertPoint:NSMakePoint(NSMidX(cell.bounds), NSMidY(cell.bounds)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:middle modifierFlags:key.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask
                                       timestamp:key.timestamp windowNumber:cell.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    [cell mouseDown:click];
    return YES;
}

static BOOL DPInput_command(NSView *self, SEL _cmd, NSTextView *text, SEL command) {
    if (DPTurnOffAI.on && (command == @selector(moveUp:) || command == @selector(moveDown:))) {
        gArrowAt = CACurrentMediaTime();
    } else if (DPTurnOffAI.on && command == @selector(insertNewline:) && DPOpenTypedRow(text)) {
        return YES;
    }
    return DPCallOriginal(DPInput_command, self, text, command);
}

// A hidden row has no view to look at, so the ones hidden here are shown again first, all before anything is drawn.
// Rows are only looked at between updates: asking a table for a view while it updates throws.
static void DPFindAIRows(NSTableView *table) {
    // Hiding and showing rows are updates too.
    static BOOL finding;
    if (finding) return;
    finding = YES;
    // The table keeps its hidden rows in step as rows come and go; what was found before may point past the end now.
    if ([DPGet(table, &DPAIRowsKey) count] && table.hiddenRowIndexes.count)
        [table unhideRowsAtIndexes:table.hiddenRowIndexes withAnimation:NSTableViewAnimationEffectNone];
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (NSInteger row = 0; DPTurnOffAI.on && row < table.numberOfRows; row++) {
        NSView *view = [table rowViewAtRow:row makeIfNecessary:YES];
        if (view && DPIsAIRowView(table, view)) [rows addIndex:row];
    }
    BOOL changed = ![rows isEqualToIndexSet:DPGet(table, &DPAIRowsKey) ?: [NSIndexSet indexSet]];
    DPSet(table, &DPAIRowsKey, rows);
    if (rows.count) [table hideRowsAtIndexes:rows withAnimation:NSTableViewAnimationEffectNone];
    finding = NO;
    if (!DPIsKind(table.delegate, DPDiaSuggestionsView)) return;
    if (!DPTurnOffAI.on) DPSet(table, &DPPickKey, nil);
    else if (!DPGet(table, &DPPickKey) && !DPArrowJustPressed() && [rows containsIndex:table.selectedRow]) DPPickedHiddenRow(table);
    else if (DPGet(table, &DPPickKey)) dispatch_async(dispatch_get_main_queue(), ^{ DPShowTypedAction(table); });
    if (!changed) return;
    for (NSView *view = table; view; view = view.superview)
        if (DPIsKind(view, DPDiaCommandBar)) { view.needsLayout = YES; break; }
}

CGFloat DPHiddenSuggestionsHeight(NSView *suggestions) {
    if (!DPTurnOffAI.on) return 0;
    NSTableView *table = (NSTableView *)DPFindView(suggestions, ^BOOL(NSView *view) { return [view isKindOfClass:NSTableView.class]; });
    NSIndexSet *rows = DPGet(table, &DPAIRowsKey);
    CGFloat height = 0;
    for (NSUInteger row = rows.firstIndex; rows.count && row != NSNotFound; row = [rows indexGreaterThanIndex:row])
        height += [(id<NSTableViewDelegate>)table.delegate tableView:table heightOfRow:row];
    return height;
}

static void DPTable_endUpdates(NSTableView *self, SEL _cmd) {
    DPCallOriginal(DPTable_endUpdates, self);
    if (DPFoldsRows(self)) DPFindAIRows(self);
}

static void DPTable_reloadData(NSTableView *self, SEL _cmd) {
    DPCallOriginal(DPTable_reloadData, self);
    if (DPFoldsRows(self)) DPFindAIRows(self);
}

// Dia picks the command bar's suggestion itself, hidden or not. Landing on the chat row with an arrow key moves on the way
// the key did; picked for what was typed it isn't moved from, which would fill the field with the next suggestion.
static void DPTable_selectRows(NSTableView *self, SEL _cmd, NSIndexSet *rows, BOOL extend) {
    NSInteger from = self.selectedRow;
    DPCallOriginal(DPTable_selectRows, self, rows, extend);
    if (!DPTurnOffAI.on || !DPIsKind(self.delegate, DPDiaSuggestionsView)) return;
    BOOL hidden = rows.count == 1 && [DPGet(self, &DPAIRowsKey) containsIndex:rows.firstIndex];
    if (hidden && !DPArrowJustPressed()) return DPPickedHiddenRow(self);
    DPSet(self, &DPPickKey, nil);
    if (!hidden) return;
    BOOL up = from > (NSInteger)rows.firstIndex && rows.firstIndex > 0;
    if (!up && rows.firstIndex + 1 >= (NSUInteger)self.numberOfRows) up = YES;
    NSResponder *editor = self.window.firstResponder;
    dispatch_async(dispatch_get_main_queue(), ^{ [editor doCommandBySelector:up ? @selector(moveUp:) : @selector(moveDown:)]; });
}

void DPApplyAIRows(void) {
    for (NSView *table in DPFindViews("NSTableView"))
        if (DPFoldsRows((NSTableView *)table)) DPFindAIRows((NSTableView *)table);
}

void DPInstallAIRows(void) {
    DPHookClass(NSTableView.class, @selector(endUpdates), (IMP)DPTable_endUpdates);
    DPHookClass(NSTableView.class, @selector(reloadData), (IMP)DPTable_reloadData);
    DPHookClass(NSTableView.class, @selector(selectRowIndexes:byExtendingSelection:), (IMP)DPTable_selectRows);
    DPHook(DPDiaCommandBarText, @selector(textView:doCommandBySelector:), (IMP)DPInput_command);
}
