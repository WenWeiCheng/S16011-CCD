/******************************************************************************
* @file ccd_controller.h
*
* 自制 IP ccd_controller（AXI4-Lite）的驱动接口。
*
* 命名刻意不以 X 开头（非 Xilinx 提供），但 API 风格与 Xilinx 驱动一致：
* Config 查找表 + 实例 + CfgInitialize + SelfTest + InterruptHandler。
* 寄存器映射见 00-docs/verilog-design/ccd_controller_ip.md。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef CCD_CONTROLLER_H
#define CCD_CONTROLLER_H

#include "xil_types.h"
#include "xstatus.h"

#ifdef __cplusplus
extern "C" {
#endif

/******************************************************************************
* 寄存器偏移与位定义（对照 ccd_controller_ip.md）
******************************************************************************/
#define CCDC_REG_CTRL           0x00U   /* R/W */
#define CCDC_REG_IMG_SIZE       0x04U   /* R/W */
#define CCDC_REG_BEVEL_BLANK    0x08U   /* R/W */
#define CCDC_REG_TRIGGER        0x0CU   /* W  */
#define CCDC_REG_STATUS         0x10U   /* R  */
#define CCDC_REG_INTR_EN        0x14U   /* R/W */
#define CCDC_REG_INTR_STS       0x18U   /* W1C */

/* CTRL[0x00] */
#define CCDC_CTRL_EXPOSURE_MASK      (1U<<0)
#define CCDC_CTRL_FREQ_SEL_MASK      (1U<<1)   /* 0=100k, 1=500k */
#define CCDC_CTRL_MOCK_MODE_MASK     (1U<<2)
#define CCDC_CTRL_READ_MODE_MASK     (0x3U<<3) /* 0=line binning, 1=image */
#define CCDC_CTRL_CDSCLK_DELAY_MASK  (0x7FU<<5)

/* IMG_SIZE[0x04] */
#define CCDC_IMG_WIDTH_MASK      0x0000FFFFU
#define CCDC_IMG_HEIGHT_MASK     0xFFFF0000U

/* BEVEL_BLANK[0x08] */
#define CCDC_BEVEL_L_MASK        (0xFU<<0)
#define CCDC_BEVEL_T_MASK        (0xFU<<4)
#define CCDC_BEVEL_R_MASK        (0xFU<<8)
#define CCDC_BEVEL_B_MASK        (0xFU<<12)
#define CCDC_BLANK_L_MASK        (0xFU<<16)
#define CCDC_BLANK_R_MASK        (0xFU<<20)

/* TRIGGER[0x0C] */
#define CCDC_TRIGGER_TX_START_MASK  (1U<<0)

/* STATUS[0x10] */
#define CCDC_STATUS_FRAME_NUM_MASK   0x000000FFU
#define CCDC_STATUS_EXCEPTION_MASK   (1U<<8)
#define CCDC_STATUS_EXCEPTION_CNT    (0x7FU<<9)
#define CCDC_STATUS_DDR3_DONE_MASK   (1U<<16)

/* INTR_EN[0x14] / INTR_STS[0x18] */
#define CCDC_INTR_EXCEPTION       (1U<<8)
#define CCDC_INTR_TX_DONE         (1U<<9)
#define CCDC_INTR_ALL             (CCDC_INTR_EXCEPTION | CCDC_INTR_TX_DONE)

/* 读出模式 */
#define CCDC_READ_MODE_LINE_BINNING  0U
#define CCDC_READ_MODE_IMAGE         1U

/* 采样频率 */
#define CCDC_FREQ_100K               0U
#define CCDC_FREQ_500K               1U

/******************************************************************************
* 类型定义
******************************************************************************/
typedef struct {
    u16 DeviceId;
    u32 BaseAddress;
    u32 IntrVecId;            /* INTC 向量号 */
} CcdController_Config;

/* 消隐/空白参数（对应 BEVEL_BLANK 寄存器） */
typedef struct {
    u8 BevelLeft;   /* [3:0]   */
    u8 BevelTop;    /* [7:4]   */
    u8 BevelRight;  /* [11:8]  */
    u8 BevelBottom; /* [15:12] */
    u8 BlankLeft;   /* [19:16] */
    u8 BlankRight;  /* [23:20] */
} CcdController_BevelBlank;

/* 中断回调：IntrMask 为 CCDC_INTR_* 组合 */
typedef void (*CcdController_Handler)(u32 IntrMask, void *CallBackRef);

typedef struct {
    CcdController_Config Config;
    u32  BaseAddress;
    u8   IsReady;
    u8   IsStarted;
    CcdController_Handler Handler;
    void *CallBackRef;
} CcdController;

/******************************************************************************
* 寄存器级访问（静态内联）
******************************************************************************/
static inline u32 CcdController_ReadReg(CcdController *p, u32 off)
{
    return *(volatile u32 *)(p->BaseAddress + off);
}

static inline void CcdController_WriteReg(CcdController *p, u32 off, u32 val)
{
    *(volatile u32 *)(p->BaseAddress + off) = val;
}

/******************************************************************************
* 初始化 / 自检
******************************************************************************/
CcdController_Config *CcdController_LookupConfig(u16 DeviceId);
int CcdController_CfgInitialize(CcdController *p, CcdController_Config *cfg,
                                u32 addr);
int CcdController_SelfTest(CcdController *p);

/******************************************************************************
* 配置语义 API（对照 IP 寄存器 0x00~0x08）
******************************************************************************/
void CcdController_SetImageSize(CcdController *p, u16 w, u16 h);
void CcdController_SetBevelBlank(CcdController *p,
                                 const CcdController_BevelBlank *bb);
void CcdController_SetCdsclkDelay(CcdController *p, u8 delay);
void CcdController_SetReadMode(CcdController *p, u8 mode);
void CcdController_SetFreqSel(CcdController *p, u8 freq);
void CcdController_SetMockMode(CcdController *p, u8 mock);

/******************************************************************************
* 采集控制语义 API
******************************************************************************/
int CcdController_StartCapture(CcdController *p);  /* 检查 ddr3_done 后置 exposure=1 */
void CcdController_StopCapture(CcdController *p);   /* 清 exposure=0（下降沿启动读出） */
void CcdController_TriggerFrameSend(CcdController *p); /* 写 TRIGGER[0]=1 */

/******************************************************************************
* 状态查询
******************************************************************************/
u8   CcdController_GetFrameNum(CcdController *p);
u8   CcdController_IsDdrReady(CcdController *p);
u8   CcdController_GetException(CcdController *p);
u32  CcdController_GetExceptionCnt(CcdController *p);
u32  CcdController_GetStatus(CcdController *p);

/******************************************************************************
* 中断
******************************************************************************/
void CcdController_SetHandler(CcdController *p, CcdController_Handler hdl,
                              void *ref);
void CcdController_IntrEnable(CcdController *p, u8 tx_done_en,
                              u8 exception_en);
void CcdController_IntrDisable(CcdController *p);
void CcdController_InterruptHandler(void *ref);

#ifdef __cplusplus
}
#endif

#endif /* CCD_CONTROLLER_H */
