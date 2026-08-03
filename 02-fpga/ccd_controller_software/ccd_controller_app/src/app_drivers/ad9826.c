/******************************************************************************
* @file ad9826.c
*
* ad9826 driver implementation. SPI mode 0 (CPOL=0, CPHA=0), 16-bit frames.
* Frame assembly: u16 = (rw<<15) | (addr<<12) | (data & 0x1FF).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "ad9826.h"
#include "xil_assert.h"

#define AD9826_DATA_MASK   0x1FFU
#define AD9826_ADDR_SHIFT  12U
#define AD9826_RW_SHIFT    15U

/*****************************************************************************/
/**
* @brief  Starts a 16-bit frame transfer (writes a command, reads back the previous frame data).
*
* Switches to SPI mode 0 and asserts the chip select before transferring.
*
* @return XST_SUCCESS / underlying error.
******************************************************************************/
static int Ad9826_Transfer(Ad9826 *d, u16 word, u16 *readback)
{
    int status;
    u16 txw = word;
    u16 rxw = 0U;

    Xil_AssertNonvoid(d != NULL);

    status = XSpi_SetOptions(d->Spi,
                             XSP_MASTER_OPTION |
                             XSP_MANUAL_SSELECT_OPTION);  /* CPOL=0, CPHA=0 */
    if (status != XST_SUCCESS) {
        return status;
    }
    XSpi_SetSlaveSelect(d->Spi, 1U << d->Cs);

    status = XSpi_Transfer(d->Spi, (u8 *)&txw, (u8 *)&rxw, 2U);
    if (status != XST_SUCCESS) {
        return status;
    }
    *readback = rxw;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Initializes: stores SPI / chip select.
*
* @return XST_SUCCESS.
******************************************************************************/
int Ad9826_Init(Ad9826 *d, XSpi *spi, u8 cs)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(spi != NULL);

    d->Spi = spi;
    d->Cs = cs;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Writes each register in order to complete the configuration.
*
* Unspecified fields are filled with the power-up defaults. Write sequence:
* Configuration -> MUX -> Red/Green/Blue PGA -> Red/Green/Blue Offset.
*
* @return XST_SUCCESS / underlying error.
******************************************************************************/
int Ad9826_Configure(Ad9826 *d, const Ad9826_Config *cfg)
{
    int status;
    Ad9826_Config c;

    if (cfg != NULL) {
        c = *cfg;
    } else {
        c.Config = AD9826_DEFAULT_CONFIG;
        c.Mux = AD9826_DEFAULT_MUX;
        c.GainR = 0U;
        c.GainG = 0U;
        c.GainB = 0U;
        c.OffR = 0U;
        c.OffG = 0U;
        c.OffB = 0U;
    }

    status = Ad9826_WriteReg(d, AD9826_REG_CONFIG, c.Config);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = Ad9826_WriteReg(d, AD9826_REG_MUX, c.Mux);
    if (status != XST_SUCCESS) {
        return status;
    }

    /* PGA: D8:D6=000, D5:D0=gain code */
    status = Ad9826_WriteReg(d, AD9826_REG_GAIN_RED, c.GainR & 0x3FU);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = Ad9826_WriteReg(d, AD9826_REG_GAIN_GREEN, c.GainG & 0x3FU);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = Ad9826_WriteReg(d, AD9826_REG_GAIN_BLUE, c.GainB & 0x3FU);
    if (status != XST_SUCCESS) {
        return status;
    }

    /* Offset: 9-bit signed */
    status = Ad9826_WriteReg(d, AD9826_REG_OFFSET_RED, c.OffR);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = Ad9826_WriteReg(d, AD9826_REG_OFFSET_GREEN, c.OffG);
    if (status != XST_SUCCESS) {
        return status;
    }
    return Ad9826_WriteReg(d, AD9826_REG_OFFSET_BLUE, c.OffB);
}

/*****************************************************************************/
/**
* @brief  Writes a register (R/Wb=0).
******************************************************************************/
int Ad9826_WriteReg(Ad9826 *d, u8 addr, u8 val)
{
    u16 readback;
    u16 word;

    word = (u16)((0U << AD9826_RW_SHIFT) |
                 ((u16)(addr & 0x7U) << AD9826_ADDR_SHIFT) |
                 ((u16)val & AD9826_DATA_MASK));
    return Ad9826_Transfer(d, word, &readback);
}

/*****************************************************************************/
/**
* @brief  Reads a register (R/Wb=1), for verification/debugging.
******************************************************************************/
int Ad9826_ReadReg(Ad9826 *d, u8 addr, u8 *val)
{
    u16 readback;
    u16 word;
    int status;

    word = (u16)((1U << AD9826_RW_SHIFT) |
                 ((u16)(addr & 0x7U) << AD9826_ADDR_SHIFT));
    status = Ad9826_Transfer(d, word, &readback);
    if (status != XST_SUCCESS) {
        return status;
    }
    *val = (u8)(readback & AD9826_DATA_MASK);
    return XST_SUCCESS;
}
