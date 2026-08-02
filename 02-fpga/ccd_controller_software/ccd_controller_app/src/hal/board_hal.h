/******************************************************************************
* @file board_hal.h
*
* 板级硬件抽象：全局共享 Xilinx 实例 + app 驱动实例的声明，
* 以及 BoardHal_Init（初始化外设 + 接线 INTC）。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef BOARD_HAL_H
#define BOARD_HAL_H

#include "xil_types.h"
#include "xstatus.h"
#include "xspi.h"
#include "xgpio.h"
#include "xtmrctr.h"
#include "xuartlite.h"
#include "xintc.h"

#include "ccd_controller.h"
#include "../app_drivers/heartbeat.h"
#include "../app_drivers/key.h"
#include "../app_drivers/led.h"
#include "../app_drivers/fx2.h"
#include "../app_drivers/adn8833.h"
#include "../app_drivers/ccd.h"
#include "../app_drivers/uart.h"
#include "../app_drivers/ads1118.h"
#include "../app_drivers/dac8311.h"
#include "../app_drivers/ad9826.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 全局共享 Xilinx 实例（清零，方便调试器查看） */
extern XSpi      gSpi;
extern XGpio     gGpioFx2Fifo;
extern XGpio     gGpioGeneral;
extern XGpio     gGpioKey;
extern XGpio     gGpioLed;
extern XTmrCtr   gTimer0;
extern XTmrCtr   gTimer1;
extern XUartLite gUart;
extern XIntc     gIntc;

/* 全局 app 驱动实例 */
extern Heartbeat    gHeartbeat;
extern Key          gKey;
extern Led          gLed;
extern Fx2          gFx2;
extern Adn8833      gAdn8833;
extern Ccd          gCcd;
extern Uart         gUartDrv;
extern Ads1118      gAds1118;
extern Dac8311      gDac8311;
extern Ad9826       gAd9826;
extern CcdController gCcdCtrl;

/* 初始化所有外设并接线 INTC（返回 XST_SUCCESS / XST_FAILURE） */
int  BoardHal_Init(void);

/* CcdController 自检 + 状态打印（供冒烟测试） */
void BoardHal_SelfTest(void);

#ifdef __cplusplus
}
#endif

#endif /* BOARD_HAL_H */
