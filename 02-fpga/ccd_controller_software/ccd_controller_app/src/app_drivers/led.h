/******************************************************************************
* @file led.h
*
* LED 驱动：基于 Gpio_led，按 idx 操作，极性内置（见 board_config.h
* 的 LED_ACTIVE_LOW）。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef LED_H
#define LED_H

#include "xil_types.h"
#include "xstatus.h"
#include "xgpio.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    XGpio *Gpio;
    u32 OutMask;      /* 输出位掩码 */
    u32 Current;      /* 逻辑层当前输出（未含极性） */
} Led;

int  Led_Init(Led *d, XGpio *gpio, u32 out_mask);
void Led_Set(Led *d, u8 idx, u8 on);
void Led_On(Led *d, u8 idx);
void Led_Off(Led *d, u8 idx);
void Led_Toggle(Led *d, u8 idx);

#ifdef __cplusplus
}
#endif

#endif /* LED_H */
