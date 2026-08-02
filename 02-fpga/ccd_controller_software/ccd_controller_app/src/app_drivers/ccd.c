/******************************************************************************
* @file ccd.c
*
* CCD 曝光控制 + 帧通路驱动实现。
*
* 状态机（single）：IDLE → EXPOSING → READING → TX → IDLE
* 状态机（live） ：IDLE → EXPOSING → READING → TX → EXPOSING → ... → IDLE
*
* - 曝光计时：timer1 64-bit 级联（XTC_CASCADE_MODE_OPTION），中断只在 counter0。
* - 曝光到期 ISR：CcdController_StopCapture（exposure=0 下降沿启动读出）。
* - live 模式：曝光到期后自动 TriggerSend；tx_done 后自动重启曝光。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "ccd.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/*****************************************************************************/
/**
* @brief  回调 app 状态变化。
******************************************************************************/
static void Ccd_FireHandler(Ccd *d)
{
    if (d->Handler != NULL) {
        d->Handler(d->State, d->HandlerRef);
    }
}

/*****************************************************************************/
/**
* @brief  启动曝光计时（timer1 64-bit 级联，一次性）。
*
* counts = exposure_us × (时钟MHz)；reset64 = 2^64 − counts；
* counter1 = 高 32 位，counter0 = 低 32 位（级联时 counter0 中断有效）。
******************************************************************************/
static void Ccd_StartExposureTimer(Ccd *d)
{
    u64 counts = d->ExposureUs * (u64)(BOARD_CLK_FREQ_HZ / 1000000UL);
    u64 reset = (u64)0xFFFFFFFFFFFFFFFFULL - counts + 1ULL;

    XTmrCtr_SetResetValue(d->Tmr1, 1U, (u32)(reset >> 32));   /* 高 32 */
    XTmrCtr_SetResetValue(d->Tmr1, 0U, (u32)(reset & 0xFFFFFFFFU)); /* 低 32 */
    XTmrCtr_Reset(d->Tmr1, 1U);
    XTmrCtr_Reset(d->Tmr1, 0U);
    XTmrCtr_Start(d->Tmr1, 0U);
}

/*****************************************************************************/
/**
* @brief  启动曝光：置 exposure=1 + 启动计时，进入 EXPOSING。
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
* @brief  曝光到期（timer1 ISR 内）：exposure=0 启动读出，进入 READING。
*         live 模式随后自动触发帧发送。
******************************************************************************/
static void Ccd_OnExposureDone(Ccd *d)
{
    CcdController_StopCapture(d->Ctrl);
    d->State = CCD_READING;
    Ccd_FireHandler(d);

    if (d->Mode == CCD_MODE_LIVE) {
        Ccd_TriggerSend(d);   /* 曝光到期后触发帧发送 */
    }
}

/*****************************************************************************/
/**
* @brief  帧发送完成（CcdController tx_done 回调）：进入 TX。
*         live 模式自动重启曝光；single 模式回 IDLE。
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
* @brief  CcdController 中断回调（tx_done / exception）。
******************************************************************************/
static void Ccd_CtrlHandler(u32 IntrMask, void *ref)
{
    Ccd *d = (Ccd *)ref;

    if (IntrMask & CCDC_INTR_TX_DONE) {
        Ccd_OnTxDone(d);
    }
    if (IntrMask & CCDC_INTR_EXCEPTION) {
        /* 帧异常：live 模式下中止循环回 IDLE，避免卡死在 READING */
        if (d->Mode == CCD_MODE_LIVE) {
            Ccd_Stop(d);
        }
    }
}

/*****************************************************************************/
/**
* @brief  timer1 的 XTmrCtr 回调（曝光到期）。
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
* @brief  初始化 ccd 驱动。
*
* @param  ctrl    CcdController 实例（board_hal 已初始化）。
* @param  tmr1    timer1 的 XTmrCtr 实例（board_hal 已初始化）。
* @param  IntrVecId timer1 的 INTC 向量号。
*
* @return XST_SUCCESS。
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

    /* timer1 64-bit 级联，中断只在 counter0；一次性（无 auto-reload） */
    XTmrCtr_SetOptions(tmr1, 0U,
                       XTC_INT_MODE_OPTION | XTC_CASCADE_MODE_OPTION);
    XTmrCtr_SetHandler(tmr1, Ccd_ExposureHandler, d);
    XTmrCtr_Reset(tmr1, 0U);
    XTmrCtr_Reset(tmr1, 1U);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  启动采集（single 或 live）。
*
* @return XST_SUCCESS / XST_DEVICE_BUSY（已在采集）/ 底层错误。
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
* @brief  停止：中止曝光/读出，回 IDLE 并通知。
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
* @brief  中止当前曝光：仅清 exposure=0，不改变状态/不通知。
******************************************************************************/
void Ccd_Abort(Ccd *d)
{
    CcdController_StopCapture(d->Ctrl);
    XTmrCtr_Stop(d->Tmr1, 0U);
}

/*****************************************************************************/
/**
* @brief  手动触发帧发送到 FX2（仅当 DDR3 就绪且帧缓存有帧）。
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
* @brief  帧缓存中可读帧数。
******************************************************************************/
u8 Ccd_GetFrameNum(Ccd *d)
{
    return CcdController_GetFrameNum(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  DDR3 是否就绪。
******************************************************************************/
u8 Ccd_IsDdrReady(Ccd *d)
{
    return CcdController_IsDdrReady(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  帧异常标志。
******************************************************************************/
u8 Ccd_GetException(Ccd *d)
{
    return CcdController_GetException(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  帧异常计数。
******************************************************************************/
u32 Ccd_GetExceptionCnt(Ccd *d)
{
    return CcdController_GetExceptionCnt(d->Ctrl);
}

/*****************************************************************************/
/**
* @brief  当前采集模式。
******************************************************************************/
CcdMode Ccd_GetMode(Ccd *d)
{
    return d->Mode;
}

/*****************************************************************************/
/**
* @brief  注册状态变化回调。
******************************************************************************/
void Ccd_RegisterHandler(Ccd *d, CcdHandler hdl, void *ref)
{
    d->Handler = hdl;
    d->HandlerRef = ref;
}
