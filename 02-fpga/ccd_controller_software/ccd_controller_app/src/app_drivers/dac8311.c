/******************************************************************************
* @file dac8311.c
*
* dac8311 driver implementation. SPI mode 2 (CPOL=1, CPHA=0), 16-bit frames.
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
* @brief  Starts a 16-bit transfer (writing dac8311, no readback).
*
* Switches to SPI mode 2 and asserts the chip select before transferring.
*
* @return XST_SUCCESS / underlying error.
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
* @brief  Initializes: stores the SPI / chip select / reference voltage.
*
* @return XST_SUCCESS.
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
* @brief  Sets the output voltage (normal mode, PD=00).
*
* @param  volt Target voltage (V), clamped to 0..Vref.
*
* @return XST_SUCCESS / underlying error.
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
* @brief  Writes raw 16-bit ([15:14] control bits + [13:0] data).
******************************************************************************/
int Dac8311_SetRaw(Dac8311 *d, u16 code)
{
    return Dac8311_Transfer(d, code);
}

/*****************************************************************************/
/**
* @brief  Enters Power-down mode (pd: 1=1k ohm, 2=100k ohm, 3=High-Z).
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
