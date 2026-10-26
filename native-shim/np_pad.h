// Shared contract of the native controller shim (libnp_gamepad.dylib).
//
// hid_profile.c  turns any HID game controller into np_pad_state: it parses the HID
//                report descriptor, looks the pad up in gamecontrollerdb (SDL format) by
//                its SDL GUID, and decodes input reports with that mapping.
// gamepad_shim.c interposes IOHIDManager/IOHIDDevice so raw-HID games (Unity) see every
//                unsupported pad as an Xbox Wireless Controller and get Xbox reports.
// gc_virtual.m   gives GameController-framework games a virtual GCController per pad
//                the system does not already expose as a GCController.

#ifndef NP_PAD_H
#define NP_PAD_H

#include <IOKit/hid/IOHIDLib.h>
#include <stdint.h>

// Xbox (SDL) button order; also the bit order of np_pad_state.buttons.
enum {
    NP_BTN_A, NP_BTN_B, NP_BTN_X, NP_BTN_Y,
    NP_BTN_BACK, NP_BTN_GUIDE, NP_BTN_START,
    NP_BTN_LEFTSTICK, NP_BTN_RIGHTSTICK,
    NP_BTN_LEFTSHOULDER, NP_BTN_RIGHTSHOULDER,
    NP_BTN_DPAD_UP, NP_BTN_DPAD_DOWN, NP_BTN_DPAD_LEFT, NP_BTN_DPAD_RIGHT,
    NP_BTN_MISC1,
    NP_BTN_COUNT
};

typedef struct {
    float lx, ly, rx, ry;   // -1..1, +y is down (SDL convention)
    float lt, rt;           // 0..1
    uint32_t buttons;       // bit NP_BTN_*; d-pad is reported here, not as a hat
} np_pad_state;

typedef struct np_profile np_profile;

// NULL when the device is not a game controller, or is one the system and games already
// handle natively (Xbox, DualShock 4, DualSense, Switch Pro, MFi-only): those are left alone.
np_profile *np_profile_create(IOHIDDeviceRef device);
void np_profile_free(np_profile *profile);

// Returns 1 and fills state when the report carries controller input, else 0.
// report includes the report ID byte when the device uses report IDs.
int np_profile_decode(np_profile *profile, uint32_t reportID, const uint8_t *report,
                      long length, np_pad_state *state);

// SDL GUID string (32 hex chars) and name the profile matched, for logs.
const char *np_profile_guid(const np_profile *profile);
const char *np_profile_name(const np_profile *profile);

// 18-byte Xbox Wireless Controller (Bluetooth) report in the layout Unity's
// XboxGamepadMacOSWireless (XInputControllerWirelessOSXStateV2) reads.
#define NP_XBOX_REPORT_LEN 18
void np_xbox_encode(const np_pad_state *state, uint8_t out[NP_XBOX_REPORT_LEN]);

// Mapping database: $NP_GAMECONTROLLERDB, else
// ~/Library/Application Support/ambaplay/gamecontrollerdb.txt (notproton until the app moves
// it), plus SDL_GAMECONTROLLERCONFIG.
// Later lines win over earlier ones for the same GUID.
void np_db_load(void);

// Which game-facing path the shim serves, from $NP_PAD_MODE: "hid" (raw-HID games such as
// Unity: Xbox spoof only), "gc" (GameController games: virtual GCControllers only), "both",
// or "off". Unset = "hid" when the process loaded UnityPlayer, else "both". Serving both to
// a game that reads both would show every pad twice, hence the switch.
enum { NP_MODE_OFF = 0, NP_MODE_HID = 1, NP_MODE_GC = 2 };
int np_pad_mode(void);   // bitmask of NP_MODE_HID / NP_MODE_GC

// gc_virtual.m reads pads through its own IOHIDManager (GameController games never open
// HID themselves) and decodes them with np_profile_*; it starts itself from a constructor
// when np_pad_mode() has NP_MODE_GC.

#endif
