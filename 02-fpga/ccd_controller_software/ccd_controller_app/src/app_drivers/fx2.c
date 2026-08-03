/******************************************************************************
* @file fx2.c
*
* FX2 Slave FIFO control implementation. Default endpoint 2 (FIFOADR=00):
*   sloe_n=1 (no read), slrd_n=1 (no read), fifo_addr0=0, fifo_addr1=0.
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
* @brief  Initializes the FX2 pins: output bits at default level, PA0 as input.
*
* @param  d    FX2 instance.
* @param  gpio XGpio instance of Gpio_fx2fifo (initialized by board_hal).
*
* @return XST_SUCCESS.
******************************************************************************/
int Fx2_Init(Fx2 *d, XGpio *gpio)
{
    u32 out;
    u32 dir;

    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(gpio != NULL);

    d->Gpio = gpio;
    d->OutVal = (1U << FX2_GPIO_SLOE_N_BIT) |
                (1U << FX2_GPIO_SLRD_N_BIT);   /* FIFOADR=00 (endpoint 2) */

    /* Output bits 0..3, the rest (PA0) as input */
    dir = ~FX2_GPIO_OUT_MASK;
    XGpio_SetDataDirection(gpio, 1U, dir);

    out = d->OutVal;
    XGpio_DiscreteWrite(gpio, 1U, out);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Switches the write endpoint (0=ep2, 1=ep4, 2=ep6, 3=ep8).
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
* @brief  Reads PA0 sync: 1=FX2 configured, usable as a USB channel.
******************************************************************************/
u8 Fx2_IsUsbReady(Fx2 *d)
{
    Xil_AssertNonvoid(d != NULL);
    return (XGpio_DiscreteRead(d->Gpio, 1U) & FX2_GPIO_IN_MASK) ? 1U : 0U;
}
