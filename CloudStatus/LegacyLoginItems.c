#include "LegacyLoginItems.h"

bool CSLInsertLoginItemLast(LSSharedFileListRef list, CFURLRef url) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return LSSharedFileListInsertItemURL(
        list,
        kLSSharedFileListItemLast,
        NULL,
        NULL,
        url,
        NULL,
        NULL
    ) != NULL;
#pragma clang diagnostic pop
}
