#import "Startup.h"

// Dia 1.55.1 (89833) – 1.59.0 (91402), arm64. Unknown or ambiguous code stays untouched.
// initializeAuth() has finished initializing auth here. With no user it waits for sign-in; otherwise it returns .restored.
// Async frame offsets (x22 loads), branch displacements and the milestone enum argument (mov w0, #imm) are masked.
static const DPSkipInstruction DPLaunch[] = {
    {0xb24403bd, 0xffffffff},
    {0xd10083ff, 0xffffffff},
    {0xa9017bfd, 0xffffffff},
    {0xf90007f6, 0xffffffff},
    {0x910043fd, 0xffffffff},
    {0x394002c8, 0xffc003ff},
    {0x7100051f, 0xffffffff},
    {0x54000001, 0xff00001f},
    {0xf94002c0, 0xffc003ff},
    {0xf94002d4, 0xffc003ff},
    {0x94000000, 0xfc000000},
    {0x52800000, 0xffe0001f},
    {0x94000000, 0xfc000000},
    {0xf94006c1, 0xffffffff},
    {0x52800040, 0xffffffff},
    {0xd2800014, 0xffffffff},
    {0xa9417bfd, 0xffffffff},
    {0x9243fbbd, 0xffffffff},
    {0x910083ff, 0xffffffff},
    {0xd61f0020, 0xffffffff},
};

// Window creation separately rejects a signed-out user. Keep the readiness and termination checks around it.
// Field/async-frame offsets and branch displacements are masked so layout shifts across Dia releases still match uniquely.
static const DPSkipInstruction DPWindow[] = {
    {0xf9400114, 0xffc003ff},
    {0xb4000014, 0xff00001f},
    {0xaa1403e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0x94000000, 0xfc000000},
    {0xaa0003f3, 0xffffffff},
    {0xaa1403e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0x36000013, 0xfff8001f},
    {0xf94002d4, 0xffc003ff},
    {0xf94002c0, 0xffc003ff},
    {0x52800021, 0xffffffff},
};

static const uint32_t DPNop = 0xd503201f;

BOOL DPSkipAccountStartup(void) {
    DPSkipPattern patterns[] = {
        {DPLaunch, sizeof DPLaunch / sizeof *DPLaunch, NULL},
        {DPWindow, sizeof DPWindow / sizeof *DPWindow, NULL},
    };
    if (!DPSkipFindPatterns(patterns, sizeof patterns / sizeof *patterns)) return NO;
    uint32_t *launch = patterns[0].match + 7, *window = patterns[1].match + 8;
    uint32_t origLaunch = *launch, origWindow = *window;
    if ((origLaunch & DPLaunch[7].mask) != DPLaunch[7].value || (origWindow & DPWindow[8].mask) != DPWindow[8].value) return NO;
    if (!DPSkipWriteCode(launch, origLaunch, DPNop)) return NO;
    if (DPSkipWriteCode(window, origWindow, DPNop)) return YES;
    DPSkipWriteCode(launch, DPNop, origLaunch);
    return NO;
}
