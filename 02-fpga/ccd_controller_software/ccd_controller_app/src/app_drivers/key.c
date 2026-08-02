/******************************************************************************
* @file key.c
*
* 按键驱动实现：消抖/长按 FSM，由心跳周期驱动 Key_Tick()。
* 按下语义：掩码位中任一低有效键为低即视为"按下"（OR）。
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
* @brief  初始化按键实例。
*
* @param  d              按键实例。
* @param  gpio           Gpio_key 的 XGpio 实例（board_hal 已初始化）。
* @param  active_low_mask 低有效键位掩码（按下=0）。
*
* @return XST_SUCCESS。
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
* @brief  注册按键事件回调（KEY_PRESSED / KEY_RELEASED / KEY_LONG_PRESS）。
******************************************************************************/
void Key_RegisterHandler(Key *d, KeyHandler hdl, void *ref)
{
    d->Handler = hdl;
    d->HandlerRef = ref;
}

/*****************************************************************************/
/**
* @brief  返回消抖后的按键状态。
******************************************************************************/
KeyState Key_GetState(Key *d)
{
    return d->State;
}

/*****************************************************************************/
/**
* @brief  心跳周期推进消抖 FSM（每 1ms 调用一次）。
*
* 状态：IDLE --按下消抖--> PRESSED --释放消抖--> IDLE。
* 长按在 PRESSED 期间持续累计，超阈值触发一次 KEY_LONG_PRESS。
*
* @param  d  按键实例。
* @param  ms 距上次调用的毫秒数（当前恒为 1）。
******************************************************************************/
void Key_Tick(Key *d, u32 ms)
{
    u32 raw = XGpio_DiscreteRead(d->Gpio, 1) & d->ActiveLowMask;
    u8 pressed = (raw != d->ActiveLowMask) ? 1U : 0U; /* 任一低有效键按下 */
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
* @brief  Gpio_key 中断（挂 INTC，vec6）。
*
* 只清中断并置"电平有变化"标志，真实状态判定交给 Key_Tick。
******************************************************************************/
void Key_InterruptHandler(void *ref)
{
    Key *d = (Key *)ref;

    if (d->ActiveLowMask != 0U) {
        XGpio_InterruptClear(d->Gpio, d->ActiveLowMask);
    }
    d->Changed = 1U;
}
