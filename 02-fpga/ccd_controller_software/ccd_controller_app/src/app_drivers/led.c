/******************************************************************************
* @file led.c
*
* LED 驱动实现：极性内置，逻辑 on=亮，物理电平由 LED_ACTIVE_LOW 决定。
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
* @brief  初始化 LED 实例。
*
* @param  d        LED 实例。
* @param  gpio     Gpio_led 的 XGpio 实例（board_hal 已初始化）。
* @param  out_mask 输出位掩码。
*
* @return XST_SUCCESS。
******************************************************************************/
int Led_Init(Led *d, XGpio *gpio, u32 out_mask)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(gpio != NULL);

    d->Gpio = gpio;
    d->OutMask = out_mask;
    d->Current = 0U;
    /* 输出方向（1=输入，0=输出） */
    XGpio_SetDataDirection(gpio, 1U, ~out_mask);
    XGpio_DiscreteWrite(gpio, 1U, 0U);
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  按 idx 设置 LED（idx=0/1，对应 LED0_BIT/LED1_BIT）。
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
* @brief  点亮 idx 号 LED。
******************************************************************************/
void Led_On(Led *d, u8 idx)
{
    Led_Set(d, idx, 1U);
}

/*****************************************************************************/
/**
* @brief  熄灭 idx 号 LED。
******************************************************************************/
void Led_Off(Led *d, u8 idx)
{
    Led_Set(d, idx, 0U);
}

/*****************************************************************************/
/**
* @brief  翻转 idx 号 LED。
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
