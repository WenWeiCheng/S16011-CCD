/******************************************************************************
* @file ccd.c
*
* CCD exposure control + frame path driver implementation.
*
* State machine (single): IDLE -> EXPOSING -> READING -> TX -> IDLE
* State machine (live) : IDLE -> EXPOSING -> READING -> TX -> EXPOSING -> ... -> IDLE
*
* - Exposure timing: timer1 64-bit cascade (XTC_CASCADE_MODE_OPTION), interrupt only on counter0.
* - Exposure expiry ISR: CcdController_StopCapture (exposure=0 falling edge starts readout).
* - Live mode: automatically TriggerSend after exposure expiry; restart exposure after tx_done.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* 1.1   wwc  26/08/03 Complete function doc comments (Xilinx style)
* </pre>
******************************************************************************/
#include "ccd.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/*****************************************************************************/
/**
* @brief  Calls back the app on state change.
*
* @param  d  Ccd instance.
******************************************************************************/
static void Ccd_FireHandler(Ccd *d)
{
    if (d->Handler != NULL) {
        d->Handler(d->State, d->HandlerRef);
    }
}

/*****************************************************************************/
/**
* @brief  Starts the exposure timer (timer1 64-bit cascade, one-shot).
*
* counts = exposure_us x (clock MHz); reset64 = 2^64 - counts;
* counter1 = upper 32 bits, counter0 = lower 32 bits (counter0 interrupt is valid
* when cascaded).
*
* @param  d  Ccd instance.
******************************************************************************/
static void Ccd_StartExposureTimer(Ccd *d)
{
    u64 counts = d->ExposureUs * (u64)(BOARD_CLK_FREQ_HZ / 1000000UL);
    u64 reset = (u64)0xFFFFFFFFFFFFFFFFULL - counts + 1ULL;

    XTmrCtr_SetResetValue(d->Tmr1, 1U, (u32)(reset >> 32));   /* upper 32 */
    XTmrCtr_SetResetValue(d->Tmr1, 0U, (u32)(reset & 0xFFFFFFFFU)); /* lower 32 */
    XTmrCtr_Reset(d->Tmr1, 1U);
    XTmrCtr_Reset(d->Tmr1, 0U);
    XTmrCtr_Start(d->Tmr1, 0U);
}

/*****************************************************************************/
/**
* @brief  Starts exposure: sets exposure=1 + starts the timer, enters EXPOSING.
*
* @param  d  Ccd instance.
*
* @return XST_SUCCESS / XST_DEVICE_BUSY (DDR3 not ready).
******************************************************************************/
static int Ccd_StartExposure(Ccd *d)
{
    int status;

    status = CcdController_StartCapture(d->Ctrl);
    if (status != XST_SUCCESS) {
        return status;
    }
    Ccd_StartExposureTimer(d);

    d->State = CCD_EXPOSING;
    Ccd_FireHandler(d);
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Exposure expired (inside timer1 ISR): exposure=0 starts readout, enters READING.
*         Live mode then triggers frame send automatically.
*
* @param  d  Ccd instance.
******************************************************************************/
static void Ccd_OnExposureDone(Ccd *d)
{
    CcdController_StopCapture(d->Ctrl);
    d->State = CCD_READING;
    Ccd_FireHandler(d);

    if (d->Mode == CCD_MODE_LIVE) {
        Ccd_TriggerSend(d);   /* trigger frame send after exposure expiry */
    }
}

/*****************************************************************************/
/**
* @brief  Frame send complete (CcdController tx_done callback): enters TX.
*         Live mode restarts exposure automatically; single mode returns to IDLE.
*
* @param  d  Ccd instance.
******************************************************************************/
static void Ccd_OnTxDone(Ccd *d)
{
    d->State = CCD_TX;
    Ccd_FireHandler(d);

    if (d->Mode == CCD_MODE_LIVE) {
        Ccd_StartExposure(d);
    } else {
        d->State = CCD_IDLE;
        Ccd_FireHandler(d);
    }
}

/*****************************************************************************/
/**
* @brief  CcdController interrupt callback (tx_done / exception).
*
* @param  IntrMask  Combination of CCDC_INTR_TX_DONE / CCDC_INTR_EXCEPTION.
* @param  ref       Ccd instance pointer.
******************************************************************************/
static void Ccd_CtrlHandler(u32 IntrMask, void *ref)
{
    Ccd *d = (Ccd *)ref;

    if (IntrMask & CCDC_INTR_TX_DONE) {
        Ccd_OnTxDone(d);
    }
    if (IntrMask & CCDC_INTR_EXCEPTION) {
        /* Frame exception: abort the live loop back to IDLE to avoid getting stuck in READING */
        if (d->Mode == CCD_MODE_LIVE) {
            Ccd_Stop(d);
        }
    }
}

/*****************************************************************************/
/**
* @brief  XTmrCtr callback of timer1 (exposure expired).
*
* @param  ref            Ccd instance pointer.
* @param  TmrCtrNumber   Number of the counter that triggered (should be 0).
******************************************************************************/
static void Ccd_ExposureHandler(void *ref, u8 TmrCtrNumber)
{
    Ccd *d = (Ccd *)ref;

    if (XTmrCtr_IsExpired(d->Tmr1, TmrCtrNumber)) {
        Ccd_OnExposureDone(d);
    }
}

/*****************************************************************************/
/**
* @brief  Initializes the ccd driver.
*
* @param  ctrl    CcdController instance (initialized by board_hal).
* @param  tmr1    XTmrCtr instance of timer1 (initialized by board_hal).
* @param  IntrVecId INTC vector number of timer1.
*
* @return XST_SUCCESS.
******************************************************************************/
int Ccd_Init(Ccd *d, CcdController *ctrl, XTmrCtr *tmr1, u32 IntrVecId)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(ctrl != NULL);
    Xil_AssertNonvoid(tmr1 != NULL);

    d->Ctrl = ctrl;
    d->Tmr1 = tmr1;
    d->IntrVecId = IntrVecId;
    d->Mode = CCD_MODE_SINGLE;
    d->State = CCD_IDLE;
    d->ExposureUs = 0U;
    d->Handler = NULL;
    d->HandlerRef = NULL;

    CcdController_SetHandler(ctrl, Ccd_CtrlHandler, d);

    /* timer1 64-bit cascade, interrupt only on counter0; one-shot (no auto-reload) */
    XTmrCtr_SetOptions(tmr1, 0U,
                       XTC_INT_MODE_OPTION | XTC_CASCADE_MODE_OPTION);
    XTmrCtr_SetHandler(tmr1, Ccd_ExposureHandler, d);
    XTmrCtr_Reset(tmr1, 0U);
    XTmrCtr_Reset(tmr1, 1U);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Starts capture (single or live).
*
* @param  d            Ccd instance.
* @param  mode         CCD_MODE_SINGLE or CCD_MODE_LIVE.
* @param  exposure_us  Exposure duration in microseconds.
*
* @return XST_SUCCESS / XST_DEVICE_BUSY (already capturing) / underlying error.
******************************************************************************/
int Ccd_StartCapture(Ccd *d, CcdMode mode, u64 exposure_us)
{
    if (d->State != CCD_IDLE) {
        return XST_DEVICE_BUSY;
    }

    d->Mode = mode;
    d->ExposureUs = exposure_us;
    return Ccd_StartExposure(d);
}

/*****************************************************************************/
/**
* @brief  Stops: aborts exposure/readout, returns to IDLE and notifies.
*
* @param  d  Ccd instance.
******************************************************************************/
void Ccd_Stop(Ccd *d)
{
    CcdController_StopCapture(d->Ctrl);
    XTmrCtr_Stop(d->Tmr1, 0U);
    d->State = CCD_IDLE;
    Ccd_FireHandler(d);
}

/*****************************************************************************/
/**
* @brief  Aborts the current exposure: only clears exposure=0, does not change state / notify.
*
* @param  d  Ccd instance.
******************************************************************************/
void Ccd_Abort(Ccd *d)
{
    CcdController_StopCapture(d->Ctrl);
    XTmrCtr_Stop(d->Tmr1, 0U);
}

/*****************************************************************************/
/**
* @brief  Manually triggers frame send to FX2 (only when DDR3 is ready and the frame
* buffer has frames).
*
* @param  d  Ccd instance.
******************************************************************************/
void Ccd_TriggerSend(Ccd *d)
{
    if (CcdController_IsDdrReady(d->Ctrl) &&
        (CcdController_GetFrameNum(d->Ctrl) > 0U)) {
        CcdController_TriggerFrameSend(d->Ctrl);
    }
}

/*****************************************************************************/
/**
* @brief  Number of readable frames in the frame buffer.
*
* @param  d  Ccd instance.
*
* @return Frame count (forwarded from CcdController_GetFrameNum).
******************************************************************************/
u8 Ccd_GetFrameNum(Ccd *d)
{
    return CcdController_GetFrameNum(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  Whether DDR3 is ready.
*
* @param  d  Ccd instance.
*
* @return 1 = ready, 0 = not ready.
******************************************************************************/
u8 Ccd_IsDdrReady(Ccd *d)
{
    return CcdController_IsDdrReady(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  Frame exception flag.
*
* @param  d  Ccd instance.
*
* @return 1 = frame exception, 0 = none.
******************************************************************************/
u8 Ccd_GetException(Ccd *d)
{
    return CcdController_GetException(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  Frame exception count.
*
* @param  d  Ccd instance.
*
* @return Accumulated frame exception count.
******************************************************************************/
u32 Ccd_GetExceptionCnt(Ccd *d)
{
    return CcdController_GetExceptionCnt(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  Current capture mode.
*
* @param  d  Ccd instance.
*
* @return CCD_MODE_SINGLE or CCD_MODE_LIVE.
******************************************************************************/
CcdMode Ccd_GetMode(Ccd *d)
{
    return d->Mode;
}

/*****************************************************************************/
/**
* @brief  Registers the state change callback.
*
* @param  d    Ccd instance.
* @param  hdl  Callback invoked on every state change; NULL disables.
* @param  ref  Opaque reference passed back to the callback.
******************************************************************************/
void Ccd_RegisterHandler(Ccd *d, CcdHandler hdl, void *ref)
{
    d->Handler = hdl;
    d->HandlerRef = ref;
}
