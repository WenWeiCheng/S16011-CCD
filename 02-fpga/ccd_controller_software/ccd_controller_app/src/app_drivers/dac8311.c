/******************************************************************************
* @file dac8311.c
*
* dac8311 驱动实现。SPI mode 2（CPOL=1, CPHA=0），16-bit 帧。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "dac8311.h"
#include "../include/board_config.h"
#include "xil_assert.h"

#define DAC8311_DATA_MASK    0x3FFFU   /* [13:0] */
#define DAC8311_PD_SHIFT     14U

/*****************************************************************************/
/**
* @brief  发起一笔 16-bit 传输（写 dac8311 无回读）。
*
* 传输前切 SPI mode 2 并选片。
*
* @return XST_SUCCESS / 底层错误。
******************************************************************************/
static int Dac8311_Transfer(Dac8311 *d, u16 word)
{
    int status;
    u16 txw = word;
    u16 rxw = 0U;

    Xil_AssertNonvoid(d != NULL);

    status = XSpi_SetOptions(d->Spi,
                             XSP_MASTER_OPTION |
                             XSP_MANUAL_SSELECT_OPTION |
                             XSP_CLK_ACTIVE_LOW_OPTION); /* CPOL=1, CPHA=0 */
    if (status != XST_SUCCESS) {
        return status;
    }
    XSpi_SetSlaveSelect(d->Spi, 1U << d->Cs);

    status = XSpi_Transfer(d->Spi, (u8 *)&txw, (u8 *)&rxw, 2U);
    return status;
}

/*****************************************************************************/
/**
* @brief  初始化：保存 SPI/片选/参考电压。
*
* @return XST_SUCCESS。
******************************************************************************/
int Dac8311_Init(Dac8311 *d, XSpi *spi, u8 cs, float vref)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(spi != NULL);

    d->Spi = spi;
    d->Cs = cs;
    d->Vref = (vref > 0.0f) ? vref : DAC8311_VREF_V;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  设置输出电压（正常模式，PD=00）。
*
* @param  volt 目标电压（V），钳位到 0..Vref。
*
* @return XST_SUCCESS / 底层错误。
******************************************************************************/
int Dac8311_SetVoltage(Dac8311 *d, float volt)
{
    u32 dac;
    u16 word;

    if (volt < 0.0f) {
        volt = 0.0f;
    }
    if (volt > d->Vref) {
        volt = d->Vref;
    }

    /* D = volt * 2^14 / Vref */
    dac = (u32)((volt * 16384.0f / d->Vref) + 0.5f);
    if (dac > DAC8311_DATA_MASK) {
        dac = DAC8311_DATA_MASK;
    }

    word = (u16)((DAC8311_PD_NORMAL << DAC8311_PD_SHIFT) | dac);
    return Dac8311_Transfer(d, word);
}

/*****************************************************************************/
/**
* @brief  写原始 16-bit（[15:14] 控制位 + [13:0] 数据）。
******************************************************************************/
int Dac8311_SetRaw(Dac8311 *d, u16 code)
{
    return Dac8311_Transfer(d, code);
}

/*****************************************************************************/
/**
* @brief  进入 Power-down 模式（pd: 1=1kΩ, 2=100kΩ, 3=High-Z）。
******************************************************************************/
int Dac8311_SetPowerDown(Dac8311 *d, u8 pd)
{
    u16 word;

    if (pd > DAC8311_PD_HIGHZ) {
        pd = DAC8311_PD_HIGHZ;
    }
    word = (u16)((u16)pd << DAC8311_PD_SHIFT);
    return Dac8311_Transfer(d, word);
}
