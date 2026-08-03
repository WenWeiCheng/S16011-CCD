/******************************************************************************
* @file board_hal.c
*
* Board-level hardware abstraction implementation: defines the shared global instances,
* initializes all peripherals and wires up the INTC.
*
* Interrupt vectors (see xparameters.h, compare ccd_controller_driver_architecture.md sec. 6):
*   0 = ccd_controller -> CcdController_InterruptHandler
*   1 = timer0        -> XTmrCtr_InterruptHandler -> Heartbeat_InterruptHandler
*   3 = uart          -> Uart_InterruptHandler
*   5 = timer1        -> XTmrCtr_InterruptHandler -> Ccd_ExposureHandler
*   6 = Gpio_key      -> Key_InterruptHandler
*   (2 = spi, 4 = iic not used at this layer, not connected)
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

/* Interrupt vectors (use raw macros when an alias is missing) */
#define CCD_INTR_VEC    XPAR_MICROBLAZE_0_AXI_INTC_CCD_CONTROLLER_V1_0_0_INTR_INTR
#define TIMER0_VEC      XPAR_INTC_0_TMRCTR_0_VEC_ID
#define UART_VEC        XPAR_INTC_0_UARTLITE_0_VEC_ID
#define TIMER1_VEC      XPAR_INTC_0_TMRCTR_1_VEC_ID
#define KEY_VEC         XPAR_INTC_0_GPIO_2_VEC_ID

/* Shared global Xilinx instances */
XSpi      gSpi;
XGpio     gGpioFx2Fifo;
XGpio     gGpioGeneral;
XGpio     gGpioKey;
XGpio     gGpioLed;
XTmrCtr   gTimer0;
XTmrCtr   gTimer1;
XUartLite gUart;
XIntc     gIntc;

/* Global app driver instances */
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
* @brief  Initializes the GPIO instances (direction set by each app driver Init).
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
* @brief  Initializes the timer instances.
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
* @brief  Initializes SPI (master mode + manual chip select) and starts it.
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
* @brief  Wires up the INTC: Connect -> Start -> Enable each vector.
*
* @param  Intc The XIntc instance.
* @return XST_SUCCESS / failure.
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

    /* One-time setup: hook the exception handler to INTC */
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XIntc_InterruptHandler,
                                 intc);
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Initializes all peripherals and wires up the INTC.
*
* Order: cache -> UART -> INTC -> SPI -> GPIO -> Timer -> CcdController ->
* app drivers -> key interrupt enable -> heartbeat start.
*
* @return XST_SUCCESS / XST_FAILURE.
******************************************************************************/
int BoardHal_Init(void)
{
    int status;

    Xil_ICacheEnable();
    Xil_DCacheEnable();

    xil_printf("\r\n--- BoardHal_Init ---\r\n");

    /* UART first, so later prints work.
     * Note: UART is the STDOUT device, so SelfTest is skipped (its loopback test
     * needs a physical loopback). */
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

    /* Wire up INTC */
    status = BoardHal_SetupIntc(&gIntc);
    if (status != XST_SUCCESS) {
        xil_printf("INTC setup FAILED\r\n");
        return XST_FAILURE;
    }

    /* app drivers */
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

    /* Enable ccd interrupts (tx_done + exception) */
    CcdController_IntrEnable(&gCcdCtrl, 1U, 1U);

    /* Key: input direction (1=input) + interrupt enable */
    XGpio_SetDataDirection(&gGpioKey, 1U, KEY_IN_MASK);
    XGpio_InterruptGlobalEnable(&gGpioKey);
    XGpio_InterruptEnable(&gGpioKey, KEY_IN_MASK);

    xil_printf("--- BoardHal_Init done ---\r\n");
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  CcdController self-test + key status printout (for smoke testing).
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
