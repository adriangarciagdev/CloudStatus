#ifndef LegacyLoginItems_h
#define LegacyLoginItems_h

#include <stdbool.h>
#include <CoreServices/CoreServices.h>

bool CSLInsertLoginItemLast(LSSharedFileListRef list, CFURLRef url);

#endif
