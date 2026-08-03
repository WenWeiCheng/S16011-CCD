/******************************************************************************
* @file fx2.h
*
* FX2 Slave FIFO control: based on Gpio_fx2fifo, writes data to endpoint 2.
* Software only sets static pin levels (sloe_n/slrd_n/FIFOADR); the actual read/write
* timing is done by the FPGA ccd_controller.frame_tx; PA0 is the FX2 sync input
* (high=configuration complete).
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

/* Endpoint number -> FIFOADR[1:0] */
#define FX2_EP_2    0U   /* FIFOADR=00 */
#define FX2_EP_4    1U   /* FIFOADR=01 */
#define FX2_EP_6    2U   /* FIFOADR=10 */
#define FX2_EP_8    3U   /* FIFOADR=11 */

typedef struct {
    XGpio *Gpio;
    u32 OutVal;       /* current output bit value (incl. SLOE/SLRD/FIFOADR) */
} Fx2;

int  Fx2_Init(Fx2 *d, XGpio *gpio);
void Fx2_SetEndpoint(Fx2 *d, u8 ep);
u8   Fx2_IsUsbReady(Fx2 *d);   /* reads PA0: 1=FX2 configured */

#ifdef __cplusplus
}
#endif

#endif /* FX2_H */
