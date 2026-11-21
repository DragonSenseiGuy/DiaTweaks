#import "StdPatch/StdPatch.h"

extern NSInteger DPSafeMode;
extern BOOL DPPaused;  // Every tweak is off and keeps its settings until the pause file goes.
extern BOOL DPPausedAtLaunch;  // Set when Dia started paused, so no patch hooks are installed.
void DPBeginLaunch(void);
void DPLeaveSafeMode(void);
BOOL DPPauseSaved(void);
void DPSetPaused(BOOL paused);
