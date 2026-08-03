/******************************************************************************
* @file ccd_controller.c
*
* Driver implementation for the custom IP ccd_controller (AXI4-Lite).
*
* Register map is in 00-docs/verilog-design/ccd_controller_ip.md.
* This driver has no corresponding libsrc in the BSP, all hand-written; names do not
* start with X for easier cross-platform porting.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "ccd_controller.h"
#include "xparameters.h"
#include "xil_assert.h"

/******************************************************************************
* Config lookup table
******************************************************************************/
/*
 * xparameters.h only has base address macros, no separate DeviceID / interrupt
 * vector aliases, so DeviceId is 0 and IntrVecId uses the raw INTC vector number
 * directly.
 */
static CcdController_Config CcdController_ConfigTable[] = {
    {
        .DeviceId   = 0,
        .BaseAddress = XPAR_CCD_CONTROLLER_V1_0_0_BASEADDR,
        .IntrVecId  = XPAR_MICROBLAZE_0_AXI_INTC_CCD_CONTROLLER_V1_0_0_INTR_INTR,
    }
};

#define CCD_CONTROLLER_NUM_CONFIGS \
    (sizeof(CcdController_ConfigTable) / sizeof(CcdController_ConfigTable[0]))

/*****************************************************************************/
/**
* @brief  Looks up the config by DeviceId.
*
* @param  DeviceId The ID to look up (always 0 on this board).
*
* @return Config pointer, or NULL if not found.
******************************************************************************/
CcdController_Config *CcdController_LookupConfig(u16 DeviceId)
{
    u32 i;
    for (i = 0; i < CCD_CONTROLLER_NUM_CONFIGS; i++) {
        if (CcdController_ConfigTable[i].DeviceId == DeviceId) {
            return &CcdController_ConfigTable[i];
        }
    }
    return NULL;
}

/*****************************************************************************/
/**
* @brief  Initializes the driver instance.
*
* Only writes BaseAddress/IsReady, does not preset image parameters (to avoid
* overwriting config already set by the caller).
*
* @param  p    Instance pointer.
* @param  cfg  Config returned by LookupConfig.
* @param  addr Valid address (usually cfg->BaseAddress).
*
* @return XST_SUCCESS / XST_DEVICE_NOT_FOUND / XST_FAILURE.
******************************************************************************/
int CcdController_CfgInitialize(CcdController *p, CcdController_Config *cfg,
                                u32 addr)
{
    Xil_AssertNonvoid(p != NULL);

    if (cfg == NULL) {
        return XST_DEVICE_NOT_FOUND;
    }

    p->Config = *cfg;
    p->BaseAddress = addr;
    p->IsReady = 0U;
    p->IsStarted = 0U;
    p->Handler = NULL;
    p->CallBackRef = NULL;

    /* Power-on reset: disable interrupts, clear the exposure bit */
    CcdController_WriteReg(p, CCDC_REG_INTR_EN, 0U);
    CcdController_WriteReg(p, CCDC_REG_INTR_STS, CCDC_INTR_ALL);

    p->IsReady = 1U;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Register read/write self-test.
*
* Verifies R/W registers with a "write-read back-restore" check; write-only
* registers (TRIGGER) are not involved.
*
* @param  p Instance pointer.
*
* @return XST_SUCCESS / XST_FAILURE.
******************************************************************************/
int CcdController_SelfTest(CcdController *p)
{
    u32 rw_regs[3] = { CCDC_REG_CTRL, CCDC_REG_IMG_SIZE, CCDC_REG_BEVEL_BLANK };
    u32 saved[3];
    u32 i;

    Xil_AssertNonvoid(p != NULL);

    if (!p->IsReady) {
        return XST_DEVICE_NOT_FOUND;
    }

    for (i = 0; i < 3; i++) {
        saved[i] = CcdController_ReadReg(p, rw_regs[i]);
    }

    /* Write a known pattern and read it back (avoiding reserved/read-only bits;
     * the CTRL test value excludes bit0=exposure so the self-test does not
     * accidentally trigger capture) */
    CcdController_WriteReg(p, CCDC_REG_IMG_SIZE, 0x12345678U);
    if (CcdController_ReadReg(p, CCDC_REG_IMG_SIZE) != 0x12345678U) {
        return XST_FAILURE;
    }

    CcdController_WriteReg(p, CCDC_REG_BEVEL_BLANK, 0x00FF1111U);
    if (CcdController_ReadReg(p, CCDC_REG_BEVEL_BLANK) != 0x00FF1111U) {
        return XST_FAILURE;
    }

    CcdController_WriteReg(p, CCDC_REG_CTRL, 0x0000FFF0U);
    if (CcdController_ReadReg(p, CCDC_REG_CTRL) != 0x0000FFF0U) {
        return XST_FAILURE;
    }

    /* Restore the original values */
    for (i = 0; i < 3; i++) {
        CcdController_WriteReg(p, rw_regs[i], saved[i]);
    }

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Sets the image size (writes IMG_SIZE).
******************************************************************************/
void CcdController_SetImageSize(CcdController *p, u16 w, u16 h)
{
    CcdController_WriteReg(p, CCDC_REG_IMG_SIZE,
                           ((u32)h << 16) | (u32)w);
}

/*****************************************************************************/
/**
* @brief  Sets the bevel/blank parameters (writes BEVEL_BLANK).
******************************************************************************/
void CcdController_SetBevelBlank(CcdController *p,
                                 const CcdController_BevelBlank *bb)
{
    u32 val = 0U;
    if (bb == NULL) {
        return;
    }
    val |= ((u32)(bb->BevelLeft   & 0xFU) << 0);
    val |= ((u32)(bb->BevelTop    & 0xFU) << 4);
    val |= ((u32)(bb->BevelRight  & 0xFU) << 8);
    val |= ((u32)(bb->BevelBottom & 0xFU) << 12);
    val |= ((u32)(bb->BlankLeft   & 0xFU) << 16);
    val |= ((u32)(bb->BlankRight  & 0xFU) << 20);
    CcdController_WriteReg(p, CCDC_REG_BEVEL_BLANK, val);
}

/*****************************************************************************/
/**
* @brief  Sets the CDSCLK fine-tune delay (writes CTRL[11:5]).
******************************************************************************/
void CcdController_SetCdsclkDelay(CcdController *p, u8 delay)
{
    u32 ctrl = CcdController_ReadReg(p, CCDC_REG_CTRL);
    ctrl &= ~CCDC_CTRL_CDSCLK_DELAY_MASK;
    ctrl |= ((u32)(delay & 0x7FU) << 5);
    CcdController_WriteReg(p, CCDC_REG_CTRL, ctrl);
}

/*****************************************************************************/
/**
* @brief  Sets the readout mode (writes CTRL[4:3], read-modify-write keeps the other bits).
******************************************************************************/
void CcdController_SetReadMode(CcdController *p, u8 mode)
{
    u32 ctrl = CcdController_ReadReg(p, CCDC_REG_CTRL);
    ctrl &= ~CCDC_CTRL_READ_MODE_MASK;
    ctrl |= ((u32)(mode & 0x3U) << 3);
    CcdController_WriteReg(p, CCDC_REG_CTRL, ctrl);
}

/*****************************************************************************/
/**
* @brief  Sets the SCLK frequency (writes CTRL[1]).
******************************************************************************/
void CcdController_SetFreqSel(CcdController *p, u8 freq)
{
    u32 ctrl = CcdController_ReadReg(p, CCDC_REG_CTRL);
    if (freq) {
        ctrl |= CCDC_CTRL_FREQ_SEL_MASK;
    } else {
        ctrl &= ~CCDC_CTRL_FREQ_SEL_MASK;
    }
    CcdController_WriteReg(p, CCDC_REG_CTRL, ctrl);
}

/*****************************************************************************/
/**
* @brief  Sets mock mode (writes CTRL[2]).
******************************************************************************/
void CcdController_SetMockMode(CcdController *p, u8 mock)
{
    u32 ctrl = CcdController_ReadReg(p, CCDC_REG_CTRL);
    if (mock) {
        ctrl |= CCDC_CTRL_MOCK_MODE_MASK;
    } else {
        ctrl &= ~CCDC_CTRL_MOCK_MODE_MASK;
    }
    CcdController_WriteReg(p, CCDC_REG_CTRL, ctrl);
}

/*****************************************************************************/
/**
* @brief  Starts capture (sets exposure=1).
*
* Checks that DDR3 calibration is complete (STATUS[16]) before starting; returns
* XST_DEVICE_BUSY if not. Uses read-modify-write to keep the other CTRL bits
* (read_mode/freq/mock/cdsclk_delay etc.).
*
* @return XST_SUCCESS / XST_DEVICE_BUSY.
******************************************************************************/
int CcdController_StartCapture(CcdController *p)
{
    u32 ctrl;

    if (!CcdController_IsDdrReady(p)) {
        return XST_DEVICE_BUSY;
    }

    ctrl = CcdController_ReadReg(p, CCDC_REG_CTRL);
    ctrl |= CCDC_CTRL_EXPOSURE_MASK;
    CcdController_WriteReg(p, CCDC_REG_CTRL, ctrl);
    p->IsStarted = 1U;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  Stops capture (clears exposure=0, falling edge starts readout).
******************************************************************************/
void CcdController_StopCapture(CcdController *p)
{
    u32 ctrl = CcdController_ReadReg(p, CCDC_REG_CTRL);
    ctrl &= ~CCDC_CTRL_EXPOSURE_MASK;
    CcdController_WriteReg(p, CCDC_REG_CTRL, ctrl);
    p->IsStarted = 0U;
}

/*****************************************************************************/
/**
* @brief  Triggers a frame send (writes TRIGGER[0]=1, hardware stretches it then clears it).
******************************************************************************/
void CcdController_TriggerFrameSend(CcdController *p)
{
    CcdController_WriteReg(p, CCDC_REG_TRIGGER, CCDC_TRIGGER_TX_START_MASK);
}

/*****************************************************************************/
/**
* @brief  Number of readable frames in the frame buffer (STATUS[7:0]).
******************************************************************************/
u8 CcdController_GetFrameNum(CcdController *p)
{
    return (u8)(CcdController_ReadReg(p, CCDC_REG_STATUS) &
                CCDC_STATUS_FRAME_NUM_MASK);
}

/*****************************************************************************/
/**
* @brief  Whether DDR3 calibration is complete (STATUS[16]).
******************************************************************************/
u8 CcdController_IsDdrReady(CcdController *p)
{
    return (CcdController_ReadReg(p, CCDC_REG_STATUS) &
            CCDC_STATUS_DDR3_DONE_MASK) ? 1U : 0U;
}

/*****************************************************************************/
/**
* @brief  Frame exception flag (STATUS[8]).
******************************************************************************/
u8 CcdController_GetException(CcdController *p)
{
    return (CcdController_ReadReg(p, CCDC_REG_STATUS) &
            CCDC_STATUS_EXCEPTION_MASK) ? 1U : 0U;
}

/*****************************************************************************/
/**
* @brief  Accumulated frame exception count (STATUS[15:9]).
******************************************************************************/
u32 CcdController_GetExceptionCnt(CcdController *p)
{
    return (CcdController_ReadReg(p, CCDC_REG_STATUS) &
            CCDC_STATUS_EXCEPTION_CNT) >> 9;
}

/*****************************************************************************/
/**
* @brief  Reads the raw STATUS value (for debugging).
******************************************************************************/
u32 CcdController_GetStatus(CcdController *p)
{
    return CcdController_ReadReg(p, CCDC_REG_STATUS);
}

/*****************************************************************************/
/**
* @brief  Registers the interrupt callback.
******************************************************************************/
void CcdController_SetHandler(CcdController *p, CcdController_Handler hdl,
                              void *ref)
{
    p->Handler = hdl;
    p->CallBackRef = ref;
}

/*****************************************************************************/
/**
* @brief  Enables interrupts (writes INTR_EN).
******************************************************************************/
void CcdController_IntrEnable(CcdController *p, u8 tx_done_en,
                              u8 exception_en)
{
    u32 en = 0U;
    if (tx_done_en) {
        en |= CCDC_INTR_TX_DONE;
    }
    if (exception_en) {
        en |= CCDC_INTR_EXCEPTION;
    }
    CcdController_WriteReg(p, CCDC_REG_INTR_EN, en);
}

/*****************************************************************************/
/**
* @brief  Disables all interrupts.
******************************************************************************/
void CcdController_IntrDisable(CcdController *p)
{
    CcdController_WriteReg(p, CCDC_REG_INTR_EN, 0U);
}

/*****************************************************************************/
/**
* @brief  ccd_controller ISR, hooked to the INTC.
*
* Reads INTR_STS -> masks with INTR_EN -> W1C clear -> calls back to the app
* (minimal processing).
*
* @param ref CcdController instance pointer.
******************************************************************************/
void CcdController_InterruptHandler(void *ref)
{
    CcdController *p = (CcdController *)ref;
    u32 en = CcdController_ReadReg(p, CCDC_REG_INTR_EN) & CCDC_INTR_ALL;
    u32 pending = CcdController_ReadReg(p, CCDC_REG_INTR_STS) & en;

    if (pending != 0U) {
        /* W1C: write 1 to clear */
        CcdController_WriteReg(p, CCDC_REG_INTR_STS, pending);
        if (p->Handler != NULL) {
            p->Handler(pending, p->CallBackRef);
        }
    }
}
