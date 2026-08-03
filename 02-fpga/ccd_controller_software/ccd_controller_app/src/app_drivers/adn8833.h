/******************************************************************************
* @file adn8833.h
*
* ADN8833 TEC power enable: based on Gpio_general[0], only does level operations.
* Enable timing (power-up settling, current limiting) is controlled by the app logic.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef ADN8833_H
#define ADN8833_H

#include "xil_types.h"
#include "xstatus.h"
#include "xgpio.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    XGpio *Gpio;
    u32 EnMask;       /* enable bit mask */
    u8 Enable;        /* current enable state */
} Adn8833;

int  Adn8833_Init(Adn8833 *d, XGpio *gpio, u32 en_bit);
void Adn8833_SetEnable(Adn8833 *d, u8 on);
u8   Adn8833_GetEnable(Adn8833 *d);

#ifdef __cplusplus
}
#endif

#endif /* ADN8833_H */
