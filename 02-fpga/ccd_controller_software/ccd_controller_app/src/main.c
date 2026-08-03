/******************************************************************************
* @file main.c
*
* CCD controller application entry: assembles the app logic layer.
*  - UART line -> Protocol (command dispatch table / parameter table / ACQ)
*  - Monitor telemetry sampling loop (ads1118 four channels: NTC x2 / TEC voltage / TEC current)
*  - Heartbeat -> key debounce; LED0 heartbeat blink
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/03 Rewrite: wire app logic layer (UART protocol)
* 1.0   wwc  26/08/02 First release (driver smoke test)
* </pre>
******************************************************************************/
#include "app_drivers/led.h"
#include "hal/board_hal.h"
#include "include/board_config.h"
#include "app_logic/protocol.h"
#include "app_logic/monitor.h"
#include "xil_printf.h"
#include "xil_types.h"

/*****************************************************************************/
/**
* @brief  Heartbeat periodic task: key debounce FSM (must tick at 1ms).
******************************************************************************/
static void App_HeartbeatTick(void *ref)
{
    (void)ref;
    Key_Tick(&gKey, 1U);
}

/*****************************************************************************/
/**
* @brief  Main function.
******************************************************************************/
int main(void)
{
    u32 ledTick = 0U;

    if (BoardHal_Init() != XST_SUCCESS) {
        xil_printf("BoardHal_Init FAILED\r\n");
        return -1;
    }

    /* Assemble the app logic layer */
    Uart_RegisterLineHandler(&gUartDrv, Protocol_OnLine, NULL);
    Uart_RegisterErrorHandler(&gUartDrv, Protocol_OnError, NULL);
    Heartbeat_RegisterHandler(&gHeartbeat, App_HeartbeatTick, NULL);

    Monitor_Init(&gMonitor, &gAds1118, &gHeartbeat);
    Protocol_Init();

    while (1) {
        u32 tick = Heartbeat_GetTick(&gHeartbeat);

        Monitor_Tick(&gMonitor);
        Protocol_ProcessPending();

        /* LED0 heartbeat blink (500ms) */
        if (tick - ledTick >= 500U) {
            ledTick = tick;
            Led_Toggle(&gLed, 0);
        }
    }
}
