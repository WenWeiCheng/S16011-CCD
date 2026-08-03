/******************************************************************************
* @file monitor.h
*
* 采样监控循环：周期性采样 ads1118 四路输入（CCD 传感器 NTC、TEC 电压、
* TEC 电流、环境 NTC），缓存各通道原始码，并按需换算成工程值。
* 协议层 RO 参数（sensor_temp / tec_voltage / tec_current 等）经本模块取值。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/03 First release
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
    Ads1118 *Adc;                /* ads1118 驱动（board_hal 已初始化） */
    Heartbeat *Hb;               /* 心跳节拍源（timer0，1ms） */
    s16 Raw[MONITOR_CHANNELS];   /* 各通道最近一次原始码（索引=通道序） */
    u8  MuxIdx;                  /* 当前采样通道（0..3） */
    u32 LastReadMs;              /* 上次读数节拍 */
    u32 LastSwitchMs;            /* 上次换通道节拍 */
} Monitor;

extern Monitor gMonitor;

int   Monitor_Init(Monitor *d, Ads1118 *adc, Heartbeat *hb);
void  Monitor_Tick(Monitor *d);                       /* 主循环调用：2ms 读 / 8ms 换通道 */
s16   Monitor_GetRaw(Monitor *d, Ads1118_Mux mux);    /* 原始码 */
float Monitor_GetVoltage(Monitor *d, Ads1118_Mux mux);/* V */
float Monitor_GetNtcTemp(Monitor *d, Ads1118_Mux mux);/* degC（仅 NTC 通道有效） */

#ifdef __cplusplus
}
#endif

#endif /* MONITOR_H */
