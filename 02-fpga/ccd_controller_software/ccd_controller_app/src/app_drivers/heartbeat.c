/******************************************************************************
* @file heartbeat.c
*
* 系统心跳实现：timer0 配为 auto-reload 周期计数，周期 1ms。
* 中断链：INTC vec1 → XTmrCtr_InterruptHandler → Heartbeat_InterruptHandler。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "heartbeat.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/* 1ms 周期对应的 32-bit 递增计数初值（100MHz） */
#define HEARTBEAT_RESET_VALUE \
    (u32)(0xFFFFFFFFUL - (BOARD_CLK_FREQ_HZ / 1000UL - 1UL))

/*****************************************************************************/
/**
* @brief  初始化心跳。
*
* timer 实例由 board_hal 预先初始化（XTmrCtr_Initialize），本函数只配置
* counter0 为 1ms auto-reload 并注册 handler，随后启动。
*
* @param  d          心跳实例。
* @param  tmr        timer0 的 XTmrCtr 实例。
* @param  IntrVecId  INTC 向量号（备用，当前未直接使用）。
*
* @return XST_SUCCESS。
******************************************************************************/
int Heartbeat_Init(Heartbeat *d, XTmrCtr *tmr, u32 IntrVecId)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(tmr != NULL);

    d->Tmr = tmr;
    d->IntrVecId = IntrVecId;
    d->Tick = 0U;
    d->NumHandlers = 0U;

    XTmrCtr_SetResetValue(tmr, 0U, HEARTBEAT_RESET_VALUE);
    XTmrCtr_SetOptions(tmr, 0U,
                       XTC_INT_MODE_OPTION | XTC_AUTO_RELOAD_OPTION);
    XTmrCtr_SetHandler(tmr, Heartbeat_InterruptHandler, d);
    XTmrCtr_Reset(tmr, 0U);
    XTmrCtr_Start(tmr, 0U);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  注册 1ms 周期回调（内部最多 HEARTBEAT_MAX_HANDLERS 个）。
******************************************************************************/
void Heartbeat_RegisterHandler(Heartbeat *d, HeartbeatHandler hdl, void *ref)
{
    if (d->NumHandlers >= HEARTBEAT_MAX_HANDLERS) {
        return;
    }
    d->Handlers[d->NumHandlers] = hdl;
    d->HandlerRefs[d->NumHandlers] = ref;
    d->NumHandlers++;
}

/*****************************************************************************/
/**
* @brief  返回上电以来 tick 数（毫秒）。
******************************************************************************/
u32 Heartbeat_GetTick(Heartbeat *d)
{
    return d->Tick;
}

/*****************************************************************************/
/**
* @brief  timer0 的 XTmrCtr 回调（中断上下文）。
*
* tick 自增并依次调用已注册 handler，只做最小处理。
*
* @param ref            Heartbeat 实例。
* @param TmrCtrNumber   触发的 counter 号（应为 0）。
******************************************************************************/
void Heartbeat_InterruptHandler(void *ref, u8 TmrCtrNumber)
{
    Heartbeat *d = (Heartbeat *)ref;
    u8 i;

    if (XTmrCtr_IsExpired(d->Tmr, TmrCtrNumber)) {
        d->Tick++;
        for (i = 0; i < d->NumHandlers; i++) {
            d->Handlers[i](d->HandlerRefs[i]);
        }
    }
}
