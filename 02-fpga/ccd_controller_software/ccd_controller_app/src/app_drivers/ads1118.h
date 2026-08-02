/******************************************************************************
* @file ads1118.h
*
* ads1118 温敏电阻 / TEC 电压 / TEC 电流 ADC 驱动。
*
* 共用 XSpi 实例，cs=Spi_cs_2；SPI mode 1（CPOL=0, CPHA=1）。
* 运行模式：连续转换（MODE=0），860SPS，PGA 满量程 ±4.096V。
* 每笔事务恒为 16-bit：写配置（NOP=00）或写取数（NOP=01）并同步回读
* 上一次转换结果。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
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

/* 输入通道（单端对 GND，MUX[2:0]） */
typedef enum {
    ADS1118_MUX_SENSOR_NTC = 0x4U,   /* AIN0: CCD 传感器 NTC */
    ADS1118_MUX_TEC_V      = 0x5U,   /* AIN1: TEC 输出电压 */
    ADS1118_MUX_TEC_I      = 0x6U,   /* AIN2: TEC 输出电流 */
    ADS1118_MUX_ENV_NTC    = 0x7U    /* AIN3: 环境 NTC */
} Ads1118_Mux;

/* 配置寄存器位字段（供 WriteConfig / 自定义构造） */
#define ADS1118_CFG_SS_MASK        (1U << 15)
#define ADS1118_CFG_MUX_SHIFT      12U
#define ADS1118_CFG_PGA_SHIFT      9U
#define ADS1118_CFG_MODE_SHIFT     8U
#define ADS1118_CFG_DR_SHIFT       5U
#define ADS1118_CFG_TS_MODE_SHIFT  4U
#define ADS1118_CFG_PULLUP_SHIFT   3U
#define ADS1118_CFG_NOP_SHIFT      1U

#define ADS1118_DR_860SPS          (0x6U << ADS1118_CFG_DR_SHIFT)

/* 连续模式（SS=0, MODE=0）基础配置：PGA=000b(±4.096V)、DR=110b(860SPS) */
#define ADS1118_CFG_CONTINUOUS_BASE  ADS1118_DR_860SPS

typedef struct {
    XSpi *Spi;
    u8   Cs;
    Ads1118_Mux Mux;      /* 当前通道 */
} Ads1118;

int  Ads1118_Init(Ads1118 *d, XSpi *spi, u8 cs);
int  Ads1118_SetChannel(Ads1118 *d, Ads1118_Mux mux);
int  Ads1118_ReadRaw(Ads1118 *d, s16 *raw);
int  Ads1118_WriteConfig(Ads1118 *d, u16 cfg);

#ifdef __cplusplus
}
#endif

#endif /* ADS1118_H */
