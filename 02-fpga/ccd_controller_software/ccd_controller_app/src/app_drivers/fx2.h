/******************************************************************************
* @file fx2.h
*
* FX2 Slave FIFO 控制：基于 Gpio_fx2fifo，固定向端点 2 写数据。
* 软件只设静态引脚电平（sloe_n/slrd_n/FIFOADR），实际读写时序由 FPGA
* ccd_controller.frame_tx 完成；PA0 为 FX2 sync 输入（高=配置完成）。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef FX2_H
#define FX2_H

#include "xil_types.h"
#include "xstatus.h"
#include "xgpio.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 端点号 → FIFOADR[1:0] */
#define FX2_EP_2    0U   /* FIFOADR=00 */
#define FX2_EP_4    1U   /* FIFOADR=01 */
#define FX2_EP_6    2U   /* FIFOADR=10 */
#define FX2_EP_8    3U   /* FIFOADR=11 */

typedef struct {
    XGpio *Gpio;
    u32 OutVal;       /* 当前输出位值（含 SLOE/SLRD/FIFOADR） */
} Fx2;

int  Fx2_Init(Fx2 *d, XGpio *gpio);
void Fx2_SetEndpoint(Fx2 *d, u8 ep);
u8   Fx2_IsUsbReady(Fx2 *d);   /* 读 PA0：1=FX2 已配置 */

#ifdef __cplusplus
}
#endif

#endif /* FX2_H */
