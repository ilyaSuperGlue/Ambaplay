// CompatManager WebUI service.
#ifndef NOTPROTON_FEATS_COMPATSVC_H
#define NOTPROTON_FEATS_COMPATSVC_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <mach-o/loader.h>

// Registers on first route lookup rather than at install time
void np_compatsvc_register(const struct mach_header_64 *mh, intptr_t slide,
                           uintptr_t text_base, size_t text_size);

// Whether the CompatManager routes are answering. UNTRIED is a route lookup that has
// not happened yet, which is not the same as a client that cannot serve them: the
// compat chunk can be served before anything asks the transport for a route.
enum {
    NP_COMPATSVC_UNTRIED = 0,
    NP_COMPATSVC_READY,
    NP_COMPATSVC_ABSENT,
};
int np_compatsvc_routes(void);

// Sentinel name for "no tool", which Steam keeps in CompatToolMapping. Releases before
// Ambaplay 3.0 wrote the legacy one, and it means the same until the app rewrites it.
#define NP_COMPAT_TOOL_NONE        "ambaplay-proton.none"
#define NP_COMPAT_TOOL_NONE_LEGACY "notproton.none"

static inline int np_compat_is_none(const char *name) {
    return name && (strcmp(name, NP_COMPAT_TOOL_NONE) == 0
                    || strcmp(name, NP_COMPAT_TOOL_NONE_LEGACY) == 0);
}

// Tells the page the mapping changed.
void np_compatsvc_state_changed(void);

#endif // NOTPROTON_FEATS_COMPATSVC_H
