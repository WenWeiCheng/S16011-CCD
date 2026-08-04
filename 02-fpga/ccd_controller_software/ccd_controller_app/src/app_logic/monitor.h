/******************************************************************************
* @file monitor.h
*
* Sampling/monitor loop: periodically samples the four ads1118 inputs (CCD sensor NTC,
* TEC voltage, TEC current, ambient NTC), caches the raw codes of each channel, and
* converts them to engineering values on demand.
* The protocol layer's RO parameters (sensor_temp / tec_voltage / tec_current etc.) get
* their values through this module.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/03 First release
* 1.3   wwc  26/08/04 Per-channel sample tick (Monitor_GetSampleTick) for the TEC loop
* </pre>
******************************************************************************/
#ifndef MONITOR_H
#define MONITOR_H

#include "xil_types.h"
#include "../app_drivers/ads1118.h"
#include "../app_drivers/heartbeat.h"

#ifdef __cplusplus
extern "C" {
#endif

#define MONITOR_CHANNELS   4U   /* SENSOR_NTC / TEC_V / TEC_I / ENV_NTC */

typedef struct {
    Ads1118 *Adc;                /* ads1118 driver (initialized by board_hal) */
    Heartbeat *Hb;               /* heartbeat tick source (timer0, 1ms) */
    s16 Raw[MONITOR_CHANNELS];   /* most recent raw code of each channel (index = channel order) */
    u32 SampleTick[MONITOR_CHANNELS]; /* heartbeat tick of the last successful read of each channel */
    u8  MuxIdx;                  /* current sampling channel (0..3) */
    u32 LastReadMs;              /* tick of the last read */
    u32 LastSwitchMs;            /* tick of the last channel switch */
} Monitor;

extern Monitor gMonitor;

int   Monitor_Init(Monitor *d, Ads1118 *adc, Heartbeat *hb);
void  Monitor_Tick(Monitor *d);                       /* called from main loop: read every 2ms / switch every 8ms */
s16   Monitor_GetRaw(Monitor *d, Ads1118_Mux mux);    /* raw code */
float Monitor_GetVoltage(Monitor *d, Ads1118_Mux mux);/* V */
float Monitor_GetNtcTemp(Monitor *d, Ads1118_Mux mux);/* degC (valid only for NTC channels) */
u32   Monitor_GetSampleTick(Monitor *d, Ads1118_Mux mux); /* heartbeat tick of the channel's last read */

#ifdef __cplusplus
}
#endif

#endif /* MONITOR_H */
