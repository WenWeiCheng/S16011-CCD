/******************************************************************************
* @file adn8833.c
*
* ADN8833 enable driver implementation.
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
* @brief  Initializes the ADN8833 enable pin.
*
* @param  d      ADN8833 instance.
* @param  gpio   XGpio instance of Gpio_general (initialized by board_hal).
* @param  en_bit Enable bit number (default 0).
*
* @return XST_SUCCESS.
******************************************************************************/
int Adn8833_Init(Adn8833 *d, XGpio *gpio, u32 en_bit)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(gpio != NULL);

    d->Gpio = gpio;
    d->EnMask = 1U << en_bit;
    d->Enable = 0U;

    /* Set that bit as output */
    XGpio_SetDataDirection(gpio, 1U, ~d->EnMask);
    XGpio_DiscreteWrite(gpio, 1U, 0U);   /* off by default at power-up */

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Sets/clears the ADN8833 EN.
******************************************************************************/
void Adn8833_SetEnable(Adn8833 *d, u8 on)
{
    u32 cur;

    Xil_AssertVoid(d != NULL);

    /* Read-modify-write, to avoid affecting the other bits of Gpio_general */
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
* @brief  Reads the current enable state.
******************************************************************************/
u8 Adn8833_GetEnable(Adn8833 *d)
{
    return d->Enable;
}
