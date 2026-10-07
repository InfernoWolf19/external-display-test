// Shared between Tweak.x and the other Backport162 source files.
#import <Foundation/Foundation.h>

// Feature switches. <jbroot>/tmp/Backport162.off.<name> turns one off; opt-in features also need
// <jbroot>/tmp/Backport162.on.<name> to be switched on.
enum { F_SCALE, F_AUTOHOST, F_BLANK, F_DISCONNECT, F_DISCSWITCH, F_ACTIVEDISPLAY, F_GESTUREGATE, F_LOCKEDPTR, F_NOWINDOW, F_COUNT };

BOOL BP_On(int feature);
void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
