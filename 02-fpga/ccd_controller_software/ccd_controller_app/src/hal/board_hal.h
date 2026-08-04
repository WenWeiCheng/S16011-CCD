/******************************************************************************
* @file board_hal.h
*
* Board-level hardware abstraction: declarations of the shared global Xilinx instances
* and app driver instances, plus BoardHal_Init (initializes peripherals + wires up INTC).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* 1.1   wwc  26/08/03 Remove dead BoardHal_SelfTest
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

#include "../devices/ccd.h"
#include "../devices/heartbeat.h"
#include "../devices/key.h"
#include "../devices/led.h"
#include "../devices/fx2.h"
#include "../devices/adn8833.h"
#include "../devices/uart.h"
#include "../devices/ads1118.h"
#include "../devices/dac8311.h"
#include "../devices/ad9826.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Shared global Xilinx instances (zeroed, easy to inspect in the debugger) */
extern XSpi      gSpi;
extern XGpio     gGpioFx2Fifo;
extern XGpio     gGpioGeneral;
extern XGpio     gGpioKey;
extern XGpio     gGpioLed;
extern XTmrCtr   gTimer0;
extern XTmrCtr   gTimer1;
extern XUartLite gUart;
extern XIntc     gIntc;

/* Global app driver instances */
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

/* Initialize all peripherals and wire up INTC (returns XST_SUCCESS / XST_FAILURE) */
int  BoardHal_Init(void);

#ifdef __cplusplus
}
#endif

#endif /* BOARD_HAL_H */
