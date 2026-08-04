/******************************************************************************
* @file pid.c
*
* Generic PID controller implementation (pure logic). See pid.h for the
* conventions.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/04 First release
* </pre>
******************************************************************************/
#include "pid.h"

/*****************************************************************************/
/**
* @brief  Initializes the PID state with the given gains and output clamp range.
*
* @param  p     PID instance.
* @param  kp    Proportional gain.
* @param  ki    Integral gain (1/s).
* @param  kd    Derivative gain (s).
* @param  omin  Output clamp low.
* @param  omax  Output clamp high.
******************************************************************************/
void Pid_Init(Pid *p, float kp, float ki, float kd, float omin, float omax)
{
    p->Kp = kp;
    p->Ki = ki;
    p->Kd = kd;
    p->SetPoint = 0.0f;
    p->OutMin = omin;
    p->OutMax = omax;
    p->IntAcc = 0.0f;
    p->PrevMeas = 0.0f;
    p->Init = 0U;
}

/*****************************************************************************/
/**
* @brief  Updates the PID gains (running state is preserved).
*
* @param  p   PID instance.
* @param  kp  Proportional gain.
* @param  ki  Integral gain (1/s).
* @param  kd  Derivative gain (s).
******************************************************************************/
void Pid_SetTunings(Pid *p, float kp, float ki, float kd)
{
    p->Kp = kp;
    p->Ki = ki;
    p->Kd = kd;
}

/*****************************************************************************/
/**
* @brief  Sets the control setpoint.
*
* @param  p   PID instance.
* @param  sp  Target value.
******************************************************************************/
void Pid_SetSetpoint(Pid *p, float sp)
{
    p->SetPoint = sp;
}

/*****************************************************************************/
/**
* @brief  Resets the integral accumulator and the derivative history.
*
* @param  p  PID instance.
******************************************************************************/
void Pid_Reset(Pid *p)
{
    p->IntAcc = 0.0f;
    p->PrevMeas = 0.0f;
    p->Init = 0U;
}

/*****************************************************************************/
/**
* @brief  Runs one control step and returns the clamped output.
*
* err = measurement - SetPoint. The integral term accumulates Ki*err*dt with
* conditional anti-windup: while the output is clamped and the error would push
* the integral further into saturation, the accumulator is left unchanged. The
* derivative term uses the measurement slope (no setpoint kick); the first call
* after Init/Reset has no derivative term.
*
* @param  p     PID instance.
* @param  measurement  Current measurement.
* @param  dt    Time since the previous update (s); must be > 0.
*
* @return Clamped controller output.
******************************************************************************/
float Pid_Update(Pid *p, float measurement, float dt)
{
    float err, pterm, iterm, dterm, out;

    err = measurement - p->SetPoint;

    pterm = p->Kp * err;

    iterm = p->IntAcc + p->Ki * err * dt;

    if (p->Init == 0U) {
        dterm = 0.0f;   /* no derivative on the first sample */
    } else {
        dterm = (dt > 0.0f) ? p->Kd * (measurement - p->PrevMeas) / dt : 0.0f;
    }
    p->PrevMeas = measurement;
    p->Init = 1U;

    out = pterm + iterm + dterm;

    if (out > p->OutMax) {
        out = p->OutMax;
        if (err <= 0.0f) {
            p->IntAcc = iterm;   /* not winding up: error moves the integral away */
        }
    } else if (out < p->OutMin) {
        out = p->OutMin;
        if (err >= 0.0f) {
            p->IntAcc = iterm;
        }
    } else {
        p->IntAcc = iterm;
    }

    return out;
}
