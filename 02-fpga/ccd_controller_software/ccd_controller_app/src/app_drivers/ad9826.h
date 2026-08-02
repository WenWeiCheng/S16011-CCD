/******************************************************************************
* @file ad9826.h
*
* ad9826 CCD ADC 配置驱动。
*
* 共用 XSpi 实例，cs=Spi_cs_0；SPI mode 0（CPOL=0, CPHA=0）。
* 16-bit 帧：R/Wb(15) / A[2:0](14:12) / 3'b000(11:9) / D[8:0](8:0)。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef AD9826_H
#define AD9826_H

#include "xil_types.h"
#include "xstatus.h"
#include "xspi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 寄存器地址（A2:A1:A0） */
#define AD9826_REG_CONFIG      0x0U
#define AD9826_REG_MUX         0x1U
#define AD9826_REG_GAIN_RED    0x2U
#define AD9826_REG_GAIN_GREEN  0x3U
#define AD9826_REG_GAIN_BLUE   0x4U
#define AD9826_REG_OFFSET_RED  0x5U
#define AD9826_REG_OFFSET_GREEN 0x6U
#define AD9826_REG_OFFSET_BLUE 0x7U

/* Configuration 寄存器位（D8、D1 恒置 0） */
#define AD9826_CFG_INPUT_RANGE  (1U << 7)   /* 1=4V, 0=2V */
#define AD9826_CFG_VREF         (1U << 6)   /* 1=内部 VREF 使能 */
#define AD9826_CFG_3CH_MODE     (1U << 5)   /* 1=3通道, 0=1通道 */
#define AD9826_CFG_CDS          (1U << 4)   /* 1=CDS, 0=SHA */
#define AD9826_CFG_CLAMP        (1U << 3)   /* 1=钳位 4V, 0=3V */
#define AD9826_CFG_PWR_DN       (1U << 2)   /* 1=Power-Down */
#define AD9826_CFG_OUT_MODE     (1U << 0)   /* 0=2字节, 1=1字节 */

/* MUX Config 寄存器位（D8、D3:D0 恒置 0） */
#define AD9826_MUX_ORDER        (1U << 7)   /* 1=R-G-B, 0=B-G-R */
#define AD9826_MUX_RED          (1U << 6)
#define AD9826_MUX_GREEN        (1U << 5)
#define AD9826_MUX_BLUE         (1U << 4)

/* 上电默认值 */
#define AD9826_DEFAULT_CONFIG   0xF8U   /* 4V, VREF, 3CH, CDS, 钳位4V, 2字节 */
#define AD9826_DEFAULT_MUX      0xF0U   /* R-G-B，三通道全开 */

typedef struct {
    u8 Config;                    /* Configuration（D8=0, D7..D0） */
    u8 Mux;                       /* MUX Config（D7..D4） */
    u8 GainR, GainG, GainB;       /* PGA 增益码 0~63（G=0→1.0, G=63→6.0） */
    u8 OffR, OffG, OffB;          /* 偏移码（9-bit 有符号） */
} Ad9826_Config;

typedef struct {
    XSpi *Spi;
    u8   Cs;
} Ad9826;

int  Ad9826_Init(Ad9826 *d, XSpi *spi, u8 cs);
int  Ad9826_Configure(Ad9826 *d, const Ad9826_Config *cfg);
int  Ad9826_WriteReg(Ad9826 *d, u8 addr, u8 val);
int  Ad9826_ReadReg(Ad9826 *d, u8 addr, u8 *val);

#ifdef __cplusplus
}
#endif

#endif /* AD9826_H */
