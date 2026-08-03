/******************************************************************************
* @file protocol.c
*
* UART 控制协议实现：
*   - Value System：Protocol_Param 参数表（每参数一个描述结构体）
*   - 命令分发表：VERB → handler（LISTPARAMS / GETINFO / GETPARAM / SETPARAM / ACQ）
*   - 行解析：空格分隔 + 双引号包裹（\" 转义）
*   - 响应：OK <data...> / ERR <code> <message>
*
* 数字格式化/解析全部手写（itoa / 定点小数 / 浮点解析），不依赖 newlib
* printf/strtod —— newlib printf 即便只用于整数也会把完整浮点引擎（_svfprintf_r
* + _dtoa_r + malloc）拉进固件，128KB local mem 装不下。
*
* 依赖 app 驱动层（gUartDrv / gCcd / gCcdCtrl / gAdn8833 / gDac8311 / gMonitor），
* 不直接访问寄存器或 Xilinx 驱动。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/03 First release
* </pre>
******************************************************************************/
#include "protocol.h"
#include "proto_num.h"
#include "../hal/board_hal.h"
#include "../include/board_config.h"
#include "monitor.h"
#include "mb_interface.h"
#include "xil_printf.h"
#include <string.h>

#define PROTO_MAX_ARGS     4U
#define PROTO_RESP_MAX     512U   /* 响应行缓冲（TX 不受 256B RX 行限约束） */
#define PROTO_STR_MAX      32U    /* 字符串参数容量（camera_name maxlen） */

/* 错误码（对应 uart_protocol_design.md §3） */
#define PROTO_ERR_UNKNOWN_VERB   1
#define PROTO_ERR_UNKNOWN_PARAM  2
#define PROTO_ERR_INVALID_VALUE  3
#define PROTO_ERR_NOT_WRITABLE   4
#define PROTO_ERR_BUSY           5
#define PROTO_ERR_LINE_TOO_LONG  6
#define PROTO_ERR_INTERNAL       7

/* ============================================================================
 * Value System
 * ==========================================================================*/
typedef enum {
    VAL_TYPE_INT_RANGE = 0,
    VAL_TYPE_INT_COLLECTION,
    VAL_TYPE_FLOAT_RANGE,
    VAL_TYPE_FLOAT_COLLECTION,
    VAL_TYPE_STRING,
    VAL_TYPE_BOOL
} Protocol_ValType;

typedef enum {
    VAL_ACCESS_RO = 0,
    VAL_ACCESS_RW,
    VAL_ACCESS_WO
} Protocol_Access;

typedef union {
    s32   I;                  /* int_range / int_collection（索引） */
    float F;                  /* float_range */
    u8    B;                  /* bool */
    char  S[PROTO_STR_MAX];   /* string */
} Protocol_Value;

typedef struct Protocol_Param Protocol_Param;

typedef int (*Protocol_ApplyFn)(const Protocol_Param *p);  /* SETPARAM 生效→硬件 */
typedef int (*Protocol_FormatFn)(const Protocol_Param *p, char *buf, u32 cap);

struct Protocol_Param {
    const char *Name;
    Protocol_ValType Type;
    Protocol_Access  Access;
    const char *Desc;          /* 含空格，GETINFO 双引号包裹 */
    const char *Unit;
    const char *Constraint;    /* min:max:step | label,... | maxlen N | "" */
    Protocol_Value Cur;        /* 当前值（RO 参数未用） */
    Protocol_ApplyFn  Apply;
    Protocol_FormatFn Format;
};

/* ============================================================================
 * 响应行拼接器
 * ==========================================================================*/
typedef struct {
    char *Buf;
    u32 Len;
    u32 Cap;
} ProtoBuf;

static void Pb_Init(ProtoBuf *b, char *buf, u32 cap)
{
    b->Buf = buf;
    b->Len = 0U;
    b->Cap = cap;
    if (cap > 0U) buf[0] = '\0';
}

static void Pb_AppendLen(ProtoBuf *b, const char *s, u32 n)
{
    if (b->Len >= b->Cap - 1U) return;
    if (n > b->Cap - 1U - b->Len) n = b->Cap - 1U - b->Len;
    memcpy(b->Buf + b->Len, s, n);
    b->Len += n;
    b->Buf[b->Len] = '\0';
}

static void Pb_Append(ProtoBuf *b, const char *s)
{
    Pb_AppendLen(b, s, (u32)strlen(s));
}

static void Pb_AppendInt(ProtoBuf *b, s32 v)
{
    char tmp[12];
    Pb_AppendLen(b, tmp, Proto_Itoa(tmp, v));
}

static void Pb_AppendFloat(ProtoBuf *b, float v, int dec)
{
    char tmp[40];
    Proto_FmtFloat(tmp, sizeof tmp, v, dec);
    Pb_Append(b, tmp);
}

/* ============================================================================
 * 前向声明
 * ==========================================================================*/
static Protocol_Param *Proto_FindParam(const char *name);
static int  Cmd_ListParams(int argc, char **argv);
static int  Cmd_GetInfo(int argc, char **argv);
static int  Cmd_GetParam(int argc, char **argv);
static int  Cmd_SetParam(int argc, char **argv);
static int  Cmd_Acq(int argc, char **argv);

/* ============================================================================
 * 参数表（"新参数只需加一行"）
 * ==========================================================================*/
static Protocol_Param g_params[] = {
    /* ---- 曝光 / 图像 ---- */
    { "exposure_time_us", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "exposure time in us", "us",
      "100:10000:100", { .I = 1000 }, NULL, NULL },
    { "read_mode", VAL_TYPE_INT_COLLECTION, VAL_ACCESS_RW, "readout mode", "",
      "line_binning,image", { .I = CCDC_READ_MODE_LINE_BINNING }, NULL, NULL },
    { "freq_sel", VAL_TYPE_INT_COLLECTION, VAL_ACCESS_RW, "SCLK frequency", "",
      "100k,500k", { .I = CCDC_FREQ_100K }, NULL, NULL },
    { "mock_mode", VAL_TYPE_BOOL, VAL_ACCESS_RW, "mock ADC output virtual pixels", "",
      "", { .B = 0 }, NULL, NULL },
    { "cdsclk_delay", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "CDSCLK fine delay", "clk",
      "0:127:1", { .I = 0 }, NULL, NULL },
    { "image_width", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "image width", "px",
      "1:2048:1", { .I = CCD_IMG_WIDTH_DEFAULT }, NULL, NULL },
    { "image_height", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "image height", "px",
      "1:64:1", { .I = CCD_IMG_HEIGHT_DEFAULT }, NULL, NULL },
    { "bevel_left", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "left bevel pixels", "px",
      "0:15:1", { .I = CCD_BEVEL_L_DEFAULT }, NULL, NULL },
    { "bevel_top", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "top bevel pixels", "px",
      "0:15:1", { .I = CCD_BEVEL_T_DEFAULT }, NULL, NULL },
    { "bevel_right", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "right bevel pixels", "px",
      "0:15:1", { .I = CCD_BEVEL_R_DEFAULT }, NULL, NULL },
    { "bevel_bottom", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "bottom bevel pixels", "px",
      "0:15:1", { .I = CCD_BEVEL_B_DEFAULT }, NULL, NULL },
    { "blank_left", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "left blank pixels", "px",
      "0:15:1", { .I = CCD_BLANK_L_DEFAULT }, NULL, NULL },
    { "blank_right", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "right blank pixels", "px",
      "0:15:1", { .I = CCD_BLANK_R_DEFAULT }, NULL, NULL },
    /* ---- TEC ---- */
    { "tec_enable", VAL_TYPE_BOOL, VAL_ACCESS_RW, "TEC cooling enable", "",
      "", { .B = 0 }, NULL, NULL },
    { "tec_voltage_set", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RW, "TEC output voltage set", "V",
      "0:2.500:0.001", { .F = 0.0f }, NULL, NULL },
    /* ---- 遥测（RO） ---- */
    { "sensor_temp", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "CCD sensor NTC temperature", "degC",
      "0:80:0.1", { .F = 0.0f }, NULL, NULL },
    { "environment_temp", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "environment NTC temperature", "degC",
      "0:80:0.1", { .F = 0.0f }, NULL, NULL },
    { "tec_voltage", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "TEC output voltage monitor", "V",
      "0:4.096:0.001", { .F = 0.0f }, NULL, NULL },
    { "tec_current", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "TEC output current monitor", "A",
      "0:10:0.001", { .F = 0.0f }, NULL, NULL },
    /* ---- 系统 ---- */
    { "camera_name", VAL_TYPE_STRING, VAL_ACCESS_RW, "camera name", "",
      "maxlen 32", { .S = "ccd" }, NULL, NULL },
    { "acq_state", VAL_TYPE_INT_COLLECTION, VAL_ACCESS_RO, "acquisition state", "",
      "idle,exposing,reading,tx", { .I = 0 }, NULL, NULL },
    { "frame_num_ready", VAL_TYPE_INT_RANGE, VAL_ACCESS_RO, "frames ready in cache", "",
      "0:8:1", { .I = 0 }, NULL, NULL },
};
#define PROTO_NUM_PARAMS  (sizeof g_params / sizeof g_params[0])

/* ============================================================================
 * 命令分发表（"新命令只需加一行"）
 * ==========================================================================*/
typedef int (*Proto_CmdHandler)(int argc, char **argv);
typedef struct {
    const char *Verb;
    Proto_CmdHandler Handler;
} Proto_Cmd;

static const Proto_Cmd g_cmds[] = {
    { "LISTPARAMS", Cmd_ListParams },
    { "GETINFO",    Cmd_GetInfo },
    { "GETPARAM",   Cmd_GetParam },
    { "SETPARAM",   Cmd_SetParam },
    { "ACQ",        Cmd_Acq },
};
#define PROTO_NUM_CMDS  (sizeof g_cmds / sizeof g_cmds[0])

/* ============================================================================
 * 响应输出
 * ==========================================================================*/
static void Proto_Reply(const char *line)
{
    Uart_SendLine(&gUartDrv, line);
}

/* OK（无数据） */
static void Proto_Ok0(void)
{
    Proto_Reply("OK");
}

/* ERR <code> <msg> */
static void Proto_Err(int code, const char *msg)
{
    char line[PROTO_RESP_MAX];
    ProtoBuf b;

    Pb_Init(&b, line, sizeof line);
    Pb_Append(&b, "ERR ");
    Pb_AppendInt(&b, (s32)code);
    Pb_Append(&b, " ");
    Pb_Append(&b, msg);
    Proto_Reply(line);
}

/* ============================================================================
 * 约束 / 集合工具
 * ==========================================================================*/
static const char *Proto_TypeName(Protocol_ValType t)
{
    static const char *const names[] = {
        "int_range", "int_collection", "float_range", "float_collection",
        "string", "bool"
    };
    if ((u32)t >= (sizeof names / sizeof names[0])) {
        return "?";
    }
    return names[t];
}

static const char *Proto_AccessName(Protocol_Access a)
{
    static const char *const names[] = { "RO", "RW", "WO" };
    if ((u32)a >= 3U) {
        return "?";
    }
    return names[a];
}

/* ============================================================================
 * 参数解析 + 校验（SETPARAM）
 * ==========================================================================*/
static int Proto_ParseValue(const Protocol_Param *p, const char *tok,
                            Protocol_Value *v)
{
    long mn, mx, st;
    float fmn, fmx, fst;
    s32 iv;
    float fv;
    u32 maxlen;

    switch (p->Type) {
    case VAL_TYPE_INT_RANGE:
        if (Proto_ParseIntConstraint(p->Constraint, &mn, &mx, &st) != 0) return -1;
        if (Proto_ParseInt(tok, &iv) != 0) return -1;
        if (iv < mn || iv > mx) return -1;
        if (st > 1 && ((iv - mn) % st) != 0) return -1;
        v->I = iv;
        return 0;
    case VAL_TYPE_INT_COLLECTION:
        if (Proto_ParseColl(p->Constraint, tok, &v->I) != 0) return -1;
        return 0;
    case VAL_TYPE_FLOAT_RANGE:
        if (Proto_ParseFloatConstraint(p->Constraint, &fmn, &fmx, &fst) != 0) return -1;
        if (Proto_ParseFloat(tok, &fv) != 0) return -1;
        if (fv < fmn || fv > fmx) return -1;
        v->F = fv;
        return 0;
    case VAL_TYPE_FLOAT_COLLECTION:
        return -1;   /* 本协议暂未使用 */
    case VAL_TYPE_BOOL:
        if (strcmp(tok, "0") == 0 || strcmp(tok, "off") == 0 ||
            strcmp(tok, "false") == 0) { v->B = 0U; return 0; }
        if (strcmp(tok, "1") == 0 || strcmp(tok, "on") == 0 ||
            strcmp(tok, "true") == 0) { v->B = 1U; return 0; }
        return -1;
    case VAL_TYPE_STRING:
        maxlen = PROTO_STR_MAX - 1U;
        if (strncmp(p->Constraint, "maxlen", 6U) == 0) {
            u32 ml;
            if (Proto_ParseUInt(p->Constraint + 6, &ml) == 0) {
                maxlen = ml;
            }
            if (maxlen > PROTO_STR_MAX - 1U) maxlen = PROTO_STR_MAX - 1U;
        }
        if (strlen(tok) > maxlen) return -1;
        strncpy(v->S, tok, maxlen);
        v->S[maxlen] = '\0';
        return 0;
    default:
        return -1;
    }
}

/* ============================================================================
 * 生效回调（Apply）：把参数当前值写入硬件
 * ==========================================================================*/
static int Apply_ReadMode(const Protocol_Param *p)
{
    CcdController_SetReadMode(&gCcdCtrl, (u8)p->Cur.I);
    return 0;
}

static int Apply_FreqSel(const Protocol_Param *p)
{
    CcdController_SetFreqSel(&gCcdCtrl, (u8)p->Cur.I);
    return 0;
}

static int Apply_MockMode(const Protocol_Param *p)
{
    CcdController_SetMockMode(&gCcdCtrl, p->Cur.B);
    return 0;
}

static int Apply_CdsclkDelay(const Protocol_Param *p)
{
    CcdController_SetCdsclkDelay(&gCcdCtrl, (u8)p->Cur.I);
    return 0;
}

static int Apply_ImageSize(const Protocol_Param *p)
{
    Protocol_Param *w, *h;

    (void)p;
    w = Proto_FindParam("image_width");
    h = Proto_FindParam("image_height");
    CcdController_SetImageSize(&gCcdCtrl, (u16)w->Cur.I, (u16)h->Cur.I);
    return 0;
}

static int Apply_BevelBlank(const Protocol_Param *p)
{
    CcdController_BevelBlank bb;

    (void)p;
    bb.BevelLeft   = (u8)Proto_FindParam("bevel_left")->Cur.I;
    bb.BevelTop    = (u8)Proto_FindParam("bevel_top")->Cur.I;
    bb.BevelRight  = (u8)Proto_FindParam("bevel_right")->Cur.I;
    bb.BevelBottom = (u8)Proto_FindParam("bevel_bottom")->Cur.I;
    bb.BlankLeft   = (u8)Proto_FindParam("blank_left")->Cur.I;
    bb.BlankRight  = (u8)Proto_FindParam("blank_right")->Cur.I;
    CcdController_SetBevelBlank(&gCcdCtrl, &bb);
    return 0;
}

static int Apply_TecEnable(const Protocol_Param *p)
{
    Adn8833_SetEnable(&gAdn8833, p->Cur.B);
    return 0;
}

static int Apply_TecVoltage(const Protocol_Param *p)
{
    return (Dac8311_SetVoltage(&gDac8311, p->Cur.F) == XST_SUCCESS) ? 0 : -1;
}

/* ============================================================================
 * 序列化回调（Format）：把当前值 / 实时值写为协议字符串
 * ==========================================================================*/
static int Fmt_Int(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    Pb_Init(&b, buf, cap);
    Pb_AppendInt(&b, p->Cur.I);
    return (int)b.Len;
}

static int Fmt_Coll(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    char label[PROTO_STR_MAX];

    Pb_Init(&b, buf, cap);
    if (Proto_CollLabel(p->Constraint, (u32)p->Cur.I, label, sizeof label) != 0) {
        Pb_Append(&b, "?");
    } else {
        Pb_Append(&b, label);
    }
    return (int)b.Len;
}

static int Fmt_Bool(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    Pb_Init(&b, buf, cap);
    Pb_Append(&b, p->Cur.B ? "1" : "0");
    return (int)b.Len;
}

static int Fmt_String(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    Pb_Init(&b, buf, cap);
    Pb_Append(&b, "\"");
    Pb_Append(&b, p->Cur.S);
    Pb_Append(&b, "\"");
    return (int)b.Len;
}

static int Fmt_Float(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    int dec = Proto_StepDecimals(p->Constraint);
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b, p->Cur.F, dec);
    return (int)b.Len;
}

/* ---- RO 参数：实时取 monitor / ccd ---- */
static int Fmt_SensorTemp(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b, Monitor_GetNtcTemp(&gMonitor, ADS1118_MUX_SENSOR_NTC), 1);
    return (int)b.Len;
}

static int Fmt_EnvTemp(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b, Monitor_GetNtcTemp(&gMonitor, ADS1118_MUX_ENV_NTC), 1);
    return (int)b.Len;
}

static int Fmt_TecVoltage(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b, Monitor_GetVoltage(&gMonitor, ADS1118_MUX_TEC_V), 3);
    return (int)b.Len;
}

static int Fmt_TecCurrent(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b,
                   Monitor_GetVoltage(&gMonitor, ADS1118_MUX_TEC_I) * TEC_I_A_PER_V,
                   3);
    return (int)b.Len;
}

static int Fmt_AcqState(const Protocol_Param *p, char *buf, u32 cap)
{
    static const char *const states[] = { "idle", "exposing", "reading", "tx" };
    ProtoBuf b;
    u32 idx = (u32)gCcd.State;
    (void)p;
    if (idx >= (sizeof states / sizeof states[0])) idx = 0U;
    Pb_Init(&b, buf, cap);
    Pb_Append(&b, states[idx]);
    return (int)b.Len;
}

static int Fmt_FrameNum(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendInt(&b, (s32)Ccd_GetFrameNum(&gCcd));
    return (int)b.Len;
}

/* 给各参数挂上 Apply / Format（集中赋值，避免初始化列表过长） */
static void Proto_BindHandlers(void)
{
    g_params[0].Format = Fmt_Int;                /* exposure_time_us */
    g_params[1].Apply  = Apply_ReadMode;   g_params[1].Format = Fmt_Coll;
    g_params[2].Apply  = Apply_FreqSel;    g_params[2].Format = Fmt_Coll;
    g_params[3].Apply  = Apply_MockMode;   g_params[3].Format = Fmt_Bool;
    g_params[4].Apply  = Apply_CdsclkDelay;g_params[4].Format = Fmt_Int;
    g_params[5].Apply  = Apply_ImageSize;  g_params[5].Format = Fmt_Int;
    g_params[6].Apply  = Apply_ImageSize;  g_params[6].Format = Fmt_Int;
    g_params[7].Apply  = Apply_BevelBlank; g_params[7].Format = Fmt_Int;
    g_params[8].Apply  = Apply_BevelBlank; g_params[8].Format = Fmt_Int;
    g_params[9].Apply  = Apply_BevelBlank; g_params[9].Format = Fmt_Int;
    g_params[10].Apply = Apply_BevelBlank; g_params[10].Format = Fmt_Int;
    g_params[11].Apply = Apply_BevelBlank; g_params[11].Format = Fmt_Int;
    g_params[12].Apply = Apply_BevelBlank; g_params[12].Format = Fmt_Int;
    g_params[13].Apply = Apply_TecEnable;  g_params[13].Format = Fmt_Bool;
    g_params[14].Apply = Apply_TecVoltage; g_params[14].Format = Fmt_Float;
    g_params[15].Format = Fmt_SensorTemp;
    g_params[16].Format = Fmt_EnvTemp;
    g_params[17].Format = Fmt_TecVoltage;
    g_params[18].Format = Fmt_TecCurrent;
    g_params[19].Format = Fmt_String;
    g_params[20].Format = Fmt_AcqState;
    g_params[21].Format = Fmt_FrameNum;
}

/* ============================================================================
 * 参数查找
 * ==========================================================================*/
static Protocol_Param *Proto_FindParam(const char *name)
{
    u32 i;
    for (i = 0; i < PROTO_NUM_PARAMS; i++) {
        if (strcmp(g_params[i].Name, name) == 0) {
            return &g_params[i];
        }
    }
    return NULL;
}

/* ============================================================================
 * 命令处理
 * ==========================================================================*/
static int Cmd_ListParams(int argc, char **argv)
{
    const char *group = (argc >= 2) ? argv[1] : NULL;
    char line[PROTO_RESP_MAX];
    ProtoBuf b;
    u32 i;
    int first = 1;

    Pb_Init(&b, line, sizeof line);
    for (i = 0; i < PROTO_NUM_PARAMS; i++) {
        if (group != NULL && !Proto_MatchGroup(g_params[i].Name, group)) {
            continue;
        }
        Pb_Append(&b, first ? "OK " : ",");
        Pb_Append(&b, g_params[i].Name);
        first = 0;
    }
    if (first) {
        Pb_Append(&b, "OK");
    }
    Proto_Reply(line);
    return 0;
}

static int Cmd_GetInfo(int argc, char **argv)
{
    const Protocol_Param *p;
    char line[PROTO_RESP_MAX];
    ProtoBuf b;

    if (argc < 2) { Proto_Err(PROTO_ERR_UNKNOWN_PARAM, "missing param"); return 0; }
    p = Proto_FindParam(argv[1]);
    if (p == NULL) { Proto_Err(PROTO_ERR_UNKNOWN_PARAM, "unknown param"); return 0; }

    Pb_Init(&b, line, sizeof line);
    Pb_Append(&b, "OK ");
    Pb_Append(&b, p->Name);
    Pb_Append(&b, " ");
    Pb_Append(&b, Proto_TypeName(p->Type));
    Pb_Append(&b, " ");
    Pb_Append(&b, Proto_AccessName(p->Access));
    Pb_Append(&b, " \"");
    Pb_Append(&b, p->Desc);
    Pb_Append(&b, "\" ");
    Pb_Append(&b, p->Unit);
    Pb_Append(&b, " ");
    Pb_Append(&b, p->Constraint);
    Proto_Reply(line);
    return 0;
}

static int Cmd_GetParam(int argc, char **argv)
{
    const Protocol_Param *p;
    char vbuf[128];
    char line[PROTO_RESP_MAX];
    ProtoBuf b;

    if (argc < 2) { Proto_Err(PROTO_ERR_UNKNOWN_PARAM, "missing param"); return 0; }
    p = Proto_FindParam(argv[1]);
    if (p == NULL) { Proto_Err(PROTO_ERR_UNKNOWN_PARAM, "unknown param"); return 0; }

    if (p->Format != NULL) {
        p->Format(p, vbuf, sizeof vbuf);
    } else {
        vbuf[0] = '0';
        vbuf[1] = '\0';
    }
    Pb_Init(&b, line, sizeof line);
    Pb_Append(&b, "OK ");
    Pb_Append(&b, p->Name);
    Pb_Append(&b, " ");
    Pb_Append(&b, vbuf);
    Proto_Reply(line);
    return 0;
}

static int Cmd_SetParam(int argc, char **argv)
{
    Protocol_Param *p;
    Protocol_Value v;
    char msg[PROTO_RESP_MAX];
    ProtoBuf b;

    if (argc < 3) { Proto_Err(PROTO_ERR_INVALID_VALUE, "missing value"); return 0; }
    p = Proto_FindParam(argv[1]);
    if (p == NULL) { Proto_Err(PROTO_ERR_UNKNOWN_PARAM, "unknown param"); return 0; }
    if (p->Access != VAL_ACCESS_RW && p->Access != VAL_ACCESS_WO) {
        Proto_Err(PROTO_ERR_NOT_WRITABLE, "not writable");
        return 0;
    }
    if (Proto_ParseValue(p, argv[2], &v) != 0) {
        Pb_Init(&b, msg, sizeof msg);
        Pb_Append(&b, "invalid value range ");
        Pb_Append(&b, p->Constraint);
        Proto_Err(PROTO_ERR_INVALID_VALUE, msg);
        return 0;
    }
    p->Cur = v;
    if (p->Apply != NULL && p->Apply(p) != 0) {
        Proto_Err(PROTO_ERR_INTERNAL, "apply failed");
        return 0;
    }
    Proto_Ok0();
    return 0;
}

static int Cmd_Acq(int argc, char **argv)
{
    const Protocol_Param *pt;

    if (argc < 2) { Proto_Err(PROTO_ERR_INVALID_VALUE, "missing mode"); return 0; }

    if (strcmp(argv[1], "abort") == 0) {
        Ccd_Stop(&gCcd);
        Proto_Ok0();
        return 0;
    }

    if (strcmp(argv[1], "single") == 0 || strcmp(argv[1], "live") == 0) {
        CcdMode mode = (argv[1][0] == 'l') ? CCD_MODE_LIVE : CCD_MODE_SINGLE;
        u64 us;
        int st;

        pt = Proto_FindParam("exposure_time_us");
        us = (u64)((pt != NULL) ? pt->Cur.I : 1000L);
        st = Ccd_StartCapture(&gCcd, mode, us);
        if (st == XST_DEVICE_BUSY) { Proto_Err(PROTO_ERR_BUSY, "busy"); return 0; }
        if (st != XST_SUCCESS)     { Proto_Err(PROTO_ERR_INTERNAL, "acq start failed"); return 0; }
        Proto_Ok0();
        return 0;
    }

    Proto_Err(PROTO_ERR_INVALID_VALUE, "invalid mode (single|live|abort)");
    return 0;
}

/* ============================================================================
 * 行解析（空格 + 双引号，\" 转义）
 * ==========================================================================*/
static char *Proto_CopyEscaped(char *src)
{
    char *dst = src;

    while (*src != '\0' && *src != '"') {
        if (*src == '\\' && src[1] == '"') {
            *dst++ = '"';
            src += 2;
        } else {
            *dst++ = *src++;
        }
    }
    *dst = '\0';
    return src;
}

static int Proto_Tokenize(char *line, char **argv, u32 max)
{
    u32 argc = 0U;
    char *p = line;

    while (*p != '\0') {
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '\0') break;
        if (argc >= max) return -1;

        if (*p == '"') {
            p++;
            argv[argc] = p;
            p = Proto_CopyEscaped(p);
            if (*p == '"') *p++ = '\0';
        } else {
            argv[argc] = p;
            while (*p != '\0' && *p != ' ' && *p != '\t') p++;
            if (*p != '\0') *p++ = '\0';
        }
        argc++;
    }
    return (int)argc;
}

/* 分发命令 */
static void Proto_Dispatch(char *line)
{
    char *argv[PROTO_MAX_ARGS];
    int argc;
    u32 i;

    argc = Proto_Tokenize(line, argv, PROTO_MAX_ARGS);
    if (argc <= 0) return;

    for (i = 0; i < PROTO_NUM_CMDS; i++) {
        if (strcmp(argv[0], g_cmds[i].Verb) == 0) {
            g_cmds[i].Handler(argc, argv);
            return;
        }
    }
    Proto_Err(PROTO_ERR_UNKNOWN_VERB, "unknown verb");
}

/* ============================================================================
 * ISR → main 循环的 pending 通道
 * ==========================================================================*/
static volatile u8 gLinePending;
static volatile u8 gLineTooLong;
static char gPendingLine[UART_LINE_MAX];

/*****************************************************************************/
/**
* @brief  UART 收到完整行（ISR 上下文）：拷入 pending 缓冲并置标志。
******************************************************************************/
void Protocol_OnLine(const char *line, void *ref)
{
    u32 n;

    (void)ref;
    n = (u32)strlen(line);
    if (n >= sizeof gPendingLine) n = sizeof gPendingLine - 1U;
    memcpy(gPendingLine, line, n);
    gPendingLine[n] = '\0';
    gLinePending = 1;
}

/*****************************************************************************/
/**
* @brief  UART 错误回调（ISR 上下文）：超长行置标志，主循环回 ERR 6。
******************************************************************************/
void Protocol_OnError(UartError err, void *ref)
{
    (void)ref;
    if (err == UART_ERR_LINE_TOO_LONG) {
        gLineTooLong = 1;
    }
}

/*****************************************************************************/
/**
* @brief  主循环轮询：处理待发送的 ERR 6 与待分发的命令行。
******************************************************************************/
void Protocol_ProcessPending(void)
{
    char line[UART_LINE_MAX];

    if (gLineTooLong) {
        gLineTooLong = 0;
        Proto_Err(PROTO_ERR_LINE_TOO_LONG, "line too long");
    }

    if (gLinePending == 0) return;

    /* 临界区拷出，避免 ISR 覆盖 */
    microblaze_disable_interrupts();
    memcpy(line, gPendingLine, sizeof line);
    gLinePending = 0;
    microblaze_enable_interrupts();

    Proto_Dispatch(line);
}

/*****************************************************************************/
/**
* @brief  协议初始化：绑定 Apply/Format，应用参数默认值到硬件，打印 READY。
******************************************************************************/
int Protocol_Init(void)
{
    u32 i;

    Proto_BindHandlers();

    for (i = 0; i < PROTO_NUM_PARAMS; i++) {
        Protocol_Param *p = &g_params[i];
        if (p->Apply != NULL && p->Apply(p) != 0) {
            xil_printf("[proto] init apply '%s' failed\r\n", p->Name);
        }
    }

    Proto_Reply("READY");
    return XST_SUCCESS;
}
