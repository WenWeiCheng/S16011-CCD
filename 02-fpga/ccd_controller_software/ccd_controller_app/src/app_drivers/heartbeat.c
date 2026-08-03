/******************************************************************************
* @file heartbeat.c
*
* System heartbeat implementation: timer0 configured as an auto-reload periodic counter,
* period 1ms.
* Interrupt chain: INTC vec1 -> XTmrCtr_InterruptHandler -> Heartbeat_InterruptHandler.
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
#include "heartbeat.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/* 32-bit up-count reset value for a 1ms period (100MHz) */
#define HEARTBEAT_RESET_VALUE \
    (u32)(0xFFFFFFFFUL - (BOARD_CLK_FREQ_HZ / 1000UL - 1UL))

/*****************************************************************************/
/**
* @brief  Initializes the heartbeat.
*
* The timer instance is pre-initialized by board_hal (XTmrCtr_Initialize); this function
* only configures counter0 as a 1ms auto-reload and registers the handler, then starts it.
*
* @param  d          Heartbeat instance.
* @param  tmr        XTmrCtr instance of timer0.
* @param  IntrVecId  INTC vector number (reserved, not directly used currently).
*
* @return XST_SUCCESS.
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
* @brief  Registers a 1ms periodic callback (up to HEARTBEAT_MAX_HANDLERS internally).
*
* @param  d    Heartbeat instance.
* @param  hdl  Callback invoked once per millisecond; NULL disables.
* @param  ref  Opaque reference passed back to the callback.
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
* @brief  Returns the tick count since power-up (milliseconds).
******************************************************************************/
u32 Heartbeat_GetTick(Heartbeat *d)
{
    return d->Tick;
}

/*****************************************************************************/
/**
* @brief  XTmrCtr callback of timer0 (interrupt context).
*
* Increments the tick and calls each registered handler in turn, doing minimal
* processing only.
*
* @param ref            Heartbeat instance.
* @param TmrCtrNumber   Number of the counter that triggered (should be 0).
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
