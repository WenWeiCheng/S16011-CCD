/******************************************************************************
* @file ads1118.h
*
* ads1118 thermistor / TEC voltage / TEC current ADC driver.
*
* Shares the XSpi instance, cs=Spi_cs_2; SPI mode 1 (CPOL=0, CPHA=1).
* Operating mode: continuous conversion (MODE=0), 860SPS, PGA full scale +/-4.096V.
* Every transaction is always 16-bit: write config (NOP=00) or write fetch (NOP=01) and
* synchronously read back the previous conversion result.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef ADS1118_H
#define ADS1118_H

#include "xil_types.h"
#include "xstatus.h"
#include "xspi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Input channels (single-ended to GND, MUX[2:0]) */
typedef enum {
    ADS1118_MUX_SENSOR_NTC = 0x4U,   /* AIN0: CCD sensor NTC */
    ADS1118_MUX_TEC_V      = 0x5U,   /* AIN1: TEC output voltage */
    ADS1118_MUX_TEC_I      = 0x6U,   /* AIN2: TEC output current */
    ADS1118_MUX_ENV_NTC    = 0x7U    /* AIN3: ambient NTC */
} Ads1118_Mux;

/* Config register bit fields (for WriteConfig / custom construction) */
#define ADS1118_CFG_SS_MASK        (1U << 15)
#define ADS1118_CFG_MUX_SHIFT      12U
#define ADS1118_CFG_PGA_SHIFT      9U
#define ADS1118_CFG_MODE_SHIFT     8U
#define ADS1118_CFG_DR_SHIFT       5U
#define ADS1118_CFG_TS_MODE_SHIFT  4U
#define ADS1118_CFG_PULLUP_SHIFT   3U
#define ADS1118_CFG_NOP_SHIFT      1U

#define ADS1118_DR_860SPS          (0x6U << ADS1118_CFG_DR_SHIFT)

/* Continuous mode (SS=0, MODE=0) base config: PGA=000b (+/-4.096V), DR=110b (860SPS) */
#define ADS1118_CFG_CONTINUOUS_BASE  ADS1118_DR_860SPS

typedef struct {
    XSpi *Spi;
    u8   Cs;
    Ads1118_Mux Mux;      /* current channel */
} Ads1118;

int  Ads1118_Init(Ads1118 *d, XSpi *spi, u8 cs);
int  Ads1118_SetChannel(Ads1118 *d, Ads1118_Mux mux);
int  Ads1118_ReadRaw(Ads1118 *d, s16 *raw);
int  Ads1118_WriteConfig(Ads1118 *d, u16 cfg);

#ifdef __cplusplus
}
#endif

#endif /* ADS1118_H */
