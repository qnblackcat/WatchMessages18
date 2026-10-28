#import <Foundation/Foundation.h>

// Debug log (WM18_DEBUG=1, set by `./build.sh … debug`): every line goes to the console with the "[WatchMessages18]"
// prefix and is appended to a file in jbroot, so it can be read without a cable:
//   /var/mobile/Library/Caches/WatchMessages18/appconduitd.log (fallbacks: /var/mobile/Library/WatchMessages18/Logs,
//   /var/tmp/WatchMessages18), capped at WM18LogFileMaxBytes and rotated to appconduitd.log.1.
#define WM18LogFileMaxBytes (256 * 1024)

void WM18LogWrite(NSString *tag, NSString *text);

// Variadic because ObjC message sends ([… stringWithFormat:@"%@", a, b]) put bare commas in the argument. In a build
// without WM18_DEBUG the arguments are still compiled (so log-only variables are not "unused" under -Werror) but never run.
#if WM18_DEBUG
#define WM18Log(tag, ...) WM18LogWrite(tag, [NSString stringWithFormat:__VA_ARGS__])
#else
#define WM18Log(tag, ...) do { if (0) WM18LogWrite(tag, [NSString stringWithFormat:__VA_ARGS__]); } while (0)
#endif
