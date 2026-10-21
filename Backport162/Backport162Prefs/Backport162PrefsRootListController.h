// Backport162Prefs : the Settings pane of Backport162 (PreferenceLoader bundle, loaded into Preferences.app only when the user opens the pane).
// It is only UI. All the work of "Send logs now" is done by SpringBoard (RPT.x in the main dylib); the two talk through two Darwin notifications and the preferences domain
// com.infernowolf19.backport162. Protocol and failure table: specs/SEND-LOGS-0.7.9.md.
//
// The few classes of the private Preferences framework that are needed are declared here instead of imported: the pane must compile with any SDK (the private framework headers are
// not part of it) and these declarations only describe what the real classes already have. The superclass is resolved by the dynamic linker (Preferences.app has the framework loaded).
#import <UIKit/UIKit.h>

@interface PSSpecifier : NSObject
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)setName:(NSString *)name;
@end

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)specifiers;
- (PSSpecifier *)specifierForID:(NSString *)identifier;
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
@end

@interface Backport162PrefsRootListController : PSListController
@end
