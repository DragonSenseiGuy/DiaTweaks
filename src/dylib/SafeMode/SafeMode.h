#import "StdPatch/StdPatch.h"

extern NSInteger DPSafeMode;
extern BOOL DPPaused;
extern BOOL DPPausedAtLaunch;
void DPBeginLaunch(void);
void DPLeaveSafeMode(void);
BOOL DPPauseSaved(void);
void DPSetPaused(BOOL paused);
