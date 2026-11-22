#import "StdPatch/StdPatch.h"

typedef struct { uint32_t value, mask; } DPSkipInstruction;
typedef struct {
    const DPSkipInstruction *signature;
    NSUInteger length;
    uint32_t *match;
} DPSkipPattern;

BOOL DPSkipFindPatterns(DPSkipPattern *patterns, NSUInteger count);
BOOL DPSkipWriteCode(uint32_t *site, uint32_t expected, uint32_t value);
BOOL DPSkipAccountStartup(void);
void DPSkipAccountMenus(void);
void DPSkipAccountSettings(void);
NSString *DPSkipVerifyAccountSettings(void);
