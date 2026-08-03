/******************************************************************************
* @file key.h
*
* Key driver: based on Gpio_key (with interrupts), semantic interface + built-in
* debounce / long-press detection.
*
* The debounce FSM is advanced by calling Key_Tick() on each heartbeat period; the GPIO
* edge interrupt only sets the "level changed" flag, no timing decisions in interrupt
* context.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
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

typedef void (*KeyHandler)(KeyEvent evt, void *ref);

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
    volatile u8 Changed;      /* set by GPIO interrupt: level changed */
    KeyHandler Handler;
    void *HandlerRef;
} Key;

/* Default timing parameters (can be overridden after Init) */
#define KEY_DEBOUNCE_MS_DEFAULT   20U
#define KEY_LONG_PRESS_MS_DEFAULT 1000U

int  Key_Init(Key *d, XGpio *gpio, u32 active_low_mask);
void Key_RegisterHandler(Key *d, KeyHandler hdl, void *ref);
KeyState Key_GetState(Key *d);
void Key_Tick(Key *d, u32 ms);            /* called on each heartbeat period, advances the debounce FSM */
void Key_InterruptHandler(void *ref);     /* GPIO interrupt, sets the key flag */

#ifdef __cplusplus
}
#endif

#endif /* KEY_H */
