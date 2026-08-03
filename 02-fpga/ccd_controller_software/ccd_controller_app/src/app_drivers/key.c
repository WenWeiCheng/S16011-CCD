/******************************************************************************
* @file key.c
*
* Key driver implementation: debounce / long-press FSM, driven by Key_Tick() on each
* heartbeat period.
* Press semantics: any active-low key in the mask bits being low counts as "pressed" (OR).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "key.h"
#include "xil_assert.h"

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
    d->Changed = 0U;
    d->Handler = NULL;
    d->HandlerRef = NULL;

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Registers the key event callback (KEY_PRESSED / KEY_RELEASED / KEY_LONG_PRESS).
******************************************************************************/
void Key_RegisterHandler(Key *d, KeyHandler hdl, void *ref)
{
    d->Handler = hdl;
    d->HandlerRef = ref;
}

/*****************************************************************************/
/**
* @brief  Returns the debounced key state.
******************************************************************************/
KeyState Key_GetState(Key *d)
{
    return d->State;
}

/*****************************************************************************/
/**
* @brief  Advances the debounce FSM on each heartbeat period (called every 1ms).
*
* State: IDLE --press debounce--> PRESSED --release debounce--> IDLE.
* Long press accumulates during PRESSED and triggers KEY_LONG_PRESS once past the threshold.
*
* @param  d  Key instance.
* @param  ms Milliseconds since the last call (currently always 1).
******************************************************************************/
void Key_Tick(Key *d, u32 ms)
{
    u32 raw = XGpio_DiscreteRead(d->Gpio, 1) & d->ActiveLowMask;
    u8 pressed = (raw != d->ActiveLowMask) ? 1U : 0U; /* any active-low key pressed */
    u16 step = (u16)ms;

    if (d->State == KEY_STATE_IDLE) {
        if (pressed) {
            d->DebounceCount += step;
            if (d->DebounceCount >= d->DebounceMs) {
                d->State = KEY_STATE_PRESSED;
                d->DebounceCount = 0U;
                d->PressCount = 0U;
                d->LongPressed = 0U;
                if (d->Handler != NULL) {
                    d->Handler(KEY_PRESSED, d->HandlerRef);
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
                    d->Handler(KEY_LONG_PRESS, d->HandlerRef);
                }
            }
        } else {
            d->DebounceCount += step;
            if (d->DebounceCount >= d->DebounceMs) {
                d->State = KEY_STATE_IDLE;
                d->DebounceCount = 0U;
                d->PressCount = 0U;
                if (d->Handler != NULL) {
                    d->Handler(KEY_RELEASED, d->HandlerRef);
                }
            }
        }
    }
}

/*****************************************************************************/
/**
* @brief  Gpio_key interrupt (hooked to INTC, vec6).
*
* Only clears the interrupt and sets the "level changed" flag; the real state decision
* is left to Key_Tick.
******************************************************************************/
void Key_InterruptHandler(void *ref)
{
    Key *d = (Key *)ref;

    if (d->ActiveLowMask != 0U) {
        XGpio_InterruptClear(d->Gpio, d->ActiveLowMask);
    }
    d->Changed = 1U;
}
