/******************************************************************************
* @file ccd.c
*
* CCD exposure control + frame path driver implementation.
*
* State machine (single): IDLE -> EXPOSING -> READING -> IDLE (帧写入完成收尾, 帧留缓存)
* State machine (live) : IDLE -> EXPOSING -> READING -> EXPOSING -> ... -> IDLE
* State machine (burst): IDLE -> EXPOSING -> READING -> ... (N times) -> IDLE
*
* 帧发送 (fetch) 是与采集状态机正交的维度 (TxActive 标志): 发送期间采集状态
* (EXPOSING/READING/IDLE) 保持不变, 可与曝光/读出共存。
*
* - Exposure timing: timer1 64-bit cascade (XTC_CASCADE_MODE_OPTION), interrupt only on counter0.
* - Exposure expiry ISR: CcdController_StopCapture (exposure=0 falling edge starts readout).
* - Frame sending is host-driven: `acq fetch N` triggers N frame sends, paced one-by-one
*   by the TX_DONE interrupt (hardware drops a trigger issued mid-transmit).
* - Live/burst continuous capture: the FRAME_WRITTEN interrupt (one frame fully written
*   to DDR = readout done) advances the loop; the next exposure only starts once the
*   previous readout has finished (re-asserting exposure mid-readout would abort it).
* - Pause at full cache: when CCD_MAX_FRAMES frames are cached, capture waits (RdWaiting)
*   for the host to drain frames via fetch; a TX_DONE resumes it, so no frame is dropped
*   and no polling is needed.
*
* @note <pre>
* MODIFICATION HISTORY:
*
 * Ver   Who  Date     Changes
 * ----- ---- -------- -----------------------------------------------
 * 1.0   wwc  26/08/02 First release
 * 1.1   wwc  26/08/03 Complete function doc comments (Xilinx style)
 * 1.2   wwc  26/08/07 帧发送改为主机 fetch 驱动 (TX_DONE 逐帧推进, 支持多帧);
 *                     新增 burst 连续采集模式
 * 1.3   wwc  26/08/07 采集环推进改由 FRAME_WRITTEN 中断驱动 (替代 Ccd_Tick 轮询),
 *                     缓存满暂停由 TX_DONE (主机排空) 恢复
 * 1.4   wwc  26/08/07 CCD_TX 从互斥状态机拆出: 帧发送 (TxActive) 为正交维度,
 *                     可与 EXPOSING/READING 共存; single 由发送完成收尾回 IDLE
 * 1.5   wwc  26/08/07 single 收尾改由 FRAME_WRITTEN (帧写入完成) 驱动,
 *                     TX_DONE 完全不触碰采集状态机
 * 1.6   wwc  26/08/07 合并 Ccd_StartCapture/Ccd_StartBurst 为 Ccd_Start(d,n,us):
 *                     n==0->live, n==1->single, n>1->burst(n); 容量校验 n>=1 统一;
 *                     帧异常时所有激活模式统一 abort (含 single, 修复丢帧卡 READING)
 * 1.7   wwc  26/08/08 新增 Ccd_Set* 参数配置 API 与 Ccd_SoftReset, 封装 CcdController
 *                     (protocol 不再直接调用 CcdController)
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
*         Frame sending is NOT triggered here; it waits for the host's `acq fetch`
*         command (single/live/burst all behave the same way).
*
* @param  d  Ccd instance.
******************************************************************************/
static void Ccd_OnExposureDone(Ccd *d)
{
    CcdController_StopCapture(d->Ctrl);
    d->State = CCD_READING;
    Ccd_FireHandler(d);
}

/*****************************************************************************/
/**
* @brief  Frame send complete (CcdController tx_done callback).
*
* Frame sending is fully orthogonal to the capture state machine (TxActive
* flag): this handler never touches CcdState. It only:
*   - paces a multi-frame fetch (trigger the next send while frames remain)
*   - resumes a cache-full-paused capture once the host drained a frame
*   - clears TxActive when the fetch finishes
*
* @param  d  Ccd instance.
******************************************************************************/
static void Ccd_OnTxDone(Ccd *d)
{
    if (d->FetchPending > 0U) {
        d->FetchPending--;
        if (d->FetchPending > 0U) {
            CcdController_TriggerFrameSend(d->Ctrl);
            return;
        }
    }

    /* 缓存满暂停期间, 主机 fetch 排空一帧 → 恢复采集 (无轮询) */
    if (d->RdWaiting &&
        CcdController_GetFrameNum(d->Ctrl) < (u32)CCD_MAX_FRAMES) {
        d->RdWaiting = 0U;
        Ccd_StartExposure(d);
    }

    /* 本次 fetch 全部发送完毕: 正交发送状态结束 (采集状态机不受影响) */
    d->TxActive = 0U;
}

/*****************************************************************************/
/**
* @brief  One frame fully written to DDR (FRAME_WRITTEN interrupt): readout done.
*
*   - single: capture finishes here (READING -> IDLE); the frame stays in the
*     cache waiting for the host's fetch
*   - burst: decrement BurstRemain; 0 -> all frames captured, back to IDLE
*   - cache full (CCD_MAX_FRAMES): pause (RdWaiting=1), resumed by TX_DONE
*     when the host drains frames via fetch (no frame is dropped)
*   - otherwise start the next exposure immediately
*
* @param  d  Ccd instance.
******************************************************************************/
static void Ccd_OnFrameReady(Ccd *d)
{
    if (d->Mode == CCD_MODE_SINGLE) {
        /* single: 帧写入完成即采集流程结束, 帧留在缓存中等主机 fetch */
        d->State = CCD_IDLE;
        Ccd_FireHandler(d);
        return;
    }

    if (d->BurstRemain > 0U) {
        d->BurstRemain--;
        if (d->BurstRemain == 0U) {
            /* burst: 目标帧数已全部采入缓存 */
            d->RdWaiting = 0U;
            d->State = CCD_IDLE;
            Ccd_FireHandler(d);
            return;
        }
    }

    /* 缓存满: 暂停采集, 等主机 fetch 排空 (TX_DONE 恢复), 不丢帧 */
    if (CcdController_GetFrameNum(d->Ctrl) >= (u32)CCD_MAX_FRAMES) {
        d->RdWaiting = 1U;
        return;
    }

    d->RdWaiting = 0U;
    Ccd_StartExposure(d);
}

/*****************************************************************************/
/**
* @brief  CcdController interrupt callback (frame_written / tx_done / exception).
*
* @param  IntrMask  Combination of CCDC_INTR_*.
* @param  ref       Ccd instance pointer.
******************************************************************************/
static void Ccd_CtrlHandler(u32 IntrMask, void *ref)
{
    Ccd *d = (Ccd *)ref;

    if (IntrMask & CCDC_INTR_FRAME_WRITTEN) {
        Ccd_OnFrameReady(d);
    }
    if (IntrMask & CCDC_INTR_TX_DONE) {
        Ccd_OnTxDone(d);
    }
    if (IntrMask & CCDC_INTR_EXCEPTION) {
        /* Frame exception: abort the capture loop back to IDLE to avoid
         * getting stuck in READING (a dropped frame would never raise the
         * FRAME_WRITTEN interrupt that the capture loop waits on).
         * Applies to all active modes (single/live/burst). */
        Ccd_Stop(d);
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
    d->FetchPending = 0U;
    d->BurstRemain = 0U;
    d->TxActive = 0U;
    d->RdWaiting = 0U;
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
* @brief  Starts capture: single (1 frame), live (continuous) or burst (n frames).
*         Modes are encoded in the frame count: n==0 -> live, n==1 -> single,
*         n>1 -> burst(n). All three take an explicit exposure duration.
*
* @param  d            Ccd instance.
* @param  n            Frame count: 0 = live, 1 = single, >1 = burst(n).
* @param  exposure_us  Exposure duration in microseconds.
*
* @return XST_SUCCESS / XST_DEVICE_BUSY (already capturing) /
*         XST_FAILURE (n>=1 but the cache cannot hold avail+n frames).
******************************************************************************/
int Ccd_Start(Ccd *d, u32 n, u64 exposure_us)
{
    u32 avail;
    int st;

    if (d->State != CCD_IDLE) {
        return XST_DEVICE_BUSY;
    }

    /* 容量校验: 有限采集 (n>=1, 含 single) 要求 avail+n 放得下, 否则硬件会丢帧 */
    if (n >= 1U) {
        avail = CcdController_GetFrameNum(d->Ctrl);
        if (avail + n > (u32)CCD_MAX_FRAMES) {
            return XST_FAILURE;
        }
    }

    d->Mode = (n == 0U) ? CCD_MODE_LIVE :
              (n == 1U) ? CCD_MODE_SINGLE : CCD_MODE_BURST;
    d->ExposureUs = exposure_us;
    d->BurstRemain = n;
    d->RdWaiting = 0U;

    st = Ccd_StartExposure(d);
    if (st != XST_SUCCESS) {
        d->Mode = CCD_MODE_SINGLE;   /* roll back on failure */
        d->BurstRemain = 0U;
    }
    return st;
}

/*****************************************************************************/
/**
* @brief  Sends n cached frames to FX2. The first trigger is issued here; the
* remaining ones are paced by the TX_DONE interrupt (a hardware trigger issued
* while a frame is still transmitting is dropped).
*
* @param  d  Ccd instance.
* @param  n  Number of frames to send (>= 1, <= current frame count).
*
* @return XST_SUCCESS / XST_DEVICE_BUSY (a fetch is already in progress) /
*         XST_FAILURE (not enough frames cached).
******************************************************************************/
int Ccd_StartFetch(Ccd *d, u32 n)
{
    u32 avail;

    if (d->FetchPending > 0U) {
        return XST_DEVICE_BUSY;
    }
    if (n == 0U) {
        return XST_FAILURE;
    }
    avail = CcdController_GetFrameNum(d->Ctrl);
    if (avail < n) {
        return XST_FAILURE;   /* 缓存不足 */
    }

    d->FetchPending = n;
    d->TxActive = 1U;   /* 发送状态: 可与采集 (EXPOSING/READING) 共存 */
    CcdController_TriggerFrameSend(d->Ctrl);
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Stops: aborts exposure/readout and any pending fetch/burst, returns to
* IDLE and notifies.
*
* @param  d  Ccd instance.
******************************************************************************/
void Ccd_Stop(Ccd *d)
{
    CcdController_StopCapture(d->Ctrl);
    XTmrCtr_Stop(d->Tmr1, 0U);
    d->FetchPending = 0U;
    d->BurstRemain = 0U;
    d->TxActive = 0U;
    d->RdWaiting = 0U;
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
* @brief  Sets the readout mode: stops capture, writes CTRL[4:3], then soft-resets
* the whole pipeline (frame cache flushed, fixed frame length re-locked).
*
* Wrapping CcdController_SetReadMode + CcdController_SoftReset so the protocol
* layer never touches CcdController directly.
*
* @param  d     Ccd instance.
* @param  mode  CCD_READ_MODE_LINE_BINNING or CCD_READ_MODE_IMAGE.
******************************************************************************/
void Ccd_SetReadMode(Ccd *d, u8 mode)
{
    Ccd_Stop(d);                             /* 停止采集/发送并同步清理软件状态 */
    CcdController_SetReadMode(d->Ctrl, mode);
    CcdController_SoftReset(d->Ctrl);        /* 重锁帧长并清空帧缓存 */
}

/*****************************************************************************/
/**
* @brief  Sets the image size: stops capture, writes IMG_SIZE, then soft-resets
* the whole pipeline (frame cache flushed, fixed frame length re-locked).
*
* @param  d  Ccd instance.
* @param  w  Image width in pixels.
* @param  h  Image height in pixels.
******************************************************************************/
void Ccd_SetImageSize(Ccd *d, u16 w, u16 h)
{
    Ccd_Stop(d);
    CcdController_SetImageSize(d->Ctrl, w, h);
    CcdController_SoftReset(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  Writes the bevel/blank edges (BEVEL_BLANK). No stop/reset needed
* (bevels do not change the fixed frame length).
*
* @param  d   Ccd instance.
* @param  bb  Bevel/blank values; NULL is ignored.
******************************************************************************/
void Ccd_SetBevelBlank(Ccd *d, const Ccd_BevelBlank *bb)
{
    if (bb != NULL) {
        CcdController_SetBevelBlank(d->Ctrl, bb);
    }
}

/*****************************************************************************/
/**
* @brief  Sets the SCLK frequency (CTRL[1]).
*
* @param  d     Ccd instance.
* @param  freq  CCD_FREQ_100K or CCD_FREQ_500K.
******************************************************************************/
void Ccd_SetFreqSel(Ccd *d, u8 freq)
{
    CcdController_SetFreqSel(d->Ctrl, freq);
    CcdController_SoftReset(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  Enables/disables mock mode (CTRL[2]).
*
* @param  d     Ccd instance.
* @param  mock  0 = real ADC data, 1 = mock virtual pixels.
******************************************************************************/
void Ccd_SetMockMode(Ccd *d, u8 mock)
{
    CcdController_SetMockMode(d->Ctrl, mock);
}

/*****************************************************************************/
/**
* @brief  Sets the CDSCLK fine-tune delay (CTRL[11:5]).
*
* @param  d      Ccd instance.
* @param  delay  Fine delay taps, 0..127.
******************************************************************************/
void Ccd_SetCdsclkDelay(Ccd *d, u8 delay)
{
    CcdController_SetCdsclkDelay(d->Ctrl, delay);
}

/*****************************************************************************/
/**
* @brief  Soft-resets the whole CCD pipeline (writes CTRL[12]=1).
*
* @param  d  Ccd instance.
******************************************************************************/
void Ccd_SoftReset(Ccd *d)
{
    CcdController_SoftReset(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  Number of readable frames in the frame buffer.
*
* @param  d  Ccd instance.
*
* @return Frame count (forwarded from CcdController_GetFrameNum).
******************************************************************************/
u32 Ccd_GetFrameNum(Ccd *d)
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
* @return Current CcdMode (SINGLE/LIVE/BURST, derived from the n of Ccd_Start).
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
