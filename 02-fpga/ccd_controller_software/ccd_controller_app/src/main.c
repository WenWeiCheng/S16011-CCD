/******************************************************************************
* @file main.c
*
* CCD 控制器应用入口：装配 app 逻辑层。
*  - UART 行 → Protocol（命令分发表 / 参数表 / ACQ）
*  - Monitor 遥测采样循环（ads1118 四路：NTC×2 / TEC 电压 / TEC 电流）
*  - 心跳 → 按键消抖；LED0 心跳闪烁
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/03 Rewrite: wire app logic layer (UART protocol)
* 1.0   whc  26/08/02 First release (driver smoke test)
* </pre>
******************************************************************************/
#include "hal/board_hal.h"
#include "include/board_config.h"
#include "app_logic/protocol.h"
#include "app_logic/monitor.h"
#include "xil_printf.h"
#include "xil_types.h"

/*****************************************************************************/
/**
* @brief  心跳周期任务：按键消抖 FSM（必须 1ms 节拍）。
******************************************************************************/
static void App_HeartbeatTick(void *ref)
{
    (void)ref;
    Key_Tick(&gKey, 1U);
}

/*****************************************************************************/
/**
* @brief  主函数。
******************************************************************************/
int main(void)
{
    u32 ledTick = 0U;

    if (BoardHal_Init() != XST_SUCCESS) {
        xil_printf("BoardHal_Init FAILED\r\n");
        return -1;
    }

    /* 装配 app 逻辑层 */
    Uart_RegisterLineHandler(&gUartDrv, Protocol_OnLine, NULL);
    Uart_RegisterErrorHandler(&gUartDrv, Protocol_OnError, NULL);
    Heartbeat_RegisterHandler(&gHeartbeat, App_HeartbeatTick, NULL);

    Monitor_Init(&gMonitor, &gAds1118, &gHeartbeat);
    Protocol_Init();

    while (1) {
        u32 tick = Heartbeat_GetTick(&gHeartbeat);

        Monitor_Tick(&gMonitor);
        Protocol_ProcessPending();

        /* LED0 心跳闪烁（500ms） */
        if (tick - ledTick >= 500U) {
            ledTick = tick;
            Led_Toggle(&gLed, 0);
        }
    }
}
