/******************************************************************************
* @file led.h
*
* LED driver: based on Gpio_led, operates by idx, polarity built-in (see
* LED_ACTIVE_LOW in board_config.h).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
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
    u32 OutMask;      /* output bit mask */
    u32 Current;      /* current logical output (without polarity) */
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
