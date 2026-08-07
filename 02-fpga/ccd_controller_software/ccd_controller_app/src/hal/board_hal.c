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
*   (2 = spi, 4 = iic, 6 = Gpio_key not used at this layer; key is polled by
*    Key_Tick() on each heartbeat, no interrupt involved)
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/02 First release
* 1.1   wwc  26/08/03 Complete function doc comments (Xilinx style)
* 1.2   wwc  26/08/03 Refactor UART init into BoardHal_InitUart
* 1.3   wwc  26/08/03 Remove dead key interrupt wiring and BoardHal_SelfTest
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
*
* @return XST_SUCCESS / the status of the failing XGpio_Initialize.
******************************************************************************/
static int BoardHal_InitGpio(void)
{
    int status;

    status = XGpio_Initialize(&gGpioFx2Fifo, XPAR_AXI_GPIO_FX2FIFO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XGpio_Initialize(&gGpioGeneral, XPAR_AXI_GPIO_GENERAL_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XGpio_Initialize(&gGpioKey, XPAR_AXI_GPIO_KEY_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XGpio_Initialize(&gGpioLed, XPAR_AXI_GPIO_LED_DEVICE_ID);
    return status;
}

/*****************************************************************************/
/**
* @brief  Initializes the timer instances (timer0 heartbeat, timer1 exposure).
*
* @return XST_SUCCESS / the status of the failing init or self-test.
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
*
* @return XST_SUCCESS / XST_DEVICE_NOT_FOUND / underlying error.
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
    /*
	 * Disable Global interrupt to use polled mode operation
	 */
	XSpi_IntrGlobalDisable(&gSpi);
    return status;
}

/*****************************************************************************/
/**
* @brief  Initializes the UART (STDOUT device) and enables its interrupt.
*
* UART is the STDOUT device, so SelfTest is skipped on purpose (its loopback
* test needs a physical loopback). It must be initialized before any prints.
*
* @return XST_SUCCESS / the status of the failing XUartLite_Initialize.
******************************************************************************/
static int BoardHal_InitUart(void)
{
    int status;

    status = XUartLite_Initialize(&gUart, XPAR_UARTLITE_0_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }
    XUartLite_ResetFifos(&gUart);
    XUartLite_EnableInterrupt(&gUart);

    return XST_SUCCESS;
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

    status = XIntc_Start(intc, XIN_REAL_MODE);
    if (status != XST_SUCCESS) {
        return status;
    }

    XIntc_Enable(intc, CCD_INTR_VEC);
    XIntc_Enable(intc, TIMER0_VEC);
    XIntc_Enable(intc, UART_VEC);
    XIntc_Enable(intc, TIMER1_VEC);

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
* Order: cache -> UART -> SPI -> GPIO -> Timer -> CcdController -> INTC ->
* app drivers -> key GPIO direction.
*
* @return XST_SUCCESS / XST_FAILURE.
******************************************************************************/
int BoardHal_Init(void)
{
    int status;

    Xil_ICacheEnable();
    Xil_DCacheEnable();

    /* UART first, so later prints work. */
    status = BoardHal_InitUart();
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
    Uart_Init(&gUartDrv, &gUart, UART_VEC);
    Heartbeat_Init(&gHeartbeat, &gTimer0, TIMER0_VEC);
    Key_Init(&gKey, &gGpioKey, KEY_ACTIVE_LOW_MASK);
    Led_Init(&gLed, &gGpioLed, LED_OUT_MASK);
    Fx2_Init(&gFx2, &gGpioFx2Fifo);
    Adn8833_Init(&gAdn8833, &gGpioGeneral, ADN8833_EN_BIT);
    Ccd_Init(&gCcd, &gCcdCtrl, &gTimer1, TIMER1_VEC);
    Ads1118_Init(&gAds1118, &gSpi, SPI_CS_ADS1118);
    Dac8311_Init(&gDac8311, &gSpi, SPI_CS_DAC8311, DAC8311_VREF_V);
    Ad9826_Init(&gAd9826, &gSpi, SPI_CS_AD9826);

    /* Enable ccd interrupts (tx_done + exception + frame_written) */
    CcdController_IntrEnable(&gCcdCtrl, 1U, 1U, 1U);

    return XST_SUCCESS;
}
