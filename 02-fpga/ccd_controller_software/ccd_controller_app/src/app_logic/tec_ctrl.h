/******************************************************************************
* @file tec_ctrl.h
*
* TEC temperature PID control loop (app logic layer). When enabled, on each fresh
* CCD sensor NTC sample (~32ms from the monitor channel rotation) the loop
* computes a PID output and commands the dac8311 so the sensor temperature is
* held at SetTemp.
*
*   err = sensor_temp - SetTemp    (positive => sensor too hot => cool)
*   Vtec = Pid_Update(sensor_temp, dt)    clamped to +/- VDD (+/-3.3V)
*   Vcont = 1.25 - Vtec / 5  ->  Dac8311_SetVoltage
*
* The adn8833 EN pin is driven together with the DAC: enabling the TEC control
* powers on the ADN8833, disabling powers it off and parks the DAC at Vtec = 0
* (Vcont = 1.25).
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
#ifndef TEC_CTRL_H
#define TEC_CTRL_H

#include "xil_types.h"
#include "../app_drivers/dac8311.h"
#include "../app_drivers/adn8833.h"
#include "../app_logic/monitor.h"
#include "../app_logic/pid.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    Dac8311 *Dac;           /* dac8311 driver (initialized by board_hal) */
    Adn8833 *Adn;           /* adn8833 driver (EN pin, initialized by board_hal) */
    Monitor *Mon;           /* monitor (initialized before this) */
    Pid     Pid;            /* PID state */
    float   SetTemp;        /* sensor temperature setpoint (degC) */
    u8      Enabled;        /* tec_enable state */
    u8      FirstRun;       /* 1 until the first fresh sample after enable */
    float   Vtec;           /* last commanded TEC voltage (V) */
    u32     LastSampleTick; /* heartbeat tick of the last PID update */
} TecCtrl;

extern TecCtrl gTecCtrl;

int   TecCtrl_Init(TecCtrl *d, Dac8311 *dac, Adn8833 *adn, Monitor *mon);
void  TecCtrl_SetEnable(TecCtrl *d, u8 on);
void  TecCtrl_SetSetTemp(TecCtrl *d, float degc);
void  TecCtrl_SetTunings(TecCtrl *d, float kp, float ki, float kd);
float TecCtrl_GetVtec(TecCtrl *d);
void  TecCtrl_Tick(TecCtrl *d);   /* called from the main loop */

#ifdef __cplusplus
}
#endif

#endif /* TEC_CTRL_H */
