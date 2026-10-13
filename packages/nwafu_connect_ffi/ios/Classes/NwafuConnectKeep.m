// The app opens the library with DynamicLibrary.process(), so nothing links
// against these symbols and the static linker would drop the archive. The
// app links with -ObjC, which always loads Objective-C classes; this class's
// references pull libnwafuconnect.a in and keep the Nc* entry points.
#import <Foundation/Foundation.h>

extern char *NcStart(char *configJSON);
extern char *NcSubmit(char *kind, char *value);
extern char *NcStatus(void);
extern char *NcStop(void);
extern void NcFree(char *p);

__attribute__((used)) static void *const kNwafuConnectSymbols[] = {
    (void *)&NcStart, (void *)&NcSubmit, (void *)&NcStatus,
    (void *)&NcStop, (void *)&NcFree,
};

@interface NwafuConnectKeep : NSObject
@end

@implementation NwafuConnectKeep
+ (const void *const *)symbols {
  return (const void *const *)kNwafuConnectSymbols;
}
@end
