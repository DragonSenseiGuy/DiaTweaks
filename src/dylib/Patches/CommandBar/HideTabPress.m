#import "Patches/CommandBar/HideTab.h"

extern DPPatch DPCommandBar;

static void DPSpring(NSView *view, BOOL down) {
    CALayer *layer = view.layer;
    if (!layer) return;
    CATransform3D to = CATransform3DIdentity;
    if (down) {  // About the middle, wherever the layer's anchor is.
        CGFloat x = NSWidth(view.bounds) * (0.5 - layer.anchorPoint.x), y = NSHeight(view.bounds) * (0.5 - layer.anchorPoint.y);
        to = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(x, y, 0), 0.992, 0.992, 1), -x, -y, 0);
    }
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"transform"];
    spring.mass = 1;
    spring.stiffness = 986.96;
    spring.damping = 31.42;
    spring.fromValue = [NSValue valueWithCATransform3D:((CALayer *)layer.presentationLayer ?: layer).transform];
    spring.toValue = [NSValue valueWithCATransform3D:to];
    spring.duration = spring.settlingDuration;
    spring.fillMode = down ? kCAFillModeForwards : kCAFillModeRemoved;  // Pressed holds until let go; once let go, the layer is Dia's again.
    spring.removedOnCompletion = !down;
    [layer addAnimation:spring forKey:@"tabPress"];
}

// The press shows at once, before the click's work, such as making a tab, holds Dia up, and stays in long enough to be
// seen however quick the click. It's let go during the click if Dia tracks it, otherwise later.
static void DPPress(NSView *button, void (^click)(void)) {
    if (!DPCommandBar.on || !DPCommandBarHideTab.on) return click();
    DPSpring(button, YES);
    [CATransaction flush];
    CFTimeInterval pressedAt = CACurrentMediaTime();
    __weak NSView *weak = button;
    void (^letGo)(void) = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, MAX(0, pressedAt + 0.1 - CACurrentMediaTime()) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPSpring(weak, NO); });
    };
    __block id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp handler:^NSEvent *(NSEvent *event) {
        letGo();
        if (monitor) [NSEvent removeMonitor:monitor];
        monitor = nil;
        return event;
    }];
    // A release outside Dia is never seen, so the press doesn't stay in.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!monitor) return;
        [NSEvent removeMonitor:monitor];
        monitor = nil;
        letGo();
    });
    click();
    if (!monitor || NSEvent.pressedMouseButtons & 1) return;
    letGo();
    [NSEvent removeMonitor:monitor];
    monitor = nil;
}

static void DPNewTabButton_pressed(NSView *self, SEL _cmd, NSEvent *event) {
    DPPress(self, ^{ DPCallOriginal(DPNewTabButton_pressed, self, event); });
}

// Over Open New Tabs in Command Bar's own hook, which often handles the click without passing it on, so it's hooked once
// every patch is in.
void DPInstallPress(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ DPHook(DPDiaNewTabButton, @selector(mouseDown:), (IMP)DPNewTabButton_pressed); });
}
