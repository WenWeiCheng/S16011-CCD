/******************************************************************************
* @file tec_ctrl.c
*
* TEC temperature PID control loop implementation. See tec_ctrl.h for the
* control chain.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/04 First release
* 1.1   wwc  26/08/04 SetEnable also drives the adn8833 EN pin (Init takes Adn8833*)
* </pre>
******************************************************************************/
#include "tec_ctrl.h"
#include "tec.h"
#include "../include/board_config.h"
#include "xstatus.h"
#include "xil_assert.h"
#include "../devices/adn8833.h"

TecCtrl gTecCtrl;

/*****************************************************************************/
/**
* @brief  Initializes the TEC control loop: stores the dependencies and resets
* the PID with the Vtec output clamp range.
*
* @param  dac  dac8311 driver instance (initialized by board_hal).
* @param  adn  adn8833 driver instance (initialized by board_hal).
* @param  mon  Monitor instance (initialized before this).
*
* @return XST_SUCCESS.
******************************************************************************/
int TecCtrl_Init(TecCtrl *d, Dac8311 *dac, Adn8833 *adn, Monitor *mon)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(dac != NULL);
    Xil_AssertNonvoid(adn != NULL);
    Xil_AssertNonvoid(mon != NULL);

    d->Dac = dac;
    d->Adn = adn;
    d->Mon = mon;
    d->SetTemp = 0.0f;
    d->Enabled = 0U;
    d->FirstRun = 1U;
    d->Vtec = 0.0f;
    d->LastSampleTick = 0U;

    Pid_Init(&d->Pid, 0.0f, 0.0f, 0.0f,
             TEC_CTRL_VTEC_MIN_V, TEC_CTRL_VTEC_MAX_V);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Enables/disables the TEC control loop.
*
* The ADN8833 EN pin is driven together with the DAC: 1 powers on the TEC, 0
* powers it off. On any state change the PID is reset, the DAC is parked at
* Vtec = 0 (Vcont = 1.25), and the next fresh sensor sample only re-arms the
* loop (no control step with a bogus large dt).
*
* @param  d   TEC control instance.
* @param  on  1 = power on + run the loop, 0 = power off + park.
******************************************************************************/
void TecCtrl_SetEnable(TecCtrl *d, u8 on)
{
    Xil_AssertVoid(d != NULL);

    d->Enabled = on ? 1U : 0U;
    Adn8833_SetEnable(d->Adn, d->Enabled);
    Pid_Reset(&d->Pid);
    d->Vtec = 0.0f;
    d->LastSampleTick = 0U;
    d->FirstRun = 1U;

    /* Park the DAC at Vtec = 0 (Vcont = 1.25) on any state change */
    (void)Dac8311_SetVoltage(d->Dac, Tec_VtecToVcont(0.0f));
}

/*****************************************************************************/
/**
* @brief  Sets the sensor temperature setpoint (degC).
*
* @param  d     TEC control instance.
* @param  degc  Target temperature in degC.
******************************************************************************/
void TecCtrl_SetSetTemp(TecCtrl *d, float degc)
{
    Xil_AssertVoid(d != NULL);

    d->SetTemp = degc;
    Pid_SetSetpoint(&d->Pid, degc);
}

/*****************************************************************************/
/**
* @brief  Sets the PID gains (running state is preserved).
*
* @param  d   TEC control instance.
* @param  kp  Proportional gain (V/degC).
* @param  ki  Integral gain (1/s).
* @param  kd  Derivative gain (s).
******************************************************************************/
void TecCtrl_SetTunings(TecCtrl *d, float kp, float ki, float kd)
{
    Xil_AssertVoid(d != NULL);

    Pid_SetTunings(&d->Pid, kp, ki, kd);
}

/*****************************************************************************/
/**
* @brief  Returns the last commanded TEC voltage (V).
*
* @param  d  TEC control instance.
*
* @return Last Vtec output (V).
******************************************************************************/
float TecCtrl_GetVtec(TecCtrl *d)
{
    return d->Vtec;
}

/*****************************************************************************/
/**
* @brief  Main loop tick: runs one PID step per fresh sensor sample.
*
* Only acts while enabled. When a new sensor NTC sample is available (its
* channel sample tick advanced, ~every 32ms), computes the real dt from the
* heartbeat ticks and drives the DAC. The first fresh sample after enable only
* re-arms the loop so the first dt is a normal ~32ms interval.
*
* @param  d  TEC control instance.
******************************************************************************/
void TecCtrl_Tick(TecCtrl *d)
{
    u32 tick;
    float dt;

    Xil_AssertVoid(d != NULL);

    if (!d->Enabled) {
        return;
    }

    tick = Monitor_GetSampleTick(d->Mon, ADS1118_MUX_SENSOR_NTC);
    if (tick == d->LastSampleTick) {
        return;   /* no fresh sensor sample yet */
    }

    if (d->FirstRun) {
        d->LastSampleTick = tick;
        d->FirstRun = 0U;
        return;
    }

    dt = (float)(tick - d->LastSampleTick) / 1000.0f;   /* heartbeat in ms -> s */
    d->LastSampleTick = tick;
    if (dt <= 0.0f) {
        return;
    }

    d->Vtec = Pid_Update(&d->Pid,
                         Monitor_GetNtcTemp(d->Mon, ADS1118_MUX_SENSOR_NTC),
                         dt);
    (void)Dac8311_SetVoltage(d->Dac, Tec_VtecToVcont(d->Vtec));
}
