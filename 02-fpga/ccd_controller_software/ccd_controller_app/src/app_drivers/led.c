/******************************************************************************
* @file led.c
*
* LED driver implementation: polarity built-in, logic on=lit, physical level determined
* by LED_ACTIVE_LOW.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "led.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/*****************************************************************************/
/**
* @brief  Initializes the LED instance.
*
* @param  d        LED instance.
* @param  gpio     XGpio instance of Gpio_led (initialized by board_hal).
* @param  out_mask Output bit mask.
*
* @return XST_SUCCESS.
******************************************************************************/
int Led_Init(Led *d, XGpio *gpio, u32 out_mask)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(gpio != NULL);

    d->Gpio = gpio;
    d->OutMask = out_mask;
    d->Current = 0U;
    /* Output direction (1=input, 0=output) */
    XGpio_SetDataDirection(gpio, 1U, ~out_mask);
    XGpio_DiscreteWrite(gpio, 1U, 0U);
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Sets the LED by idx (idx=0/1, corresponding to LED0_BIT/LED1_BIT).
******************************************************************************/
void Led_Set(Led *d, u8 idx, u8 on)
{
    u32 bit;

    Xil_AssertVoid(d != NULL);
    if (idx >= 2U) {
        return;
    }
    bit = 1U << idx;

    if (on) {
        d->Current |= bit;
    } else {
        d->Current &= ~bit;
    }

#if (LED_ACTIVE_LOW != 0)
    XGpio_DiscreteWrite(d->Gpio, 1U, (~d->Current) & d->OutMask);
#else
    XGpio_DiscreteWrite(d->Gpio, 1U, d->Current & d->OutMask);
#endif
}

/*****************************************************************************/
/**
* @brief  Lights up LED idx.
******************************************************************************/
void Led_On(Led *d, u8 idx)
{
    Led_Set(d, idx, 1U);
}

/*****************************************************************************/
/**
* @brief  Turns off LED idx.
******************************************************************************/
void Led_Off(Led *d, u8 idx)
{
    Led_Set(d, idx, 0U);
}

/*****************************************************************************/
/**
* @brief  Toggles LED idx.
******************************************************************************/
void Led_Toggle(Led *d, u8 idx)
{
    u32 bit;
    u8 on;

    Xil_AssertVoid(d != NULL);
    if (idx >= 2U) {
        return;
    }
    bit = 1U << idx;
    on = (d->Current & bit) ? 0U : 1U;
    Led_Set(d, idx, on);
}
