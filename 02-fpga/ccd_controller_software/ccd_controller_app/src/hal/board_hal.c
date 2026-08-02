/******************************************************************************
* @file board_hal.c
*
* 板级硬件抽象实现：定义全局共享实例，初始化全部外设并接线 INTC。
*
* 中断向量（见 xparameters.h，对照 ccd_controller_driver_architecture.md §6）：
*   0 = ccd_controller → CcdController_InterruptHandler
*   1 = timer0        → XTmrCtr_InterruptHandler → Heartbeat_InterruptHandler
*   3 = uart          → Uart_InterruptHandler
*   5 = timer1        → XTmrCtr_InterruptHandler → Ccd_ExposureHandler
*   6 = Gpio_key      → Key_InterruptHandler
*   （2 = spi、4 = iic 本层未使用，不接线）
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "board_hal.h"
#include "../include/board_config.h"
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"

/* 中断向量（别名缺失时用原始宏） */
#define CCD_INTR_VEC    XPAR_MICROBLAZE_0_AXI_INTC_CCD_CONTROLLER_V1_0_0_INTR_INTR
#define TIMER0_VEC      XPAR_INTC_0_TMRCTR_0_VEC_ID
#define UART_VEC        XPAR_INTC_0_UARTLITE_0_VEC_ID
#define TIMER1_VEC      XPAR_INTC_0_TMRCTR_1_VEC_ID
#define KEY_VEC         XPAR_INTC_0_GPIO_2_VEC_ID

/* 全局共享 Xilinx 实例 */
XSpi      gSpi;
XGpio     gGpioFx2Fifo;
XGpio     gGpioGeneral;
XGpio     gGpioKey;
XGpio     gGpioLed;
XTmrCtr   gTimer0;
XTmrCtr   gTimer1;
XUartLite gUart;
XIntc     gIntc;

/* 全局 app 驱动实例 */
Heartbeat     gHeartbeat;
Key           gKey;
Led           gLed;
Fx2           gFx2;
Adn8833       gAdn8833;
Ccd           gCcd;
Uart          gUartDrv;
Ads1118       gAds1118;
Dac8311       gDac8311;
Ad9826        gAd9826;
CcdController gCcdCtrl;

/*****************************************************************************/
/**
* @brief  初始化 GPIO 实例（方向由各 app 驱动 Init 设置）。
******************************************************************************/
static int BoardHal_InitGpio(void)
{
    int status;

    status = XGpio_Initialize(&gGpioFx2Fifo, XPAR_GPIO_0_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XGpio_Initialize(&gGpioGeneral, XPAR_GPIO_1_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XGpio_Initialize(&gGpioKey, XPAR_GPIO_2_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XGpio_Initialize(&gGpioLed, XPAR_GPIO_3_DEVICE_ID);
    return status;
}

/*****************************************************************************/
/**
* @brief  初始化 timer 实例。
******************************************************************************/
static int BoardHal_InitTimer(void)
{
    int status;

    status = XTmrCtr_Initialize(&gTimer0, XPAR_TMRCTR_0_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XTmrCtr_SelfTest(&gTimer0, 0U);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XTmrCtr_Initialize(&gTimer1, XPAR_TMRCTR_1_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    return XTmrCtr_SelfTest(&gTimer1, 0U);
}

/*****************************************************************************/
/**
* @brief  初始化 SPI（主模式 + 手动片选），并启动。
******************************************************************************/
static int BoardHal_InitSpi(void)
{
    int status;
    XSpi_Config *cfg;

    cfg = XSpi_LookupConfig(XPAR_SPI_0_DEVICE_ID);
    if (cfg == NULL) {
        return XST_DEVICE_NOT_FOUND;
    }
    status = XSpi_CfgInitialize(&gSpi, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XSpi_SelfTest(&gSpi);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XSpi_SetOptions(&gSpi,
                             XSP_MASTER_OPTION |
                             XSP_MANUAL_SSELECT_OPTION);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XSpi_Start(&gSpi);
    return status;
}

/*****************************************************************************/
/**
* @brief  接线 INTC：Connect → Start → Enable 各向量。
*
* @param  Intc XIntc 实例。
* @return XST_SUCCESS / 失败。
******************************************************************************/
static int BoardHal_SetupIntc(XIntc *intc)
{
    int status;

    status = XIntc_Initialize(intc, XPAR_INTC_0_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XIntc_Connect(intc, CCD_INTR_VEC,
                           (XInterruptHandler)CcdController_InterruptHandler,
                           &gCcdCtrl);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XIntc_Connect(intc, TIMER0_VEC,
                           (XInterruptHandler)XTmrCtr_InterruptHandler,
                           &gTimer0);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XIntc_Connect(intc, UART_VEC,
                           (XInterruptHandler)Uart_InterruptHandler,
                           &gUartDrv);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XIntc_Connect(intc, TIMER1_VEC,
                           (XInterruptHandler)XTmrCtr_InterruptHandler,
                           &gTimer1);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XIntc_Connect(intc, KEY_VEC,
                           (XInterruptHandler)Key_InterruptHandler,
                           &gKey);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XIntc_Start(intc, XIN_REAL_MODE);
    if (status != XST_SUCCESS) {
        return status;
    }

    XIntc_Enable(intc, CCD_INTR_VEC);
    XIntc_Enable(intc, TIMER0_VEC);
    XIntc_Enable(intc, UART_VEC);
    XIntc_Enable(intc, TIMER1_VEC);
    XIntc_Enable(intc, KEY_VEC);

    /* 一次性：异常处理器接入 INTC */
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XIntc_InterruptHandler,
                                 intc);
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  初始化全部外设并接线 INTC。
*
* 顺序：cache → UART → INTC → SPI → GPIO → Timer → CcdController →
* app 驱动 → 按键中断使能 → 心跳启动。
*
* @return XST_SUCCESS / XST_FAILURE。
******************************************************************************/
int BoardHal_Init(void)
{
    int status;

    Xil_ICacheEnable();
    Xil_DCacheEnable();

    xil_printf("\r\n--- BoardHal_Init ---\r\n");

    /* UART 先行，便于后续打印。
     * 注意：UART 为 STDOUT 设备，不跑 SelfTest（其回环测试需要物理回环）。 */
    status = XUartLite_Initialize(&gUart, XPAR_UARTLITE_0_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    /* SPI / GPIO / Timer */
    status = BoardHal_InitSpi();
    if (status != XST_SUCCESS) {
        xil_printf("SPI init FAILED\r\n");
        return XST_FAILURE;
    }
    status = BoardHal_InitGpio();
    if (status != XST_SUCCESS) {
        xil_printf("GPIO init FAILED\r\n");
        return XST_FAILURE;
    }
    status = BoardHal_InitTimer();
    if (status != XST_SUCCESS) {
        xil_printf("Timer init FAILED\r\n");
        return XST_FAILURE;
    }

    /* CcdController HAL */
    status = CcdController_CfgInitialize(&gCcdCtrl,
                                         CcdController_LookupConfig(0U),
                                         XPAR_CCD_CONTROLLER_V1_0_0_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("CcdController init FAILED\r\n");
        return XST_FAILURE;
    }

    /* 接线 INTC */
    status = BoardHal_SetupIntc(&gIntc);
    if (status != XST_SUCCESS) {
        xil_printf("INTC setup FAILED\r\n");
        return XST_FAILURE;
    }

    /* app 驱动 */
    Heartbeat_Init(&gHeartbeat, &gTimer0, TIMER0_VEC);
    Key_Init(&gKey, &gGpioKey, KEY_ACTIVE_LOW_MASK);
    Led_Init(&gLed, &gGpioLed, LED_OUT_MASK);
    Fx2_Init(&gFx2, &gGpioFx2Fifo);
    Adn8833_Init(&gAdn8833, &gGpioGeneral, ADN8833_EN_BIT);
    Ccd_Init(&gCcd, &gCcdCtrl, &gTimer1, TIMER1_VEC);
    Uart_Init(&gUartDrv, &gUart, UART_VEC);
    Ads1118_Init(&gAds1118, &gSpi, SPI_CS_ADS1118);
    Dac8311_Init(&gDac8311, &gSpi, SPI_CS_DAC8311, DAC8311_VREF_V);
    Ad9826_Init(&gAd9826, &gSpi, SPI_CS_AD9826);

    /* 使能 ccd 中断（tx_done + exception） */
    CcdController_IntrEnable(&gCcdCtrl, 1U, 1U);

    /* 按键：输入方向（1=输入）+ 中断使能 */
    XGpio_SetDataDirection(&gGpioKey, 1U, KEY_IN_MASK);
    XGpio_InterruptGlobalEnable(&gGpioKey);
    XGpio_InterruptEnable(&gGpioKey, KEY_IN_MASK);

    xil_printf("--- BoardHal_Init done ---\r\n");
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  CcdController 自检 + 关键状态打印（冒烟测试用）。
******************************************************************************/
void BoardHal_SelfTest(void)
{
    u32 status;

    status = CcdController_SelfTest(&gCcdCtrl);
    xil_printf("CcdController SelfTest: %s\r\n",
               (status == XST_SUCCESS) ? "PASS" : "FAIL");

    xil_printf("DDR3 ready: %d\r\n",
               (int)CcdController_IsDdrReady(&gCcdCtrl));
    xil_printf("frame_num: %d\r\n",
               (int)CcdController_GetFrameNum(&gCcdCtrl));
    xil_printf("exception: %d (cnt=%d)\r\n",
               (int)CcdController_GetException(&gCcdCtrl),
               (int)CcdController_GetExceptionCnt(&gCcdCtrl));
    xil_printf("STATUS raw: 0x%x\r\n", (int)CcdController_GetStatus(&gCcdCtrl));
}
