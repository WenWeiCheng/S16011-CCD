/******************************************************************************
* @file heartbeat.h
*
* System heartbeat: a 1ms heartbeat source based on timer0, used by periodic tasks such
* as key debounce, LED blink, and the telemetry sampling tick.
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

#define HEARTBEAT_MAX_HANDLERS   4U   /* max number of periodic tasks that can be registered */

/* Called every 1ms */
typedef void (*HeartbeatHandler)(void *ref);

typedef struct {
    XTmrCtr *Tmr;
    u32 IntrVecId;
    volatile u32 Tick;                    /* tick count since power-up (ms) */
    HeartbeatHandler Handlers[HEARTBEAT_MAX_HANDLERS];
    void *HandlerRefs[HEARTBEAT_MAX_HANDLERS];
    u8 NumHandlers;
} Heartbeat;

int  Heartbeat_Init(Heartbeat *d, XTmrCtr *tmr, u32 IntrVecId);
void Heartbeat_RegisterHandler(Heartbeat *d, HeartbeatHandler hdl, void *ref);
u32  Heartbeat_GetTick(Heartbeat *d);

/*
 * XTmrCtr callback of timer0 (registered via XTmrCtr_SetHandler; XTmrCtr_InterruptHandler
 * hooks it to the INTC). Signature fixed as XTmrCtr_Handler's (ref, TmrCtrNumber).
 */
void Heartbeat_InterruptHandler(void *ref, u8 TmrCtrNumber);

#ifdef __cplusplus
}
#endif

#endif /* HEARTBEAT_H */
