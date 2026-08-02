/******************************************************************************
* @file ccd_controller.c
*
* 自制 IP ccd_controller（AXI4-Lite）驱动实现。
*
* 寄存器映射见 00-docs/verilog-design/ccd_controller_ip.md。
* 本驱动在 BSP 中无对应 libsrc，全部手写；命名不以 X 开头便于跨平台移植。
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
* Config 查找表
******************************************************************************/
/*
 * xparameters.h 中只有基地址宏、没有独立的 DeviceID/中断向量别名，
 * 因此 DeviceId 取 0，IntrVecId 直接用 INTC 的原始向量号。
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
* @brief  按 DeviceId 查找配置。
*
* @param  DeviceId 查找 ID（本板恒为 0）。
*
* @return 配置指针；未找到返回 NULL。
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
* @brief  初始化驱动实例。
*
* 只写 BaseAddress/IsReady，不预设图像参数（避免覆盖调用方已设定的配置）。
*
* @param  p    实例指针。
* @param  cfg  LookupConfig 返回的配置。
* @param  addr 有效地址（通常为 cfg->BaseAddress）。
*
* @return XST_SUCCESS / XST_DEVICE_NOT_FOUND / XST_FAILURE。
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

    /* 上电复位，关闭中断、清曝光位 */
    CcdController_WriteReg(p, CCDC_REG_INTR_EN, 0U);
    CcdController_WriteReg(p, CCDC_REG_INTR_STS, CCDC_INTR_ALL);

    p->IsReady = 1U;
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  寄存器读写自检。
*
* 对 R/W 寄存器做"写-读回-恢复"验证；只写寄存器（TRIGGER）不参与。
*
* @param  p 实例指针。
*
* @return XST_SUCCESS / XST_FAILURE。
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

    /* 写入已知模式并回读（避开保留/只读位；CTRL 测试值不含 bit0=exposure，
     * 避免自检误触发采集） */
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

    /* 恢复原值 */
    for (i = 0; i < 3; i++) {
        CcdController_WriteReg(p, rw_regs[i], saved[i]);
    }

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  设置图像尺寸（写 IMG_SIZE）。
******************************************************************************/
void CcdController_SetImageSize(CcdController *p, u16 w, u16 h)
{
    CcdController_WriteReg(p, CCDC_REG_IMG_SIZE,
                           ((u32)h << 16) | (u32)w);
}

/*****************************************************************************/
/**
* @brief  设置消隐/空白参数（写 BEVEL_BLANK）。
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
* @brief  设置 CDSCLK 微调延时（写 CTRL[11:5]）。
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
* @brief  设置读出模式（写 CTRL[4:3]，读-改-写保留其它位）。
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
* @brief  设置 SCLK 频率（写 CTRL[1]）。
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
* @brief  设置 mock 模式（写 CTRL[2]）。
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
* @brief  启动采集（置 exposure=1）。
*
* 启动前检查 DDR3 校准完成（STATUS[16]）；未完成返回 XST_DEVICE_BUSY。
* 用读-改-写保留 CTRL 其它位（read_mode/freq/mock/cdsclk_delay 等）。
*
* @return XST_SUCCESS / XST_DEVICE_BUSY。
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
* @brief  停止采集（清 exposure=0，下降沿启动读出）。
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
* @brief  触发帧发送（写 TRIGGER[0]=1，硬件展宽后自动清 0）。
******************************************************************************/
void CcdController_TriggerFrameSend(CcdController *p)
{
    CcdController_WriteReg(p, CCDC_REG_TRIGGER, CCDC_TRIGGER_TX_START_MASK);
}

/*****************************************************************************/
/**
* @brief  帧缓存中可读帧数（STATUS[7:0]）。
******************************************************************************/
u8 CcdController_GetFrameNum(CcdController *p)
{
    return (u8)(CcdController_ReadReg(p, CCDC_REG_STATUS) &
                CCDC_STATUS_FRAME_NUM_MASK);
}

/*****************************************************************************/
/**
* @brief  DDR3 校准是否完成（STATUS[16]）。
******************************************************************************/
u8 CcdController_IsDdrReady(CcdController *p)
{
    return (CcdController_ReadReg(p, CCDC_REG_STATUS) &
            CCDC_STATUS_DDR3_DONE_MASK) ? 1U : 0U;
}

/*****************************************************************************/
/**
* @brief  帧异常标志（STATUS[8]）。
******************************************************************************/
u8 CcdController_GetException(CcdController *p)
{
    return (CcdController_ReadReg(p, CCDC_REG_STATUS) &
            CCDC_STATUS_EXCEPTION_MASK) ? 1U : 0U;
}

/*****************************************************************************/
/**
* @brief  帧异常累计计数（STATUS[15:9]）。
******************************************************************************/
u32 CcdController_GetExceptionCnt(CcdController *p)
{
    return (CcdController_ReadReg(p, CCDC_REG_STATUS) &
            CCDC_STATUS_EXCEPTION_CNT) >> 9;
}

/*****************************************************************************/
/**
* @brief  读 STATUS 原样值（调试用）。
******************************************************************************/
u32 CcdController_GetStatus(CcdController *p)
{
    return CcdController_ReadReg(p, CCDC_REG_STATUS);
}

/*****************************************************************************/
/**
* @brief  注册中断回调。
******************************************************************************/
void CcdController_SetHandler(CcdController *p, CcdController_Handler hdl,
                              void *ref)
{
    p->Handler = hdl;
    p->CallBackRef = ref;
}

/*****************************************************************************/
/**
* @brief  使能中断（写 INTR_EN）。
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
* @brief  关闭所有中断。
******************************************************************************/
void CcdController_IntrDisable(CcdController *p)
{
    CcdController_WriteReg(p, CCDC_REG_INTR_EN, 0U);
}

/*****************************************************************************/
/**
* @brief  ccd_controller ISR，挂 INTC。
*
* 读 INTR_STS → 按 INTR_EN 掩码 → W1C 清除 → 回调 app（最小处理）。
*
* @param ref CcdController 实例指针。
******************************************************************************/
void CcdController_InterruptHandler(void *ref)
{
    CcdController *p = (CcdController *)ref;
    u32 en = CcdController_ReadReg(p, CCDC_REG_INTR_EN) & CCDC_INTR_ALL;
    u32 pending = CcdController_ReadReg(p, CCDC_REG_INTR_STS) & en;

    if (pending != 0U) {
        /* W1C：写 1 清除 */
        CcdController_WriteReg(p, CCDC_REG_INTR_STS, pending);
        if (p->Handler != NULL) {
            p->Handler(pending, p->CallBackRef);
        }
    }
}
