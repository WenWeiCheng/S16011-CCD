/******************************************************************************
* @file board_config.h
*
* 板级配置：SPI 片选、GPIO 位映射、DAC/ADC 参考、NTC 参数等。
*
* 本文件只含"板级事实"，不含 Xilinx 命名（XPAR_*），以便移植到其它平台。
* 具体的 Xilinx 设备/中断向量映射见 hal/board_hal.c。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H

#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * SPI 片选分配（AXI Quad SPI，3 片选，16-bit 帧）
 * ==========================================================================*/
#define SPI_CS_AD9826            0U   /* CCD ADC */
#define SPI_CS_DAC8311           1U   /* TEC 输出电压 DAC */
#define SPI_CS_ADS1118           2U   /* 温敏电阻 / TEC 电压电流 ADC */

#define SPI_TRANSFER_BITS        16U  /* 三颗芯片均为 16-bit 帧 */

/* ============================================================================
 * GPIO 位映射
 * ==========================================================================*/
/* Gpio_fx2fifo (XPAR_GPIO_0) */
#define FX2_GPIO_SLOE_N_BIT      0U   /* 输出 */
#define FX2_GPIO_SLRD_N_BIT      1U   /* 输出 */
#define FX2_GPIO_FIFO_ADDR0_BIT  2U   /* 输出 */
#define FX2_GPIO_FIFO_ADDR1_BIT  3U   /* 输出 */
#define FX2_GPIO_PA0_BIT         4U   /* 输入，FX2 sync：1=配置完成 */

#define FX2_GPIO_OUT_MASK        ((1U<<FX2_GPIO_SLOE_N_BIT) | \
                                  (1U<<FX2_GPIO_SLRD_N_BIT) | \
                                  (1U<<FX2_GPIO_FIFO_ADDR0_BIT) | \
                                  (1U<<FX2_GPIO_FIFO_ADDR1_BIT))
#define FX2_GPIO_IN_MASK         (1U<<FX2_GPIO_PA0_BIT)

/* Gpio_general (XPAR_GPIO_1) */
#define ADN8833_EN_BIT           0U   /* 输出，TEC 电源使能 */
#define ADN8833_EN_MASK          (1U<<ADN8833_EN_BIT)

/* Gpio_key (XPAR_GPIO_2，含中断) */
#define KEY0_BIT                 0U   /* 输入 */
#define KEY1_BIT                 1U   /* 输入 */
#define KEY_IN_MASK              ((1U<<KEY0_BIT) | (1U<<KEY1_BIT))

/* Gpio_led (XPAR_GPIO_3) */
#define LED0_BIT                 0U   /* 输出 */
#define LED1_BIT                 1U   /* 输出 */
#define LED_OUT_MASK             ((1U<<LED0_BIT) | (1U<<LED1_BIT))

/*
 * LED 极性：1=低电平点亮（大多数板子），0=高电平点亮。
 * 若实际板子相反，改这里即可，驱动内部按此宏取反。
 */
#define LED_ACTIVE_LOW           1U

/* 按键有效电平掩码：置 1 的位为低有效（按下=0），置 0 的位为高有效。 */
#define KEY_ACTIVE_LOW_MASK      (KEY_IN_MASK)

/* ============================================================================
 * 系统时钟（timer 周期换算用）
 * ==========================================================================*/
#define BOARD_CLK_FREQ_HZ        100000000UL   /* MicroBlaze 系统时钟 100MHz */

/* ============================================================================
 * dac8311
 * ==========================================================================*/
#define DAC8311_VREF_V           2.5f          /* 参考电压 2.5V，14-bit */

/* ============================================================================
 * ads1118
 * ==========================================================================*/
#define ADS1118_FS_VOLT          4.096f        /* PGA=000b 满量程 ±4.096V */
#define ADS1118_SPS              860U          /* DR=110b 数据率 */

/* ============================================================================
 * NTC 温敏电阻
 *
 * TODO(待确认)：当前为常见默认值（10kΩ NTC，B=3435，分压串联 10kΩ）。
 * 待拿到板子实际 BOM 的 NTC 规格后替换。
 * ==========================================================================*/
#define NTC_R25_OHM              10000         /* 25°C 标称阻值 */
#define NTC_BETA                 3435          /* B 值（25/85） */
#define NTC_SERIES_R_OHM         10000         /* 分压上/下拉串联电阻 */

/* ============================================================================
 * S16011 传感器默认几何（image/bevel/blank，见 00-docs/verilog-design/ccd_driver.md）
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
 * NTC 分压拓扑
 * TODO(待确认)：当前假设 Vref → Rseries → NTC → GND，ADC 测 NTC 端电压。
 * 待拿到板子实际电路后确认/替换。
 * ==========================================================================*/
#define NTC_DIV_VREF_V           4.096f        /* 分压参考电压（与 ADC FS 一致） */

/* ============================================================================
 * TEC 输出电流换算（ads1118 AIN2）
 * TODO(待确认)：当前假定 1 A/V（1Ω 采样电阻），待硬件确认后替换。
 * ==========================================================================*/
#define TEC_I_A_PER_V            1.0f          /* A per measured V */

#ifdef __cplusplus
}
#endif

#endif /* BOARD_CONFIG_H */
