/******************************************************************************
* @file pid.h
*
* Generic PID controller (pure logic, no hardware/Xilinx dependency,
* host-testable standalone).
*
* Convention:
*   err = measurement - SetPoint
*   out = Kp*err + Ki*IntAcc + Kd*(measurement - prev)/dt
* Output is clamped to [OutMin, OutMax]; the integral uses conditional
* anti-windup (it stops accumulating while the output is saturated and the
* error would drive further into the limit). The derivative acts on the
* measurement, so a setpoint change produces no derivative kick; the first
* update after a reset contributes no derivative term.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/04 First release
* </pre>
******************************************************************************/
#ifndef PID_H
#define PID_H

#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float Kp;        /* proportional gain */
    float Ki;        /* integral gain (1/s) */
    float Kd;        /* derivative gain (s) */
    float SetPoint;  /* target */
    float OutMin;    /* output clamp low */
    float OutMax;    /* output clamp high */
    float IntAcc;    /* clamped integral accumulator */
    float PrevMeas;  /* previous measurement (derivative-on-measurement) */
    u8    Init;      /* 1 after the first Pid_Update */
} Pid;

void  Pid_Init(Pid *p, float kp, float ki, float kd, float omin, float omax);
void  Pid_SetTunings(Pid *p, float kp, float ki, float kd);
void  Pid_SetSetpoint(Pid *p, float sp);
void  Pid_Reset(Pid *p);
float Pid_Update(Pid *p, float measurement, float dt);

#ifdef __cplusplus
}
#endif

#endif /* PID_H */
