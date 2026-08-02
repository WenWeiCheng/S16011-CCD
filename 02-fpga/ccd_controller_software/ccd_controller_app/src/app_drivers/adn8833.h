/******************************************************************************
* @file adn8833.h
*
* ADN8833 TEC 电源使能：基于 Gpio_general[0]，只做电平操作。
* 使能时序（上电稳定、电流限制）由 app 逻辑控制。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
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
    u32 EnMask;       /* 使能位掩码 */
    u8 Enable;        /* 当前使能状态 */
} Adn8833;

int  Adn8833_Init(Adn8833 *d, XGpio *gpio, u32 en_bit);
void Adn8833_SetEnable(Adn8833 *d, u8 on);
u8   Adn8833_GetEnable(Adn8833 *d);

#ifdef __cplusplus
}
#endif

#endif /* ADN8833_H */
