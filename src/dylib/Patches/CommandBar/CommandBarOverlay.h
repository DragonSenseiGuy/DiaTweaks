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
void DPMakeBlank(NSView *page, NSString *tab, NSString *closing);  // closing: the tab Dia is closing, if any.
NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title);
NSUserDefaults *DPSettings(void);
void DPShowHiddenBars(void);  // Bars hidden for an empty window come back.
BOOL DPHasStrip(NSWindow *window);  // Tabs at the top.

BOOL DPInTabLayout(NSView *view);
NSEvent *DPTabLayoutMouseDown(DPCommandBarOverlay *overlay, NSEvent *event);  // nil if the click stops there.
void DPTabLayoutMouseUp(DPCommandBarOverlay *overlay);

void DPHandOver(DPCommandBarOverlay *overlay);
void DPFinishHandOver(NSWindow *window);
NSEvent *DPHandToDia(NSWindow *window, NSEvent *event, BOOL newTab);  // ⌘T or ⌘L goes on to Dia, which opens its tab or bar.
BOOL DPWaitForDia(NSWindow *window, NSEvent *event, BOOL newTab);     // Pressed before Dia has: noted, and nothing else to do.
void DPDiaCaughtUp(NSWindow *window);                                  // The tab or bar is up.

BOOL DPSparesOn(void);
BOOL DPParkSpare(DPCommandBarOverlay *overlay);
void DPParkIfSpare(DPCommandBarOverlay *overlay);
BOOL DPShowSpare(NSWindow *window);
void DPDropSpare(NSWindow *window);
DPCommandBarOverlay *DPSpareIn(NSWindow *window);
void DPCloseLeftSpares(NSArray<NSString *> *tabIDs, BOOL last);
void DPNoteSpare(NSString *tabID, BOOL parked);       // A spare or a bar's hidden tab: closed at the next launch if still empty.
BOOL DPAdoptSpare(NSWindow *window, NSView *page);    // Dia brought it to the front, on that page: kept as an empty tab.
void DPWantSpare(void);
void DPNotMakingSpare(void);  // A bar the person asked for, so not the spare's even if it comes while one is being made.
