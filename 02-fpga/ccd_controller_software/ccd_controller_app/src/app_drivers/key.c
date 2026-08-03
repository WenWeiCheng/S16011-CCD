/******************************************************************************
* @file key.c
*
* Key driver implementation: debounce / long-press FSM, driven by Key_Tick() on each
* heartbeat period.
* Press semantics: any active-low key in the mask bits being low counts as "pressed" (OR);
* the pressed bit-mask is captured at the debounced press and reported with each event.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* 1.1   wwc  26/08/03 Complete function doc comments (Xilinx style)
* 1.2   wwc  26/08/03 Remove dead interrupt handler (key is polled)
* 1.3   wwc  26/08/03 Events carry key mask: distinguish which key pressed
* </pre>
******************************************************************************/
#include "key.h"
#include "xil_assert.h"
#include "../include/board_config.h"

/*****************************************************************************/
/**
* @brief  Initializes the key instance.
*
* @param  d              Key instance.
* @param  gpio           XGpio instance of Gpio_key (initialized by board_hal).
* @param  active_low_mask Mask of active-low key bits (pressed=0).
*
* @return XST_SUCCESS.
******************************************************************************/
int Key_Init(Key *d, XGpio *gpio, u32 active_low_mask)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(gpio != NULL);

    d->Gpio = gpio;
    d->ActiveLowMask = active_low_mask;
    d->DebounceMs = KEY_DEBOUNCE_MS_DEFAULT;
    d->LongPressMs = KEY_LONG_PRESS_MS_DEFAULT;
    d->State = KEY_STATE_IDLE;
    d->DebounceCount = 0U;
    d->PressCount = 0U;
    d->LongPressed = 0U;
    d->PressedMask = 0U;
    d->Handler = NULL;
    d->HandlerRef = NULL;

    /* Key: input direction (1=input); state is polled by Key_Tick() */
    XGpio_SetDataDirection(gpio, 1U, KEY_IN_MASK);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Registers the key event callback (KEY_PRESSED / KEY_RELEASED / KEY_LONG_PRESS).
*
* Events carry the pressed key mask: PRESSED / LONG_PRESS report the held keys,
* RELEASED reports the keys held during this press cycle.
*
* @param  d    Key instance.
* @param  hdl  Callback invoked on debounced key events; NULL disables.
* @param  ref  Opaque reference passed back to the callback.
******************************************************************************/
void Key_RegisterHandler(Key *d, KeyHandler hdl, void *ref)
{
    d->Handler = hdl;
    d->HandlerRef = ref;
}

/*****************************************************************************/
/**
* @brief  Returns the debounced key state.
*
* @param  d  Key instance.
*
* @return Current KeyState (IDLE or PRESSED).
******************************************************************************/
KeyState Key_GetState(Key *d)
{
    return d->State;
}

/*****************************************************************************/
/**
* @brief  Returns the mask of keys captured at the last debounced press (0 in IDLE).
*
* @param  d  Key instance.
*
* @return Bit-mask of pressed keys (1 = pressed), or 0 if none.
******************************************************************************/
u32 Key_GetPressedMask(Key *d)
{
    return d->PressedMask;
}

/*****************************************************************************/
/**
* @brief  Advances the debounce FSM on each heartbeat period (called every 1ms).
*
* State: IDLE --press debounce--> PRESSED --release debounce--> IDLE.
* Long press accumulates during PRESSED and triggers KEY_LONG_PRESS once past the threshold.
* On a debounced press the current key mask is captured into PressedMask and reported
* with KEY_PRESSED; KEY_RELEASED reports the same mask at the end of the press cycle.
*
* @param  d    Key instance.
* @param  ms   Milliseconds since the last call (currently always 1).
******************************************************************************/
void Key_Tick(Key *d, u32 ms)
{
    u32 raw = XGpio_DiscreteRead(d->Gpio, 1) & d->ActiveLowMask;
    u32 pressed_mask = ((~raw) & d->ActiveLowMask); /* 1 = key pressed (active-low) */
    u8 pressed = (pressed_mask != 0U) ? 1U : 0U;
    u16 step = (u16)ms;

    if (d->State == KEY_STATE_IDLE) {
        if (pressed) {
            d->DebounceCount += step;
            if (d->DebounceCount >= d->DebounceMs) {
                d->State = KEY_STATE_PRESSED;
                d->DebounceCount = 0U;
                d->PressCount = 0U;
                d->LongPressed = 0U;
                d->PressedMask = pressed_mask;
                if (d->Handler != NULL) {
                    d->Handler(KEY_PRESSED, d->PressedMask, d->HandlerRef);
                }
            }
        } else {
            d->DebounceCount = 0U;
        }
    } else { /* KEY_STATE_PRESSED */
        if (pressed) {
            d->PressCount += step;
            if ((d->LongPressed == 0U) &&
                (d->PressCount >= d->LongPressMs)) {
                d->LongPressed = 1U;
                if (d->Handler != NULL) {
                    d->Handler(KEY_LONG_PRESS, d->PressedMask, d->HandlerRef);
                }
            }
        } else {
            d->DebounceCount += step;
            if (d->DebounceCount >= d->DebounceMs) {
                d->State = KEY_STATE_IDLE;
                d->DebounceCount = 0U;
                d->PressCount = 0U;
                if (d->Handler != NULL) {
                    d->Handler(KEY_RELEASED, d->PressedMask, d->HandlerRef);
                }
                d->PressedMask = 0U;
            }
        }
    }
}


