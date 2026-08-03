/******************************************************************************
* @file dac8311.h
*
* dac8311 TEC output voltage DAC driver.
*
* Shares the XSpi instance, cs=Spi_cs_1; SPI mode 2 (CPOL=1, CPHA=0).
* 16-bit frame: [15:14] PD1:PD0 control bits, [13:0] data; MSB first.
* Vout = Vref x D / 2^14, Vref=2.5V (board_config.h).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef DAC8311_H
#define DAC8311_H

#include "xil_types.h"
#include "xstatus.h"
#include "xspi.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    XSpi *Spi;
    u8   Cs;
    float Vref;       /* reference voltage (V) */
} Dac8311;

/* Control bits [15:14] */
#define DAC8311_PD_NORMAL       0U   /* 00: normal output */
#define DAC8311_PD_1K           1U   /* 01: Power-down, ~1k ohm */
#define DAC8311_PD_100K         2U   /* 10: Power-down, ~100k ohm */
#define DAC8311_PD_HIGHZ        3U   /* 11: Power-down, High-Z */

int  Dac8311_Init(Dac8311 *d, XSpi *spi, u8 cs, float vref);
int  Dac8311_SetVoltage(Dac8311 *d, float volt);
int  Dac8311_SetRaw(Dac8311 *d, u16 code);
int  Dac8311_SetPowerDown(Dac8311 *d, u8 pd);

#ifdef __cplusplus
}
#endif

#endif /* DAC8311_H */
