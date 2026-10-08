// Shared between Tweak.x and the other Backport162 source files.
#import <Foundation/Foundation.h>

// Feature switches. Every feature is on by default; <jbroot>/tmp/Backport162.off.<name> turns one off and
// <jbroot>/tmp/Backport162.off turns everything off.
enum { F_SCALE, F_AUTOHOST, F_BLANK, F_DISCONNECT, F_DISCSWITCH, F_ACTIVEDISPLAY, F_GESTUREGATE, F_LOCKEDPTR, F_NOWINDOW, F_DIRECTHOOK, F_COUNT };

BOOL BP_On(int feature);
void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
