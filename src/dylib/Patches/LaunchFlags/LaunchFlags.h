#import "StdPatch/StdPatch.h"

extern DPPatch DPLaunchFlags;

NSArray<NSString *> *DPParseLaunchFlags(NSString *text, NSArray<NSString *> *__autoreleasing *ignored, BOOL *unclosedQuote);
NSString *DPFormatLaunchFlagsArray(NSArray *items);
NSString *DPLaunchFlagsSavedText(void);
void DPLaunchFlagsSaveText(NSString *text);
NSArray<NSString *> *DPLaunchFlagsLaunched(void);
NSArray<NSView *> *DPLaunchFlagsRows(void);
