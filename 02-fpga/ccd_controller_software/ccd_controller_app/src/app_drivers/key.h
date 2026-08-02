/******************************************************************************
* @file key.h
*
* 按键驱动：基于 Gpio_key（含中断），语义接口 + 内置消抖/长按判定。
*
* 消抖 FSM 由心跳周期调用 Key_Tick() 推进；GPIO 边沿中断只置"电平有变化"
* 标志，不在中断上下文做定时判定。
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
    KEY_IDLE = 0,       /* 无事件 */
    KEY_PRESSED,        /* 消抖后按下 */
    KEY_RELEASED,       /* 消抖后释放 */
    KEY_LONG_PRESS       /* 长按 */
} KeyEvent;

typedef void (*KeyHandler)(KeyEvent evt, void *ref);

typedef enum {
    KEY_STATE_IDLE = 0,
    KEY_STATE_PRESSED
} KeyState;

typedef struct {
    XGpio *Gpio;
    u32 ActiveLowMask;        /* 低有效键位掩码（按下=0） */
    u16 DebounceMs;           /* 消抖时间（ms） */
    u16 LongPressMs;          /* 长按判定时间（ms） */
    KeyState State;           /* 消抖后状态 */
    u16 DebounceCount;
    u16 PressCount;           /* 持续按下计数 */
    u8  LongPressed;          /* 本次按下是否已触发长按 */
    volatile u8 Changed;      /* GPIO 中断置位：电平有变化 */
    KeyHandler Handler;
    void *HandlerRef;
} Key;

/* 默认时序参数（可在 Init 后覆盖） */
#define KEY_DEBOUNCE_MS_DEFAULT   20U
#define KEY_LONG_PRESS_MS_DEFAULT 1000U

int  Key_Init(Key *d, XGpio *gpio, u32 active_low_mask);
void Key_RegisterHandler(Key *d, KeyHandler hdl, void *ref);
KeyState Key_GetState(Key *d);
void Key_Tick(Key *d, u32 ms);            /* 心跳周期调用，推进消抖 FSM */
void Key_InterruptHandler(void *ref);     /* GPIO 中断，置按键标志 */

#ifdef __cplusplus
}
#endif

#endif /* KEY_H */
