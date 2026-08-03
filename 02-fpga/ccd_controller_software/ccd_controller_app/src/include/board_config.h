/******************************************************************************
* @file board_config.h
*
* Board-level configuration: SPI chip selects, GPIO bit mappings, DAC/ADC references, NTC parameters, etc.
*
* This file contains only "board facts", no Xilinx names (XPAR_*), to ease porting to other platforms.
* The concrete Xilinx device / interrupt vector mapping is in hal/board_hal.c.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H

#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * SPI chip select assignment (AXI Quad SPI, 3 chip selects, 16-bit frames)
 * ==========================================================================*/
#define SPI_CS_AD9826            0U   /* CCD ADC */
#define SPI_CS_DAC8311           1U   /* TEC output voltage DAC */
#define SPI_CS_ADS1118           2U   /* thermistor / TEC voltage-current ADC */

#define SPI_TRANSFER_BITS        16U  /* all three chips use 16-bit frames */

/* ============================================================================
 * GPIO bit mapping
 * ==========================================================================*/
/* Gpio_fx2fifo (XPAR_GPIO_0) */
#define FX2_GPIO_SLOE_N_BIT      0U   /* output */
#define FX2_GPIO_SLRD_N_BIT      1U   /* output */
#define FX2_GPIO_FIFO_ADDR0_BIT  2U   /* output */
#define FX2_GPIO_FIFO_ADDR1_BIT  3U   /* output */
#define FX2_GPIO_PA0_BIT         4U   /* input, FX2 sync: 1=config done */

#define FX2_GPIO_OUT_MASK        ((1U<<FX2_GPIO_SLOE_N_BIT) | \
                                  (1U<<FX2_GPIO_SLRD_N_BIT) | \
                                  (1U<<FX2_GPIO_FIFO_ADDR0_BIT) | \
                                  (1U<<FX2_GPIO_FIFO_ADDR1_BIT))
#define FX2_GPIO_IN_MASK         (1U<<FX2_GPIO_PA0_BIT)

/* Gpio_general (XPAR_GPIO_1) */
#define ADN8833_EN_BIT           0U   /* output, TEC power enable */
#define ADN8833_EN_MASK          (1U<<ADN8833_EN_BIT)

/* Gpio_key (XPAR_GPIO_2, with interrupts) */
#define KEY0_BIT                 0U   /* input */
#define KEY1_BIT                 1U   /* input */
#define KEY_IN_MASK              ((1U<<KEY0_BIT) | (1U<<KEY1_BIT))

/* Gpio_led (XPAR_GPIO_3) */
#define LED0_BIT                 0U   /* output */
#define LED1_BIT                 1U   /* output */
#define LED_OUT_MASK             ((1U<<LED0_BIT) | (1U<<LED1_BIT))

/*
 * LED polarity: 1=active low (most boards), 0=active high.
 * If the actual board is reversed, change it here; the driver inverts per this macro.
 */
#define LED_ACTIVE_LOW           0U

/* Key active-level mask: bits set to 1 are active low (pressed=0), bits set to 0 are active high. */
#define KEY_ACTIVE_LOW_MASK      (KEY_IN_MASK)

/* ============================================================================
 * System clock (used for timer period conversion)
 * ==========================================================================*/
#define BOARD_CLK_FREQ_HZ        100000000UL   /* MicroBlaze system clock 100MHz */

/* ============================================================================
 * dac8311
 * ==========================================================================*/
#define DAC8311_VREF_V           2.5f          /* reference voltage 2.5V, 14-bit */

/* ============================================================================
 * ads1118
 * ==========================================================================*/
#define ADS1118_FS_VOLT          4.096f        /* PGA=000b full scale +/-4.096V */
#define ADS1118_SPS              860U          /* DR=110b data rate */

/* ============================================================================
 * NTC thermistor
 *
 * TODO(pending confirmation): currently common default values (10k ohm NTC, B=3435, divider series 10k ohm).
 * Replace after obtaining the actual NTC specs from the board BOM.
 * ==========================================================================*/
#define NTC_R25_OHM              10000         /* nominal resistance at 25C */
#define NTC_BETA                 3435          /* B value (25/85) */
#define NTC_SERIES_R_OHM         10000         /* divider series pull-up/pull-down resistor */

/* ============================================================================
 * S16011 sensor default geometry (image/bevel/blank, see 00-docs/verilog-design/ccd_driver.md)
 * ==========================================================================*/
#define CCD_IMG_WIDTH_DEFAULT    1024U
#define CCD_IMG_HEIGHT_DEFAULT   64U
#define CCD_BEVEL_L_DEFAULT      6U
#define CCD_BEVEL_T_DEFAULT      2U
#define CCD_BEVEL_R_DEFAULT      6U
#define CCD_BEVEL_B_DEFAULT      4U
#define CCD_BLANK_L_DEFAULT      4U
#define CCD_BLANK_R_DEFAULT      4U

/* ============================================================================
 * NTC divider topology
 * TODO(pending confirmation): currently assumes Vref -> Rseries -> NTC -> GND, ADC measures NTC terminal voltage.
 * Confirm/replace after getting the actual board circuit.
 * ==========================================================================*/
#define NTC_DIV_VREF_V           4.096f        /* divider reference voltage (matches ADC FS) */

/* ============================================================================
 * TEC output current conversion (ads1118 AIN2)
 * TODO(pending confirmation): currently assumes 1 A/V (1 ohm sense resistor), replace after hardware confirmation.
 * ==========================================================================*/
#define TEC_I_A_PER_V            1.0f          /* A per measured V */

#ifdef __cplusplus
}
#endif

#endif /* BOARD_CONFIG_H */
