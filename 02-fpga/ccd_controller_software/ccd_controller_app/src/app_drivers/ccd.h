/******************************************************************************
* @file ccd.h
*
* CCD 曝光控制 + 帧通路驱动：组合 CcdController（帧读出/缓存/发送）与
* timer1 64-bit 级联模式（曝光时长计时）。区分 single 与 live 两种模式。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
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
    CCD_MODE_SINGLE = 0,   /* 单次采集：曝光→读出→发送，完成回 IDLE */
    CCD_MODE_LIVE          /* 连续采集：驱动内自动重启曝光+触发发送 */
} CcdMode;

typedef enum {
    CCD_IDLE = 0,
    CCD_EXPOSING,
    CCD_READING,
    CCD_TX
} CcdState;

/* 状态变化回调 */
typedef void (*CcdHandler)(CcdState st, void *ref);

typedef struct {
    CcdController *Ctrl;
    XTmrCtr *Tmr1;
    u32 IntrVecId;
    CcdMode Mode;
    CcdState State;
    u64 ExposureUs;           /* 当前曝光时长（µs） */
    CcdHandler Handler;
    void *HandlerRef;
} Ccd;

int  Ccd_Init(Ccd *d, CcdController *ctrl, XTmrCtr *tmr1, u32 IntrVecId);
int  Ccd_StartCapture(Ccd *d, CcdMode mode, u64 exposure_us);
void Ccd_Stop(Ccd *d);              /* 停止：中止曝光，回 IDLE */
void Ccd_Abort(Ccd *d);             /* 清 exposure=0 中止当前曝光 */
void Ccd_TriggerSend(Ccd *d);       /* 手动触发帧发送到 FX2 */
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
