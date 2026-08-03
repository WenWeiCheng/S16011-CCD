/******************************************************************************
* @file key.h
*
* Key driver: based on Gpio_key (polled, no interrupt), semantic interface + built-in
* debounce / long-press detection. Every event carries the pressed key mask so callers
* can tell which key(s) triggered it.
*
* The debounce FSM is advanced by calling Key_Tick() on each heartbeat period; the key
* state is polled directly from the GPIO (no interrupt involved).
*
* Press semantics: any active-low key in the mask being low counts as "pressed" (OR);
* the pressed bit-mask is captured at the debounced press and reported with each event.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* 1.1   wwc  26/08/03 Remove dead interrupt handler / Changed flag (key is polled)
* 1.2   wwc  26/08/03 Events carry key mask: distinguish which key pressed
* </pre>
******************************************************************************/
#ifndef KEY_H
#define KEY_H

#include "xil_types.h"
#include "xstatus.h"
#include "xgpio.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    KEY_IDLE = 0,       /* no event */
    KEY_PRESSED,        /* pressed after debounce */
    KEY_RELEASED,       /* released after debounce */
    KEY_LONG_PRESS       /* long press */
} KeyEvent;

typedef void (*KeyHandler)(KeyEvent evt, u32 key_mask, void *ref);

typedef enum {
    KEY_STATE_IDLE = 0,
    KEY_STATE_PRESSED
} KeyState;

typedef struct {
    XGpio *Gpio;
    u32 ActiveLowMask;        /* mask of active-low key bits (pressed=0) */
    u16 DebounceMs;           /* debounce time (ms) */
    u16 LongPressMs;          /* long-press threshold time (ms) */
    KeyState State;           /* debounced state */
    u16 DebounceCount;
    u16 PressCount;           /* sustained press counter */
    u8  LongPressed;          /* whether long press already triggered for this press */
    u32 PressedMask;          /* keys captured at the debounced press; 0 in IDLE */
    KeyHandler Handler;
    void *HandlerRef;
} Key;

/* Default timing parameters (can be overridden after Init) */
#define KEY_DEBOUNCE_MS_DEFAULT   20U
#define KEY_LONG_PRESS_MS_DEFAULT 1000U

int  Key_Init(Key *d, XGpio *gpio, u32 active_low_mask);
void Key_RegisterHandler(Key *d, KeyHandler hdl, void *ref);
KeyState Key_GetState(Key *d);
u32  Key_GetPressedMask(Key *d);
void Key_Tick(Key *d, u32 ms);            /* called on each heartbeat period, advances the debounce FSM */

#ifdef __cplusplus
}
#endif

#endif /* KEY_H */
