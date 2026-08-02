/******************************************************************************
* @file ads1118.c
*
* ads1118 驱动实现。SPI mode 1（CPOL=0, CPHA=1），16-bit 帧。
* "读取即写"：写 NOP=01b 取数并同步回读最近一次 16-bit 转换结果。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "ads1118.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/* 取数 NOP=01b；写配置 NOP=00b */
#define ADS1118_NOP_READ      (0x1U << ADS1118_CFG_NOP_SHIFT)
#define ADS1118_NOP_NORMAL    (0x0U << ADS1118_CFG_NOP_SHIFT)

/*****************************************************************************/
/**
* @brief  组装当前通道配置字。
******************************************************************************/
static u16 Ads1118_BuildConfig(const Ads1118 *d, u16 nop)
{
    return (u16)(ADS1118_CFG_CONTINUOUS_BASE |
                 (((u16)d->Mux & 0x7U) << ADS1118_CFG_MUX_SHIFT) |
                 nop);
}

/*****************************************************************************/
/**
* @brief  发起一笔 16-bit 传输（写 cfg，回读上次转换结果）。
*
* 传输前切 SPI mode 1 并选片；完成后释放片选。
*
* @return XST_SUCCESS / XST_FAILURE。
******************************************************************************/
static int Ads1118_Transfer(Ads1118 *d, u16 cfg, u16 *result)
{
    int status;
    u16 txw = cfg;
    u16 rxw = 0U;

    Xil_AssertNonvoid(d != NULL);

    status = XSpi_SetOptions(d->Spi,
                             XSP_MASTER_OPTION |
                             XSP_MANUAL_SSELECT_OPTION |
                             XSP_CLK_PHASE_1_OPTION);   /* CPOL=0, CPHA=1 */
    if (status != XST_SUCCESS) {
        return status;
    }
    XSpi_SetSlaveSelect(d->Spi, 1U << d->Cs);

    /* 16-bit 帧：驱动以 native u16 存取 DTR/DRR，SPI 核按 MSB-first 移位，
     * 与 CPU 端序无关。 */
    status = XSpi_Transfer(d->Spi, (u8 *)&txw, (u8 *)&rxw, 2U);
    if (status != XST_SUCCESS) {
        return status;
    }
    *result = rxw;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  初始化：保存 SPI/片选，默认通道为 SENSOR_NTC 并立即应用配置。
*
* @return XST_SUCCESS / 底层错误。
******************************************************************************/
int Ads1118_Init(Ads1118 *d, XSpi *spi, u8 cs)
{
    u16 dummy;

    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(spi != NULL);

    d->Spi = spi;
    d->Cs = cs;
    d->Mux = ADS1118_MUX_SENSOR_NTC;

    /* 写当前配置（连续模式即时生效） */
    return Ads1118_Transfer(d, Ads1118_BuildConfig(d, ADS1118_NOP_NORMAL),
                            &dummy);
}

/*****************************************************************************/
/**
* @brief  切换输入通道（写新 MUX 配置，连续模式即时生效）。
******************************************************************************/
int Ads1118_SetChannel(Ads1118 *d, Ads1118_Mux mux)
{
    u16 dummy;

    d->Mux = mux;
    return Ads1118_Transfer(d, Ads1118_BuildConfig(d, ADS1118_NOP_NORMAL),
                            &dummy);
}

/*****************************************************************************/
/**
* @brief  读取最近一次转换结果（写 NOP=01b 取数）。
******************************************************************************/
int Ads1118_ReadRaw(Ads1118 *d, s16 *raw)
{
    u16 val;
    int status;

    status = Ads1118_Transfer(d, Ads1118_BuildConfig(d, ADS1118_NOP_READ),
                              &val);
    if (status != XST_SUCCESS) {
        return status;
    }
    *raw = (s16)val;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  写配置寄存器原语（raw）。
******************************************************************************/
int Ads1118_WriteConfig(Ads1118 *d, u16 cfg)
{
    u16 dummy;
    return Ads1118_Transfer(d, cfg, &dummy);
}
