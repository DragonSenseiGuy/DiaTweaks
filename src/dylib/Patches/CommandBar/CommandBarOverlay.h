#import "StdPatch/StdPatch.h"

extern DPPatch DPCommandBar, DPCommandBarKeepText;

@interface DPCommandBarOverlay : NSView
@property(weak) NSView *page, *panel;
@property(weak) NSWindow *host;
@property(strong) NSView *shade, *windowBlur;
@property(strong) id openedTab, returnTab, keyMonitor;
@property(strong) NSArray<NSView *> *shownShadows;
@property(strong) NSTimer *watch;
@property(copy) NSString *startURL;
@property CGFloat collapsedHeight, collapsedWidth;
@property CFTimeInterval sizedAt;
@property BOOL picked, overBlank, passingThrough;
- (NSView *)viewUnder:(NSPoint)point;  // What's under the bar there, in its superview's coordinates.
@end

extern char DPOverlayKey;

NSTextView *DPBarText(DPCommandBarOverlay *overlay);
void DPFocusBar(DPCommandBarOverlay *overlay);
void DPShowShade(DPCommandBarOverlay *overlay);
id DPDismiss(DPCommandBarOverlay *overlay, BOOL closing);  // closing: the new tab is about to close.
void DPCancelCommandBar(DPCommandBarOverlay *overlay);
id DPWatchKeys(DPCommandBarOverlay *overlay);
void DPWatch(DPCommandBarOverlay *overlay);
NSMutableSet<NSString *> *DPSplits(NSWindow *window);
NSMutableSet<NSString *> *DPBlanks(NSWindow *window);
NSView *DPBlankPage(NSWindow *window);
NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title);
NSUserDefaults *DPSettings(void);
void DPShowHiddenBars(void);  // Bars hidden for an empty window come back.
BOOL DPHasStrip(NSWindow *window);  // Tabs at the top.

BOOL DPInTabLayout(NSView *view);
NSEvent *DPTabLayoutMouseDown(DPCommandBarOverlay *overlay, NSEvent *event);  // nil if the click stops there.
void DPTabLayoutMouseUp(DPCommandBarOverlay *overlay);
