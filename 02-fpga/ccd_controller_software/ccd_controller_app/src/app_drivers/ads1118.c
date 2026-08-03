/******************************************************************************
* @file ads1118.c
*
* ads1118 driver implementation. SPI mode 1 (CPOL=0, CPHA=1), 16-bit frames.
* "read by writing": writes NOP=01b to fetch data and synchronously reads back the most
* recent 16-bit conversion result.
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

/* fetch data NOP=01b; write config NOP=00b */
#define ADS1118_NOP_READ      (0x1U << ADS1118_CFG_NOP_SHIFT)
#define ADS1118_NOP_NORMAL    (0x0U << ADS1118_CFG_NOP_SHIFT)

/*****************************************************************************/
/**
* @brief  Builds the config word for the current channel.
******************************************************************************/
static u16 Ads1118_BuildConfig(const Ads1118 *d, u16 nop)
{
    return (u16)(ADS1118_CFG_CONTINUOUS_BASE |
                 (((u16)d->Mux & 0x7U) << ADS1118_CFG_MUX_SHIFT) |
                 nop);
}

/*****************************************************************************/
/**
* @brief  Starts a 16-bit transfer (writes cfg, reads back the last conversion result).
*
* Switches to SPI mode 1 and asserts the chip select before transferring; releases the
* chip select when done.
*
* @return XST_SUCCESS / XST_FAILURE.
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

    /* 16-bit frame: the driver stores DTR/DRR as native u16, the SPI core shifts MSB-first,
     * independent of CPU endianness. */
    status = XSpi_Transfer(d->Spi, (u8 *)&txw, (u8 *)&rxw, 2U);
    if (status != XST_SUCCESS) {
        return status;
    }
    *result = rxw;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Initializes: stores SPI / chip select, default channel is SENSOR_NTC and applies
* the config immediately.
*
* @return XST_SUCCESS / underlying error.
******************************************************************************/
int Ads1118_Init(Ads1118 *d, XSpi *spi, u8 cs)
{
    u16 dummy;

    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(spi != NULL);

    d->Spi = spi;
    d->Cs = cs;
    d->Mux = ADS1118_MUX_SENSOR_NTC;

    /* Write the current config (takes effect immediately in continuous mode) */
    return Ads1118_Transfer(d, Ads1118_BuildConfig(d, ADS1118_NOP_NORMAL),
                            &dummy);
}

/*****************************************************************************/
/**
* @brief  Switches the input channel (writes a new MUX config, takes effect immediately in
* continuous mode).
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
* @brief  Reads the most recent conversion result (writes NOP=01b to fetch).
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
* @brief  Writes the config register primitive (raw).
******************************************************************************/
int Ads1118_WriteConfig(Ads1118 *d, u16 cfg)
{
    u16 dummy;
    return Ads1118_Transfer(d, cfg, &dummy);
}
