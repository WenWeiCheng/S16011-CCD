/******************************************************************************
* @file heartbeat.h
*
* 系统心跳：基于 timer0 的 1ms 心跳源，供按键消抖、LED 闪烁、
* 遥测采样节拍等周期任务使用。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef HEARTBEAT_H
#define HEARTBEAT_H

#include "xil_types.h"
#include "xstatus.h"
#include "xtmrctr.h"

#ifdef __cplusplus
extern "C" {
#endif

#define HEARTBEAT_MAX_HANDLERS   4U   /* 内部最多注册的周期任务数 */

/* 每 1ms 回调 */
typedef void (*HeartbeatHandler)(void *ref);

typedef struct {
    XTmrCtr *Tmr;
    u32 IntrVecId;
    volatile u32 Tick;                    /* 上电以来 tick 数（ms） */
    HeartbeatHandler Handlers[HEARTBEAT_MAX_HANDLERS];
    void *HandlerRefs[HEARTBEAT_MAX_HANDLERS];
    u8 NumHandlers;
} Heartbeat;

int  Heartbeat_Init(Heartbeat *d, XTmrCtr *tmr, u32 IntrVecId);
void Heartbeat_RegisterHandler(Heartbeat *d, HeartbeatHandler hdl, void *ref);
u32  Heartbeat_GetTick(Heartbeat *d);

/*
 * timer0 的 XTmrCtr 回调（经 XTmrCtr_SetHandler 注册；XTmrCtr_InterruptHandler
 * 负责挂 INTC）。签名固定为 XTmrCtr_Handler 的 (ref, TmrCtrNumber)。
 */
void Heartbeat_InterruptHandler(void *ref, u8 TmrCtrNumber);

#ifdef __cplusplus
}
#endif

#endif /* HEARTBEAT_H */
