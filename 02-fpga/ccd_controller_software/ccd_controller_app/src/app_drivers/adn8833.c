/******************************************************************************
* @file adn8833.c
*
* ADN8833 使能驱动实现。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "adn8833.h"
#include "xil_assert.h"

/*****************************************************************************/
/**
* @brief  初始化 ADN8833 使能引脚。
*
* @param  d      ADN8833 实例。
* @param  gpio   Gpio_general 的 XGpio 实例（board_hal 已初始化）。
* @param  en_bit 使能位号（默认 0）。
*
* @return XST_SUCCESS。
******************************************************************************/
int Adn8833_Init(Adn8833 *d, XGpio *gpio, u32 en_bit)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(gpio != NULL);

    d->Gpio = gpio;
    d->EnMask = 1U << en_bit;
    d->Enable = 0U;

    /* 该位设为输出 */
    XGpio_SetDataDirection(gpio, 1U, ~d->EnMask);
    XGpio_DiscreteWrite(gpio, 1U, 0U);   /* 上电默认关 */

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  置/清 ADN8833 EN。
******************************************************************************/
void Adn8833_SetEnable(Adn8833 *d, u8 on)
{
    u32 cur;

    Xil_AssertVoid(d != NULL);

    /* 读-改-写，避免影响 Gpio_general 其它位 */
    cur = XGpio_DiscreteRead(d->Gpio, 1U);
    if (on) {
        cur |= d->EnMask;
    } else {
        cur &= ~d->EnMask;
    }
    XGpio_DiscreteWrite(d->Gpio, 1U, cur);
    d->Enable = on ? 1U : 0U;
}

/*****************************************************************************/
/**
* @brief  读取当前使能状态。
******************************************************************************/
u8 Adn8833_GetEnable(Adn8833 *d)
{
    return d->Enable;
}
