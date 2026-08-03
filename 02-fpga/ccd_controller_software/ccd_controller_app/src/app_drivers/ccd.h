/******************************************************************************
* @file ccd.h
*
* CCD exposure control + frame path driver: combines CcdController (frame readout /
* buffering / send) with timer1 64-bit cascade mode (exposure duration timing).
* Distinguishes single and live modes.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef CCD_H
#define CCD_H

#include "xil_types.h"
#include "xstatus.h"
#include "xtmrctr.h"
#include "../hal/ccd_controller.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    CCD_MODE_SINGLE = 0,   /* single capture: expose -> readout -> send, done returns to IDLE */
    CCD_MODE_LIVE          /* continuous capture: driver restarts exposure and triggers send automatically */
} CcdMode;

typedef enum {
    CCD_IDLE = 0,
    CCD_EXPOSING,
    CCD_READING,
    CCD_TX
} CcdState;

/* State change callback */
typedef void (*CcdHandler)(CcdState st, void *ref);

typedef struct {
    CcdController *Ctrl;
    XTmrCtr *Tmr1;
    u32 IntrVecId;
    CcdMode Mode;
    CcdState State;
    u64 ExposureUs;           /* current exposure duration (us) */
    CcdHandler Handler;
    void *HandlerRef;
} Ccd;

int  Ccd_Init(Ccd *d, CcdController *ctrl, XTmrCtr *tmr1, u32 IntrVecId);
int  Ccd_StartCapture(Ccd *d, CcdMode mode, u64 exposure_us);
void Ccd_Stop(Ccd *d);              /* stop: abort exposure, return to IDLE */
void Ccd_Abort(Ccd *d);             /* clear exposure=0 to abort the current exposure */
void Ccd_TriggerSend(Ccd *d);       /* manually trigger frame send to FX2 */
u8   Ccd_GetFrameNum(Ccd *d);
u8   Ccd_IsDdrReady(Ccd *d);
u8   Ccd_GetException(Ccd *d);
u32  Ccd_GetExceptionCnt(Ccd *d);
CcdMode Ccd_GetMode(Ccd *d);
void Ccd_RegisterHandler(Ccd *d, CcdHandler hdl, void *ref);

#ifdef __cplusplus
}
#endif

#endif /* CCD_H */
