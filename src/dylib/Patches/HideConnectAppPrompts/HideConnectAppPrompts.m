#import "HideConnectAppPrompts.h"
#import "Patches/TurnOffAI/TurnOffAI.h"
#import <objc/message.h>

static Class DPDialogPanelClass;
static Class DPDialogButtonClass;
static Class DPDialogPanelVCClass;
static Class DPDialogPanelWCClass;
static char DPDismissedKey;

static BOOL DPSuppressConnectPrompts(void) {
    return DPHideConnectAppPrompts.on || DPTurnOffAI.on;
}

static BOOL DPIsConnectTitle(NSString *raw) {
    if (![raw isKindOfClass:NSString.class]) return NO;
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![text hasSuffix:@" to Dia?"]) return NO;
    NSUInteger prefixLen = [text hasPrefix:@"Connect "] ? 8 : [text hasPrefix:@"Reconnect "] ? 10 : 0;
    if (!prefixLen || text.length <= prefixLen + 8) return NO;
    NSString *app = [[text substringWithRange:NSMakeRange(prefixLen, text.length - prefixLen - 8)]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return app.length > 0;
}

static BOOL DPIsDeclineTitle(NSString *raw) {
    if (![raw isKindOfClass:NSString.class]) return NO;
    NSString *text = [[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        stringByReplacingOccurrencesOfString:@"\u2019" withString:@"'"];
    NSString *lower = text.lowercaseString;
    return [lower hasPrefix:@"don't connect"] || [lower isEqualToString:@"not now"];
}

static BOOL DPIsConnectAppPrompt(NSView *panel) {
    if (!panel || !DPDialogPanelClass || ![panel isKindOfClass:DPDialogPanelClass]) return NO;
    return DPFindView(panel, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextField.class] && !view.hidden && DPIsConnectTitle(((NSTextField *)view).stringValue);
    }) != nil;
}

static NSButton *DPDeclineButtonIn(NSView *panel) {
    if (!panel) return nil;
    return (NSButton *)DPFindView(panel, ^BOOL(NSView *view) {
        if (![view isKindOfClass:NSButton.class]) return NO;
        if (DPDialogButtonClass && ![view isKindOfClass:DPDialogButtonClass]) return NO;
        NSButton *button = (NSButton *)view;
        return button.target == panel && button.action == @selector(handleButton:) && button.tag != 0 && DPIsDeclineTitle(button.title);
    });
}

static NSView *DPConnectPromptIn(NSView *root, NSButton **declineOut) {
    NSView *panel = DPFindView(root, ^BOOL(NSView *view) { return DPIsConnectAppPrompt(view); });
    if (!panel) return nil;
    NSButton *decline = DPDeclineButtonIn(panel);
    if (!decline) return nil;
    if (declineOut) *declineOut = decline;
    return panel;
}

static void DPHidePromptWindow(NSWindow *window, NSView *panel) {
    window.animationBehavior = NSWindowAnimationBehaviorNone;
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    panel.hidden = YES;
}

static void DPHideOverlayHost(NSView *panel) {
    if (DPDialogPanelVCClass) {
        for (NSView *up = panel.superview; up; up = up.superview) {
            if ([up.nextResponder isKindOfClass:DPDialogPanelVCClass]) {
                up.hidden = YES;
                break;
            }
        }
    }
    panel.hidden = YES;
}

// Route through Dia's own decline button so Swift continuations and cooldown state clean up without connecting.
static void DPScheduleDecline(NSView *panel, NSButton *decline) {
    if (!panel || !decline || [DPGet(panel, &DPDismissedKey) boolValue]) return;
    DPSet(panel, &DPDismissedKey, @YES);
    __weak NSView *weakPanel = panel;
    __weak NSButton *weakDecline = decline;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *p = weakPanel;
        NSButton *b = weakDecline;
        if (!p || !b || (!p.window && !p.superview)) return;
        if (b.target != p || b.action != @selector(handleButton:) || ![p respondsToSelector:@selector(handleButton:)]) return;
        ((void (*)(id, SEL, id))objc_msgSend)(p, @selector(handleButton:), b);
    });
}

static void DPWindow_beginSheet(NSWindow *self, SEL _cmd, NSWindow *sheet, void (^handler)(NSModalResponse)) {
    if (DPSuppressConnectPrompts() && sheet) {
        NSButton *decline = nil;
        NSView *panel = DPConnectPromptIn(sheet.contentView, &decline);
        if (panel) {
            DPHidePromptWindow(sheet, panel);
            DPCallOriginal(DPWindow_beginSheet, self, sheet, handler);
            DPScheduleDecline(panel, decline);
            return;
        }
    }
    DPCallOriginal(DPWindow_beginSheet, self, sheet, handler);
}

static BOOL DPSuppressPanelWindow(NSWindow *window) {
    if (!DPSuppressConnectPrompts() || !DPDialogPanelWCClass) return NO;
    if (![window.windowController isKindOfClass:DPDialogPanelWCClass]) return NO;
    NSButton *decline = nil;
    NSView *panel = DPConnectPromptIn(window.contentView, &decline);
    if (!panel) return NO;
    DPHidePromptWindow(window, panel);
    DPScheduleDecline(panel, decline);
    return YES;
}

static void DPWindow_makeKeyAndOrderFront(NSWindow *self, SEL _cmd, id sender) {
    if (DPSuppressPanelWindow(self)) return;
    DPCallOriginal(DPWindow_makeKeyAndOrderFront, self, sender);
}

static void DPWindow_orderFront(NSWindow *self, SEL _cmd, id sender) {
    if (DPSuppressPanelWindow(self)) return;
    DPCallOriginal(DPWindow_orderFront, self, sender);
}

static void DPDialogPanelVC_viewDidLoad(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPDialogPanelVC_viewDidLoad, self);
    if (!DPSuppressConnectPrompts()) return;
    NSButton *decline = nil;
    NSView *panel = DPConnectPromptIn(self.view, &decline);
    if (!panel) return;
    self.view.hidden = YES;
    panel.hidden = YES;
}

static void DPDialogPanel_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPDialogPanel_viewDidMoveToWindow, self);
    if (!self.window || !DPSuppressConnectPrompts()) return;
    if (DPDialogPanelWCClass && [self.window.windowController isKindOfClass:DPDialogPanelWCClass]) return;
    if (!DPIsConnectAppPrompt(self)) return;
    NSButton *decline = DPDeclineButtonIn(self);
    if (!decline) return;
    DPHideOverlayHost(self);
    DPScheduleDecline(self, decline);
}

static void DPDismissInWindow(NSWindow *window) {
    if (!window.contentView) return;
    NSButton *decline = nil;
    NSView *panel = DPConnectPromptIn(window.contentView, &decline);
    if (!panel) return;
    if (DPDialogPanelWCClass && [window.windowController isKindOfClass:DPDialogPanelWCClass])
        DPHidePromptWindow(window, panel);
    else
        DPHideOverlayHost(panel);
    DPScheduleDecline(panel, decline);
}

void DPDismissConnectAppPrompts(void) {
    if (!DPDialogPanelClass || !DPSuppressConnectPrompts()) return;
    for (NSWindow *window in NSApp.windows.copy) {
        DPDismissInWindow(window);
        for (NSWindow *sheet in window.sheets.copy) DPDismissInWindow(sheet);
    }
}

static void DPInstallHideConnectAppPrompts(void) {
    DPDialogPanelClass = objc_getClass(DPDiaDialogPanel);
    DPDialogButtonClass = objc_getClass(DPDiaDialogButton);
    DPDialogPanelVCClass = objc_getClass(DPDiaDialogPanelVC);
    DPDialogPanelWCClass = objc_getClass(DPDiaDialogPanelWC);
    DPHookClass(NSWindow.class, @selector(beginSheet:completionHandler:), (IMP)DPWindow_beginSheet);
    DPHookClass(NSWindow.class, @selector(makeKeyAndOrderFront:), (IMP)DPWindow_makeKeyAndOrderFront);
    DPHookClass(NSWindow.class, @selector(orderFront:), (IMP)DPWindow_orderFront);
    DPHook(DPDiaDialogPanelVC, @selector(viewDidLoad), (IMP)DPDialogPanelVC_viewDidLoad);
    DPHook(DPDiaDialogPanel, @selector(viewDidMoveToWindow), (IMP)DPDialogPanel_viewDidMoveToWindow);
}

static void DPApplyHideConnectAppPrompts(DPPatch *patch) {
    if (DPSuppressConnectPrompts()) DPDismissConnectAppPrompts();
}

DP_PATCH(DPHideConnectAppPrompts) {
    .key = @"hideConnectAppPrompts",
    .order = 220,
    .title = @"Hide Connect App Prompt",
    .detail = @"Stop the “Connect to Dia?” prompts that ask to link logged-in apps for Chat. You can still connect apps from Dia’s Apps settings.",
    .symbol = @"app.connected.to.app.below.fill link.circle.fill",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .coveredBy = @"turnOffAI",
    .classes = DPClasses(DPDiaDialogPanel, DPDiaDialogButton, DPDiaDialogPanelVC, DPDiaDialogPanelWC),
    .install = DPInstallHideConnectAppPrompts,
    .apply = DPApplyHideConnectAppPrompts,
};
