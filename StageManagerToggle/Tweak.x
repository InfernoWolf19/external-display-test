// StageManagerToggle
//
// iPadOS 16 keeps two booleans for Stage Manager in the com.apple.springboard defaults domain:
//   SBChamoisWindowingEnabled       - Stage Manager is on (SpringBoard observes it and relayouts the windows)
//   SBChamoisWindowingEverEnabled   - Stage Manager has been turned on at least once
//
// The Control Centre button and the Settings switch only write "Enabled" once "EverEnabled" is true. While it is false
// they write "EverEnabled" instead and leave "Enabled" alone; SpringBoard observes that change, dismisses Control
// Centre and presents the Stage Manager introduction (com.apple.SpringBoardEducation), which is what the first-run
// flow is. Nothing then switches Stage Manager on by itself.
//
// This tweak makes both switches write "Enabled" directly, always, and never touch "EverEnabled", so toggling works the
// same way as `defaults write com.apple.springboard SBChamoisWindowingEnabled -bool true/false` and the introduction is
// never shown.
//
//   Control Centre (SpringBoard process, ContinuousExposeModule.bundle):
//     -[SBContinuousExposeModuleController setContinuousExposeEnabled:]      (both the tile and the expanded-panel
//     button call it)
//   Settings (Preferences process, DisplayAndBrightnessSettings):
//     -[DBSMultitaskingContinuousExposeController setContinuousExposeEnabled:specifier:]
//
// Both classes live in code that is loaded lazily, so the hooks are installed when the class first appears.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/log.h>
#include <string.h>

static NSString *const kEnabledKey = @"SBChamoisWindowingEnabled";
static NSString *const kSettingsChangedNotification = @"DBSMultitaskingContinuousExposeEnablementChanged";

static os_log_t gLog;

@interface NSObject (StageManagerToggleDeclarations)
- (NSUserDefaults *)_defaults;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
@end

%group ControlCenterModule
%hook SBContinuousExposeModuleController
- (void)setContinuousExposeEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [self _defaults];
    if (!defaults) {
        %orig;
        return;
    }
    [defaults setBool:enabled forKey:kEnabledKey];
}
%end
%end

%group SettingsPane
%hook DBSMultitaskingContinuousExposeController
- (void)setContinuousExposeEnabled:(id)value specifier:(id)specifier {
    // What the original does once Stage Manager has been enabled before: write the switch's own preference
    // (SBChamoisWindowingEnabled) and tell the pane.
    [self setPreferenceValue:value specifier:specifier];
    [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsChangedNotification object:nil];
}
%end
%end

static BOOL gControlCenterHooked, gSettingsHooked;

static void installIfPossible(void) {
    @synchronized ([NSObject class]) {
        if (!gControlCenterHooked && objc_getClass("SBContinuousExposeModuleController")) {
            gControlCenterHooked = YES;
            %init(ControlCenterModule);
            os_log(gLog, "Control Centre Stage Manager button hooked");
        }
        if (!gSettingsHooked && objc_getClass("DBSMultitaskingContinuousExposeController")) {
            gSettingsHooked = YES;
            %init(SettingsPane);
            os_log(gLog, "Settings Stage Manager switch hooked");
        }
    }
}

static void imageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    if (strstr(info.dli_fname, "ContinuousExposeModule") || strstr(info.dli_fname, "DisplayAndBrightnessSettings"))
        dispatch_async(dispatch_get_main_queue(), ^{ installIfPossible(); });
}

%ctor {
    gLog = os_log_create("com.infernowolf19.stagemanagertoggle", "main");
    installIfPossible();
    if (gControlCenterHooked && gSettingsHooked) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) { installIfPossible(); }];
    _dyld_register_func_for_add_image(imageAdded);
}
