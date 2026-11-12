#import "StdPatch/StdPatch.h"

extern DPPatch DPSidebarOnRight;

// Dia lays the window out as usual and these mirror it: every view between the sidebar, the pages and the view that
// holds them all (the root) moves to the other side of its superview, so the sidebar ends up on the right.
CGFloat DPMirroredX(NSView *superview, CGFloat x, CGFloat width);
void DPRegisterSidebar(NSView *sidebar, BOOL force);
NSView *DPRootFor(NSView *view);  // The root a view is mirrored in, or nil.
void DPJoinChain(NSView *view);
BOOL DPHasSidebarIn(NSWindow *window);  // Whether this patch holds a sidebar in the window, open or not.
NSView *DPDockedSidebarIn(NSWindow *window);  // nil unless it's mirrored, open and docked.
void DPUnmirrorWindows(void);
void DPInstallRoots(void);
void DPInstallMirror(void);
NSEvent *DPMirroredEvent(NSEvent *event);  // The pointer across the window, as if the sidebar were on the left.
void DPInstallResize(void);
void DPInstallHover(void);
// Dia's window buttons leave the sidebar for a strip in the window's top left corner that shows on hover.
BOOL DPSidebarOnRightTakesLights(NSWindow *window);
NSView *DPLightsStripIn(NSWindow *window);
BOOL DPDiaLightsShowIn(NSWindow *window);  // Dia's own buttons show somewhere in the window.
void DPUpdateLights(NSWindow *window);
void DPScheduleLights(NSWindow *window);
void DPInstallLights(void);
