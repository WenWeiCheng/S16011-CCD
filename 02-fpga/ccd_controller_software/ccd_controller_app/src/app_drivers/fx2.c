/******************************************************************************
* @file fx2.c
*
* FX2 Slave FIFO 控制实现。默认端点 2（FIFOADR=00）：
*   sloe_n=1（不读）、slrd_n=1（不读）、fifo_addr0=0、fifo_addr1=0。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "fx2.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/*****************************************************************************/
/**
* @brief  初始化 FX2 引脚：输出位置默认电平，PA0 配为输入。
*
* @param  d    FX2 实例。
* @param  gpio Gpio_fx2fifo 的 XGpio 实例（board_hal 已初始化）。
*
* @return XST_SUCCESS。
******************************************************************************/
int Fx2_Init(Fx2 *d, XGpio *gpio)
{
    u32 out;
    u32 dir;

    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(gpio != NULL);

    d->Gpio = gpio;
    d->OutVal = (1U << FX2_GPIO_SLOE_N_BIT) |
                (1U << FX2_GPIO_SLRD_N_BIT);   /* FIFOADR=00（端点 2） */

    /* 输出位 0..3，其余（PA0）为输入 */
    dir = ~FX2_GPIO_OUT_MASK;
    XGpio_SetDataDirection(gpio, 1U, dir);

    out = d->OutVal;
    XGpio_DiscreteWrite(gpio, 1U, out);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  切换写端点（0=ep2, 1=ep4, 2=ep6, 3=ep8）。
******************************************************************************/
void Fx2_SetEndpoint(Fx2 *d, u8 ep)
{
    u32 v;
    u8 addr;

    Xil_AssertVoid(d != NULL);

    addr = ep & 0x3U;
    v = d->OutVal &
        ~((1U << FX2_GPIO_FIFO_ADDR0_BIT) |
          (1U << FX2_GPIO_FIFO_ADDR1_BIT));
    v |= ((u32)(addr & 0x1U)) << FX2_GPIO_FIFO_ADDR0_BIT;
    v |= ((u32)((addr >> 1) & 0x1U)) << FX2_GPIO_FIFO_ADDR1_BIT;

    d->OutVal = v;
    XGpio_DiscreteWrite(d->Gpio, 1U, v);
}

/*****************************************************************************/
/**
* @brief  读 PA0 sync：1=FX2 已配置，可作为 USB 通道。
******************************************************************************/
u8 Fx2_IsUsbReady(Fx2 *d)
{
    Xil_AssertNonvoid(d != NULL);
    return (XGpio_DiscreteRead(d->Gpio, 1U) & FX2_GPIO_IN_MASK) ? 1U : 0U;
}
