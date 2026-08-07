/******************************************************************************
* @file ccd.h
*
* CCD exposure control + frame path driver: combines CcdController (frame readout /
* buffering / send) with timer1 64-bit cascade mode (exposure duration timing).
* Single / live / burst capture modes; frame sending (fetch) is orthogonal to the
* capture state machine and can overlap with exposing/reading.
*
* @note <pre>
* MODIFICATION HISTORY:
*
 * Ver   Who  Date     Changes
 * ----- ---- -------- -----------------------------------------------
 * 1.0   wwc  26/08/02 First release
 * 1.1   wwc  26/08/07 新增 burst 模式与 acq fetch 逐帧发送; live 不再自动发送
 *                     (帧发送由主机 fetch 命令驱动)
 * 1.2   wwc  26/08/07 采集环推进改由 FRAME_WRITTEN 中断驱动 (替代 Ccd_Tick 轮询)
 * 1.3   wwc  26/08/07 CCD_TX 从互斥状态机拆出: 帧发送 (TxActive) 为与采集状态
 *                     正交的独立维度, 可与 EXPOSING/READING 共存
 * 1.4   wwc  26/08/07 single 收尾改由 FRAME_WRITTEN (帧写入完成) 驱动
 * 1.5   wwc  26/08/07 合并 Ccd_StartCapture/Ccd_StartBurst 为 Ccd_Start(d,n,us);
 *                     n=0->live, n=1->single, n>1->burst(n)
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
    CCD_MODE_SINGLE = 0,   /* single capture: expose -> readout -> IDLE (frame cached, sent by host fetch) */
    CCD_MODE_LIVE,         /* continuous capture into cache; host fetches anytime */
    CCD_MODE_BURST         /* capture N frames continuously into cache, then IDLE */
} CcdMode;   /* 由 Ccd_Start 的 n 推导: n==0->LIVE, n==1->SINGLE, n>1->BURST */

typedef enum {
    CCD_IDLE = 0,
    CCD_EXPOSING,
    CCD_READING
} CcdState;   /* 互斥采集状态机: 帧发送 (TxActive) 是正交维度, 可与任一状态共存 */

/* State change callback */
typedef void (*CcdHandler)(CcdState st, void *ref);

typedef struct {
    CcdController *Ctrl;
    XTmrCtr *Tmr1;
    u32 IntrVecId;
    CcdMode Mode;
    CcdState State;
    u64 ExposureUs;           /* current exposure duration (us) */
    u32 FetchPending;         /* fetch: frames remaining to send (incl. the one in TX), 0 = none */
    u32 BurstRemain;          /* frames still to capture (Ccd_Start 的 n); 0 = live (连续) 或未启动 */
    u8  TxActive;             /* 1 = frame send in progress (orthogonal to the capture FSM) */
    u8  RdWaiting;            /* 1 = live/burst paused at full cache, waiting for host drain */
    CcdHandler Handler;
    void *HandlerRef;
} Ccd;

int  Ccd_Init(Ccd *d, CcdController *ctrl, XTmrCtr *tmr1, u32 IntrVecId);
int  Ccd_Start(Ccd *d, u32 n, u64 exposure_us);  /* n=0 live, 1 single, >1 burst(n) */
int  Ccd_StartFetch(Ccd *d, u32 n);       /* send n cached frames to FX2 (paced by TX_DONE) */
void Ccd_Stop(Ccd *d);              /* stop: abort exposure/fetch/burst, return to IDLE */
void Ccd_Abort(Ccd *d);             /* clear exposure=0 to abort the current exposure */
void Ccd_TriggerSend(Ccd *d);       /* manually trigger frame send to FX2 */
u32  Ccd_GetFrameNum(Ccd *d);
u8   Ccd_IsDdrReady(Ccd *d);
u8   Ccd_GetException(Ccd *d);
u32  Ccd_GetExceptionCnt(Ccd *d);
CcdMode Ccd_GetMode(Ccd *d);
void Ccd_RegisterHandler(Ccd *d, CcdHandler hdl, void *ref);

#ifdef __cplusplus
}
#endif

#endif /* CCD_H */
