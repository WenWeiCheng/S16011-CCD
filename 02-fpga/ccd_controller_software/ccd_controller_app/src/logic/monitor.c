/******************************************************************************
* @file monitor.c
*
* Sampling/monitor loop implementation: ads1118 continuous mode at 860SPS, reads the raw
* code of the current channel every 2ms, switches input channel every 8ms, sampling the
* four channels in rotation (sufficient channel settling time).
*
* Conversion:
*   - Voltage: V = code x FS / 2^15 (single-ended half scale, FS=+/-4.096V)
*   - NTC temperature: per-channel lookup table + linear interpolation. The sensor
*     (AIN0) and environment (AIN3) channels each have their own table (generated
*     offline by tools/gen_ntc_table.py from the per-channel NTC parameters in
*     board_config.h), so different NTC parts / divider resistors are supported.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/03 First release
* 1.1   wwc  26/08/03 Complete function doc comments (Xilinx style)
* 1.2   wwc  26/08/03 Per-channel NTC tables (sensor/env), lookup moved to ntc.c
* 1.3   wwc  26/08/04 Per-channel sample tick (Monitor_GetSampleTick) for the TEC loop
* </pre>
******************************************************************************/
#include "monitor.h"
#include "ntc.h"
#include "../include/board_config.h"
#include "xil_assert.h"

/* Index mapping: Ads1118_Mux enum is contiguous (0x4..0x7) -> channel order 0..3 */
#define MONITOR_MUX_BASE   ((u8)ADS1118_MUX_SENSOR_NTC)

Monitor gMonitor;

/* Per-channel NTC lookup configs (channel order 0..3: SENSOR_NTC/TEC_V/TEC_I/ENV_NTC).
 * Only the two NTC channels carry a table; the TEC channels are not NTCs. */
static const NtcTableCfg g_ntc_cfg[MONITOR_CHANNELS] = {
    [0] = { g_sensor_ntc_table, NTC_SENSOR_TABLE_N },   /* SENSOR_NTC */
    [3] = { g_env_ntc_table,    NTC_ENV_TABLE_N    },   /* ENV_NTC    */
};

/*****************************************************************************/
/**
* @brief  Ads1118_Mux enum (0x4..0x7) -> channel order 0..3.
*
* @param  mux  One of the Ads1118_Mux channel values.
*
* @return Channel index 0..3 (clamped to 0 if out of range).
******************************************************************************/
static u8 Monitor_MuxToIdx(Ads1118_Mux mux)
{
    u8 idx = (u8)mux - MONITOR_MUX_BASE;
    if (idx >= MONITOR_CHANNELS) {
        idx = 0U;
    }
    return idx;
}

/*****************************************************************************/
/**
* @brief  Initializes: stores the dependency instances, starts sampling from SENSOR_NTC.
*
* @param  adc  ads1118 driver instance (initialized by board_hal).
* @param  hb   Heartbeat tick source.
*
* @return XST_SUCCESS.
******************************************************************************/
int Monitor_Init(Monitor *d, Ads1118 *adc, Heartbeat *hb)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(adc != NULL);
    Xil_AssertNonvoid(hb != NULL);

    d->Adc = adc;
    d->Hb = hb;
    d->MuxIdx = 0U;
    d->LastReadMs = 0U;
    d->LastSwitchMs = 0U;
    d->Raw[0] = d->Raw[1] = d->Raw[2] = d->Raw[3] = 0;
    d->SampleTick[0] = d->SampleTick[1] = d->SampleTick[2] = d->SampleTick[3] = 0U;

    Ads1118_SetChannel(adc, ADS1118_MUX_SENSOR_NTC);
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Main loop tick: switch channel every 8ms, read the current channel's raw code
* into the cache every 2ms.
*
* @param  d  Monitor instance.
******************************************************************************/
void Monitor_Tick(Monitor *d)
{
    u32 tick = Heartbeat_GetTick(d->Hb);

    if (tick - d->LastSwitchMs >= 8U) {
        d->LastSwitchMs = tick;
        d->MuxIdx = (u8)((d->MuxIdx + 1U) & (MONITOR_CHANNELS - 1U));
        Ads1118_SetChannel(d->Adc,
                           (Ads1118_Mux)(MONITOR_MUX_BASE + d->MuxIdx));
    }

    if (tick - d->LastReadMs >= 2U) {
        s16 raw;
        d->LastReadMs = tick;
        if (Ads1118_ReadRaw(d->Adc, &raw) == XST_SUCCESS) {
            d->Raw[d->MuxIdx] = raw;
            d->SampleTick[d->MuxIdx] = tick;
        }
    }
}

/*****************************************************************************/
/**
* @brief  Most recent raw code of a channel.
*
* @param  d    Monitor instance.
* @param  mux  Channel to read.
*
* @return Cached raw ADC code (signed 16-bit).
******************************************************************************/
s16 Monitor_GetRaw(Monitor *d, Ads1118_Mux mux)
{
    return d->Raw[Monitor_MuxToIdx(mux)];
}

/*****************************************************************************/
/**
* @brief  Converted voltage of a channel (V).
*
* V = code x FS / 2^15, single-ended half scale, FS = ADS1118_FS_VOLT.
*
* @param  d    Monitor instance.
* @param  mux  Channel to read.
*
* @return Voltage in V.
******************************************************************************/
float Monitor_GetVoltage(Monitor *d, Ads1118_Mux mux)
{
    s16 code = d->Raw[Monitor_MuxToIdx(mux)];
    return (float)code * ADS1118_FS_VOLT / 32768.0f;
}

/*****************************************************************************/
/**
* @brief  NTC channel converted temperature (degC). Meaningless for non-NTC channels.
*
* @param  d    Monitor instance.
* @param  mux  NTC channel to read.
*
* @return Temperature in degC.
******************************************************************************/
float Monitor_GetNtcTemp(Monitor *d, Ads1118_Mux mux)
{
    u8 idx = Monitor_MuxToIdx(mux);
    const NtcTableCfg *cfg = &g_ntc_cfg[idx];

    if (cfg->Table == NULL) {
        return 0.0f;    /* not an NTC channel */
    }
    return Ntc_LookupTemp(d->Raw[idx], cfg);
}

/*****************************************************************************/
/**
* @brief  Heartbeat tick of the last successful read of a channel.
*
* Consumers (e.g. the TEC control loop) compare successive ticks to detect a
* fresh sample and derive the real sample interval.
*
* @param  d    Monitor instance.
* @param  mux  Channel to query.
*
* @return Heartbeat tick (ms) of the channel's last read.
******************************************************************************/
u32 Monitor_GetSampleTick(Monitor *d, Ads1118_Mux mux)
{
    return d->SampleTick[Monitor_MuxToIdx(mux)];
}
