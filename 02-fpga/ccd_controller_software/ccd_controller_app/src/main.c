/******************************************************************************
* @file main.c
*
* CCD 控制器应用入口：初始化驱动层 + 冒烟测试。
*
* 本文件是 app 逻辑层的挂载占位：目前只做驱动初始化 + 周期打印，
* 后续 UART 命令解析 / 曝光状态机 / 遥测循环将构建在此之上。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "hal/board_hal.h"
#include "include/board_config.h"
#include "xil_printf.h"
#include "xil_types.h"

/* ============================================================================
 * 回调（冒烟测试演示用，app 逻辑层将替换）
 * ==========================================================================*/
static void Smoke_CcdHandler(CcdState st, void *ref)
{
    static const char *const names[] = {
        [CCD_IDLE] = "idle", [CCD_EXPOSING] = "exposing",
        [CCD_READING] = "reading", [CCD_TX] = "tx"
    };
    (void)ref;
    xil_printf("[ccd] state -> %s\r\n", names[st]);
}

static void Smoke_KeyHandler(KeyEvent evt, void *ref)
{
    static const char *const names[] = {
        [KEY_IDLE] = "idle", [KEY_PRESSED] = "pressed",
        [KEY_RELEASED] = "released", [KEY_LONG_PRESS] = "long_press"
    };
    (void)ref;
    xil_printf("[key] %s\r\n", names[evt]);
}

static void Smoke_UartLineHandler(const char *line, void *ref)
{
    (void)ref;
    xil_printf("<< %s\r\n", line);
    Uart_SendLine(&gUartDrv, "OK echo");
}

/* ============================================================================
 * 心跳周期任务：按键消抖 FSM（必须 1ms 节拍）
 * ==========================================================================*/
static void Smoke_HeartbeatTick(void *ref)
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
    static const Ads1118_Mux muxOrder[4] = {
        ADS1118_MUX_SENSOR_NTC,   /* AIN0 */
        ADS1118_MUX_TEC_V,        /* AIN1 */
        ADS1118_MUX_TEC_I,        /* AIN2 */
        ADS1118_MUX_ENV_NTC       /* AIN3 */
    };
    u8 muxIdx = 0U;
    u32 lastSwitch = 0U;   /* ads1118 通道切换节拍（8ms） */
    u32 lastRead = 0U;     /* ads1118 读数节拍（2ms） */
    u32 lastPrint = 0U;    /* 状态打印节拍（1s） */
    s16 lastRaw = 0;

    if (BoardHal_Init() != XST_SUCCESS) {
        xil_printf("BoardHal_Init FAILED\r\n");
        return -1;
    }

    /* 注册回调（冒烟测试） */
    Ccd_RegisterHandler(&gCcd, Smoke_CcdHandler, NULL);
    Key_RegisterHandler(&gKey, Smoke_KeyHandler, NULL);
    Uart_RegisterLineHandler(&gUartDrv, Smoke_UartLineHandler, NULL);
    Heartbeat_RegisterHandler(&gHeartbeat, Smoke_HeartbeatTick, NULL);

    BoardHal_SelfTest();

    xil_printf("\r\n--- CCD driver smoke test running ---\r\n");
    Led_On(&gLed, 0);
    Adn8833_SetEnable(&gAdn8833, 1U);
    xil_printf("adn8833 enabled\r\n");

    while (1) {
        u32 tick = Heartbeat_GetTick(&gHeartbeat);

        /* ads1118 调度：每 8ms 换通道，每 2ms 读数 */
        if (tick - lastSwitch >= 8U) {
            lastSwitch = tick;
            Ads1118_SetChannel(&gAds1118, muxOrder[muxIdx]);
            muxIdx = (muxIdx + 1U) & 0x3U;
        }
        if (tick - lastRead >= 2U) {
            lastRead = tick;
            Ads1118_ReadRaw(&gAds1118, &lastRaw);
        }

        /* 每秒打印一次状态 + LED 翻转 */
        if (tick - lastPrint >= 1000U) {
            lastPrint = tick;
            Led_Toggle(&gLed, 0);
            xil_printf("[t=%d] ads1118=%d ddr=%d frame=%d exc=%d key=%s usb=%d\r\n",
                       (int)tick, (int)lastRaw,
                       (int)Ccd_IsDdrReady(&gCcd),
                       (int)Ccd_GetFrameNum(&gCcd),
                       (int)Ccd_GetExceptionCnt(&gCcd),
                       (Key_GetState(&gKey) == KEY_STATE_PRESSED) ? "pressed" : "idle",
                       (int)Fx2_IsUsbReady(&gFx2));
        }
    }
}
