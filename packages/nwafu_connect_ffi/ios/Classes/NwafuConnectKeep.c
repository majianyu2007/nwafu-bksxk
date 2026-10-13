// The app opens the library with DynamicLibrary.process(), so nothing in the
// app links against these symbols and the static linker would drop them.
// Referencing them here keeps the Nc* entry points in the final binary.
#include <stdint.h>

extern char *NcStart(char *configJSON);
extern char *NcSubmit(char *kind, char *value);
extern char *NcStatus(void);
extern char *NcStop(void);
extern void NcFree(char *p);

__attribute__((used, visibility("default")))
const void *nwafu_connect_keep[] = {
    (const void *)&NcStart, (const void *)&NcSubmit, (const void *)&NcStatus,
    (const void *)&NcStop,  (const void *)&NcFree,
};
