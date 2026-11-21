#import "StdPatch/StdPatch.h"
#import "Title.h"

extern DPPatch DPTabTitles;

// ArcWebContents exposes Chromium's title to Dia; filtering it here leaves the page's document.title intact.
static NSString *DPContents_title(id self, SEL _cmd) {
    NSString *title = DPCallOriginal(DPContents_title, self);
    if (!DPTabTitles.on || !title.length) return title;
    return DPDisplayTitle(title);
}

static void DPInstallTabTitles(void) {
    DPHook(DPDiaWebContents, @selector(title), (IMP)DPContents_title);
}

DP_PATCH(DPTabTitles) {
    .key = @"tabTitles",
    .order = 205,
    .title = @"Clean Tab Titles",
    .detail = @"Show a tab’s own title when it starts with invisible characters that make Dia show the domain instead. Experimental.",
    .hint = @"Reload open tabs after changing this setting.",
    .symbol = @"textformat",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaWebContents),
    .install = DPInstallTabTitles,
};
