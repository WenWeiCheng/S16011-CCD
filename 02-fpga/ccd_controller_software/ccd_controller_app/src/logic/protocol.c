/******************************************************************************
* @file protocol.c
*
* UART control protocol implementation:
*   - Value System: Protocol_Param parameter table (one descriptor struct per parameter)
*   - Command dispatch table: VERB -> handler (LISTPARAMS / GETINFO / GETPARAM / SETPARAM / ACQ)
*   - Line parsing: space separated + double quotes ("\"" escaping)
*   - Response: OK <data...> / ERR <code> <message>
*
* Number formatting/parsing is all hand-written (itoa / fixed-point decimals / float
* parsing), not depending on newlib printf/strtod -- newlib printf pulls in the complete
* floating-point engine (_svfprintf_r + _dtoa_r + malloc) even when used only for integers,
* which does not fit in the 128KB local mem.
*
* Depends on the app driver layer (gUartDrv / gCcd / gCcdCtrl / gMonitor) and the
* TEC control loop (gTecCtrl); does not access registers or Xilinx drivers directly.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/03 First release
* 1.1   wwc  26/08/03 Complete function doc comments (Xilinx style)
* 1.2   wwc  26/08/03 Reply ERR on token overflow / empty line (never drop silently)
 * 1.3   wwc  26/08/04 TEC: PID params (tec_set_temp/kp/ki/kd) replace tec_voltage_set,
 *                      RO tec_voltage/current now apply the ADN8833 monitor conversions
 * 1.4   wwc  26/08/04 Verb dispatch case-insensitive (debug convenience)
 * 1.5   wwc  26/08/07 ACQ 新增 burst N (连续采 N 帧入缓存) 与 fetch N (发送 N 帧)
 *                     子命令; 帧发送改由主机 fetch 驱动
 * 1.6   wwc  26/08/07 acq_state 改三值 (idle,exposing,reading): 帧发送为正交
 *                     维度, 不再体现在采集状态机中
 * 1.7   wwc  26/08/07 ACQ 三命令统一走 Ccd_Start(d,n,us) (burst 首次获得显式
 *                     曝光); 新增 RO frame_capacity (最大缓存帧数)
 * 1.8   wwc  26/08/07 新增 RO exception_flag / exception_cnt (帧异常标志与
 *                     累计计数, 源自 STATUS[8]/[15:9])
 * </pre>
******************************************************************************/
#include "protocol.h"
#include "proto_num.h"
#include "../hal/board_hal.h"
#include "../include/board_config.h"
#include "monitor.h"
#include "tec.h"
#include "tec_ctrl.h"
#include "mb_interface.h"
#include "xil_printf.h"
#include <string.h>

#define PROTO_MAX_ARGS     4U
#define PROTO_RESP_MAX     512U   /* response line buffer (TX not bound by the 256B RX line limit) */
#define PROTO_STR_MAX      32U    /* string parameter capacity (camera_name maxlen) */

/* Error codes (correspond to uart_protocol_design.md sec. 3) */
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
/** Parameter value type: selects how the value is parsed (SETPARAM) and formatted (GETPARAM). */
typedef enum {
    VAL_TYPE_INT_RANGE = 0,    /* integer bounded by min:max:step */
    VAL_TYPE_ENUM,             /* integer index into a label list */
    VAL_TYPE_FLOAT_RANGE,      /* float bounded by min:max:step */
    VAL_TYPE_STRING,           /* NUL-terminated string */
    VAL_TYPE_BOOL              /* boolean (0/off/false, 1/on/true) */
} Protocol_ValType;

/** Parameter access rights, enforced by SETPARAM. */
typedef enum {
    VAL_ACCESS_RO = 0,   /* read-only: no Apply, only Format */
    VAL_ACCESS_RW,       /* read-write */
    VAL_ACCESS_WO        /* write-only */
} Protocol_Access;

/**
* Storage for a parameter's current/live value. Only one member is meaningful,
* selected by Type (I for int, F for float, B for bool, S for string).
*/
typedef union {
    s32   I;                  /* int_range / enum (index) */
    float F;                  /* float_range */
    u8    B;                  /* bool */
    char  S[PROTO_STR_MAX];   /* string */
} Protocol_Value;

typedef struct Protocol_Param Protocol_Param;

/**
* SETPARAM take-effect callback: writes p->Cur to hardware. Return 0 on success,
* nonzero on failure (SETPARAM replies ERR 7 / init prints a warning).
*/
typedef int (*Protocol_ApplyFn)(const Protocol_Param *p);

/**
* GETPARAM serialize callback: writes the current/live value as a protocol string
* into buf (capacity cap), NUL-terminated. Returns the number of bytes written.
*/
typedef int (*Protocol_FormatFn)(const Protocol_Param *p, char *buf, u32 cap);

/** One entry of the parameter table; defines a settable/queryable protocol parameter. */
struct Protocol_Param {
    const char *Name;          /* protocol keyword (ASCII, no spaces) */
    Protocol_ValType Type;     /* selects parsing/formatting rules */
    Protocol_Access  Access;   /* RO/RW/WO */
    const char *Desc;          /* human description, wrapped in double quotes by GETINFO */
    const char *Unit;          /* e.g. "us", "px", "V"; empty if none */
    const char *Constraint;    /* "min:max:step" | "label,..." | "maxlen N" | "" */
    Protocol_Value Cur;        /* current value (unused for RO params) */
    Protocol_ApplyFn  Apply;   /* write p->Cur to hardware; NULL for RO params */
    Protocol_FormatFn Format;  /* serialize current/live value; NULL -> GETPARAM returns 0 */
};

/* ============================================================================
 * Response line builder
 * ==========================================================================*/
/**
* Bounded response-line buffer. Writes never overflow: appends past the end are
* silently truncated, keeping the buffer NUL-terminated.
*/
typedef struct {
    char *Buf;   /* destination buffer (caller-provided) */
    u32 Len;     /* bytes written so far */
    u32 Cap;     /* buffer capacity in bytes */
} ProtoBuf;

/*****************************************************************************/
/**
* @brief  Binds a caller-provided buffer to a ProtoBuf and resets it to an empty string.
*
* @param  b    ProtoBuf to bind.
* @param  buf  Destination buffer (caller-provided).
* @param  cap  Buffer capacity in bytes.
******************************************************************************/
static void Pb_Init(ProtoBuf *b, char *buf, u32 cap)
{
    b->Buf = buf;
    b->Len = 0U;
    b->Cap = cap;
    if (cap > 0U) buf[0] = '\0';
}

/*****************************************************************************/
/**
* @brief  Appends the first n bytes of s.
*
* Silently truncates if the buffer is full or the chunk would overflow, keeping the
* result NUL-terminated.
*
* @param  b  ProtoBuf to append to.
* @param  s  Source data.
* @param  n  Number of bytes to append.
******************************************************************************/
static void Pb_AppendLen(ProtoBuf *b, const char *s, u32 n)
{
    if (b->Len >= b->Cap - 1U) return;
    if (n > b->Cap - 1U - b->Len) n = b->Cap - 1U - b->Len;
    memcpy(b->Buf + b->Len, s, n);
    b->Len += n;
    b->Buf[b->Len] = '\0';
}

/*****************************************************************************/
/**
* @brief  Appends a whole NUL-terminated string.
*
* @param  b  ProtoBuf to append to.
* @param  s  NUL-terminated string to append.
******************************************************************************/
static void Pb_Append(ProtoBuf *b, const char *s)
{
    Pb_AppendLen(b, s, (u32)strlen(s));
}

/*****************************************************************************/
/**
* @brief  Appends a signed integer (hand-written itoa; snprintf would pull in newlib printf).
*
* @param  b  ProtoBuf to append to.
* @param  v  Signed integer value.
******************************************************************************/
static void Pb_AppendInt(ProtoBuf *b, s32 v)
{
    char tmp[12];
    Pb_AppendLen(b, tmp, Proto_Itoa(tmp, v));
}

/*****************************************************************************/
/**
* @brief  Appends a float with dec fixed decimals (hand-written formatting).
*
* @param  b    ProtoBuf to append to.
* @param  v    Float value.
* @param  dec  Number of decimal places.
******************************************************************************/
static void Pb_AppendFloat(ProtoBuf *b, float v, int dec)
{
    char tmp[40];
    Proto_FmtFloat(tmp, sizeof tmp, v, dec);
    Pb_Append(b, tmp);
}

/* ============================================================================
 * Forward declarations
 * ==========================================================================*/
static Protocol_Param *Proto_FindParam(const char *name);
static int  Cmd_ListParams(int argc, char **argv);
static int  Cmd_GetInfo(int argc, char **argv);
static int  Cmd_GetParam(int argc, char **argv);
static int  Cmd_SetParam(int argc, char **argv);
static int  Cmd_Acq(int argc, char **argv);

/* ============================================================================
 * Parameter table ("add a new parameter with just one line")
 * ==========================================================================*/
static Protocol_Param g_params[] = {
    /* ---- exposure / image ---- */
    { "exposure_time_us", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "exposure time in us", "us",
      "100:10000:100", { .I = 1000 }, NULL, NULL },
    { "read_mode", VAL_TYPE_ENUM, VAL_ACCESS_RW, "readout mode", "",
      "line_binning,image", { .I = CCDC_READ_MODE_LINE_BINNING }, NULL, NULL },
    { "freq_sel", VAL_TYPE_ENUM, VAL_ACCESS_RW, "SCLK frequency", "",
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
    /* ---- TEC (temperature PID control) ---- */
    { "tec_enable", VAL_TYPE_BOOL, VAL_ACCESS_RW, "TEC power enable", "",
      "", { .B = 0 }, NULL, NULL },
    { "tec_set_temp", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RW, "sensor temperature setpoint", "degC",
      "-80:30:0.1", { .F = 25.0f }, NULL, NULL },
    { "tec_kp", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RW, "TEC PID proportional gain", "V/degC",
      "0:10:0.001", { .F = 0.5f }, NULL, NULL },
    { "tec_ki", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RW, "TEC PID integral gain", "1/s",
      "0:5:0.001", { .F = 0.1f }, NULL, NULL },
    { "tec_kd", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RW, "TEC PID derivative gain", "s",
      "0:5:0.001", { .F = 0.0f }, NULL, NULL },
    /* ---- telemetry (RO) ---- */
    { "sensor_temp", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "CCD sensor NTC temperature", "degC",
      "0:80:0.1", { .F = 0.0f }, NULL, NULL },
    { "environment_temp", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "environment NTC temperature", "degC",
      "0:80:0.1", { .F = 0.0f }, NULL, NULL },
    { "tec_voltage", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "TEC output voltage monitor", "V",
      "-3.3:3.3:0.001", { .F = 0.0f }, NULL, NULL },
    { "tec_current", VAL_TYPE_FLOAT_RANGE, VAL_ACCESS_RO, "TEC output current monitor", "A",
      "-1.1:1.1:0.001", { .F = 0.0f }, NULL, NULL },
    /* ---- system ---- */
    { "camera_name", VAL_TYPE_STRING, VAL_ACCESS_RW, "camera name", "",
      "maxlen 32", { .S = "ccd" }, NULL, NULL },
    { "acq_state", VAL_TYPE_ENUM, VAL_ACCESS_RO, "acquisition state", "",
      "idle,exposing,reading", { .I = 0 }, NULL, NULL },
    /* frame_num_ready / frame_capacity 上限须与 CCD_MAX_FRAMES (BD MAX_FRAMES) 一致 */
    { "frame_num_ready", VAL_TYPE_INT_RANGE, VAL_ACCESS_RO, "frames ready in cache", "",
      "0:2000:1", { .I = 0 }, NULL, NULL },
    { "frame_capacity", VAL_TYPE_INT_RANGE, VAL_ACCESS_RO, "max frames cache capacity", "",
      "0:2000:1", { .I = 0 }, NULL, NULL },
    { "exception_flag", VAL_TYPE_BOOL, VAL_ACCESS_RO, "frame exception level flag", "",
      "", { .B = 0 }, NULL, NULL },
    { "exception_cnt", VAL_TYPE_INT_RANGE, VAL_ACCESS_RO, "accumulated frame exception count", "",
      "0:127:1", { .I = 0 }, NULL, NULL },
    /* ---- CCD ADC (ad9826) ---- */
    { "adc_gain_r", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "red channel PGA gain code", "",
      "0:63:1", { .I = 0 }, NULL, NULL },
    { "adc_gain_g", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "green channel PGA gain code", "",
      "0:63:1", { .I = 0 }, NULL, NULL },
    { "adc_gain_b", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "blue channel PGA gain code", "",
      "0:63:1", { .I = 0 }, NULL, NULL },
    { "adc_offset_r", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "red channel offset code (9-bit)", "",
      "0:511:1", { .I = 0 }, NULL, NULL },
    { "adc_offset_g", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "green channel offset code (9-bit)", "",
      "0:511:1", { .I = 0 }, NULL, NULL },
    { "adc_offset_b", VAL_TYPE_INT_RANGE, VAL_ACCESS_RW, "blue channel offset code (9-bit)", "",
      "0:511:1", { .I = 0 }, NULL, NULL },
};
#define PROTO_NUM_PARAMS  (sizeof g_params / sizeof g_params[0])

/* ============================================================================
 * Command dispatch table ("add a new command with just one line")
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
 * Response output
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  Sends one response line to the host UART.
*
* @param  line  NUL-terminated response line.
******************************************************************************/
static void Proto_Reply(const char *line)
{
    Uart_SendLine(&gUartDrv, line);
}

/*****************************************************************************/
/**
* @brief  Replies "OK" with no data.
******************************************************************************/
static void Proto_Ok0(void)
{
    Proto_Reply("OK");
}

/*****************************************************************************/
/**
* @brief  Replies "ERR <code> <msg>"; code is one of the PROTO_ERR_* values.
*
* @param  code  Error code (PROTO_ERR_*).
* @param  msg   Human-readable error message.
******************************************************************************/
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
 * Constraint / set utilities
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  Maps a value type to its protocol keyword ("int_range", "bool", ...).
*
* @param  t  Value type.
*
* @return Protocol keyword, or "?" if out of range.
******************************************************************************/
static const char *Proto_TypeName(Protocol_ValType t)
{
    static const char *const names[] = {
        "int_range", "enum", "float_range",
        "string", "bool"
    };
    if ((u32)t >= (sizeof names / sizeof names[0])) {
        return "?";
    }
    return names[t];
}

/*****************************************************************************/
/**
* @brief  Maps an access level to its protocol keyword ("RO"/"RW"/"WO").
*
* @param  a  Access level.
*
* @return Protocol keyword, or "?" if out of range.
******************************************************************************/
static const char *Proto_AccessName(Protocol_Access a)
{
    static const char *const names[] = { "RO", "RW", "WO" };
    if ((u32)a >= 3U) {
        return "?";
    }
    return names[a];
}

/* ============================================================================
 * Parameter parsing + validation (SETPARAM)
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  Parses + validates the token against p->Constraint and stores the result in *v.
*
* Out-of-range values are clamped; int values not on a step are snapped to the nearest
* valid step.
*
* @param  p    Parameter descriptor (Constraint / Type select the rules).
* @param  tok  Token to parse.
* @param  v    Receives the parsed value.
*
* @return 0 on success, -1 on malformed input.
******************************************************************************/
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
        if (iv < mn) iv = (s32)mn;               /* clamp to range */
        if (iv > mx) iv = (s32)mx;
        if (st > 1L) {                           /* snap to nearest valid step */
            long q = ((long)iv - mn + st / 2L) / st;
            iv = (s32)(mn + q * st);
        }
        v->I = iv;
        return 0;
    case VAL_TYPE_ENUM:
        if (Proto_ParseEnum(p->Constraint, tok, &v->I) != 0) return -1;
        return 0;
    case VAL_TYPE_FLOAT_RANGE:
        if (Proto_ParseFloatConstraint(p->Constraint, &fmn, &fmx, &fst) != 0) return -1;
        if (Proto_ParseFloat(tok, &fv) != 0) return -1;
        if (fv < fmn) fv = fmn;                  /* clamp to range */
        if (fv > fmx) fv = fmx;
        v->F = fv;
        return 0;
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
 * Apply callbacks (Apply): write the parameter's current value to hardware
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  Apply: writes the readout-mode selection to the CCD controller.
*
* @param  p  Parameter (uses p->Cur.I).
*
* @return 0 on success.
******************************************************************************/
static int Apply_ReadMode(const Protocol_Param *p)
{
    /* 切换 read_mode 会触发硬件软复位 (帧缓存清空, 固定帧长度重新锁定);
       先停止采集/发送并同步清理软件状态 (State/TxActive/FetchPending/RdWaiting) */
    Ccd_Stop(&gCcd);
    CcdController_SetReadMode(&gCcdCtrl, (u8)p->Cur.I);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: writes the SCLK frequency selection to the CCD controller.
*
* @param  p  Parameter (uses p->Cur.I).
*
* @return 0 on success.
******************************************************************************/
static int Apply_FreqSel(const Protocol_Param *p)
{
    CcdController_SetFreqSel(&gCcdCtrl, (u8)p->Cur.I);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: enables/disables the mock-ADC virtual pixel mode.
*
* @param  p  Parameter (uses p->Cur.B).
*
* @return 0 on success.
******************************************************************************/
static int Apply_MockMode(const Protocol_Param *p)
{
    CcdController_SetMockMode(&gCcdCtrl, p->Cur.B);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: writes the CDSCLK fine-delay taps to the CCD controller.
*
* @param  p  Parameter (uses p->Cur.I).
*
* @return 0 on success.
******************************************************************************/
static int Apply_CdsclkDelay(const Protocol_Param *p)
{
    CcdController_SetCdsclkDelay(&gCcdCtrl, (u8)p->Cur.I);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: pushes image_width/image_height (from their own params) to the CCD
* controller.
*
* @param  p  Unused (the width/height are read from the parameter table).
*
* @return 0 on success.
******************************************************************************/
static int Apply_ImageSize(const Protocol_Param *p)
{
    Protocol_Param *w, *h;

    (void)p;
    w = Proto_FindParam("image_width");
    h = Proto_FindParam("image_height");
    /* 写 IMG_SIZE 会触发硬件软复位 (帧缓存清空, 固定帧长度重新锁定);
       先停止采集/发送并同步清理软件状态 */
    Ccd_Stop(&gCcd);
    CcdController_SetImageSize(&gCcdCtrl, (u16)w->Cur.I, (u16)h->Cur.I);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: pushes all bevel/blank edges (from their own params) to the CCD controller.
*
* Shared by the bevel_* and blank_* params.
*
* @param  p  Unused (the edges are read from the parameter table).
*
* @return 0 on success.
******************************************************************************/
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

/*****************************************************************************/
/**
* @brief  Apply: enables/disables the TEC. The TEC control loop powers the ADN8833
* (EN pin) and commands the dac8311 together.
*
* @param  p  Parameter (uses p->Cur.B).
*
* @return 0 on success.
******************************************************************************/
static int Apply_TecEnable(const Protocol_Param *p)
{
    TecCtrl_SetEnable(&gTecCtrl, p->Cur.B);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: writes the sensor temperature setpoint to the TEC control loop.
*
* @param  p  Parameter (uses p->Cur.F).
*
* @return 0 on success.
******************************************************************************/
static int Apply_TecSetTemp(const Protocol_Param *p)
{
    TecCtrl_SetSetTemp(&gTecCtrl, p->Cur.F);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: pushes the three PID gains (from their own params) to the TEC
* control loop.
*
* @param  p  Unused (the gains are read from the parameter table).
*
* @return 0 on success.
******************************************************************************/
static int Apply_TecTunings(const Protocol_Param *p)
{
    const Protocol_Param *kp, *ki, *kd;

    (void)p;
    kp = Proto_FindParam("tec_kp");
    ki = Proto_FindParam("tec_ki");
    kd = Proto_FindParam("tec_kd");
    TecCtrl_SetTunings(&gTecCtrl, kp->Cur.F, ki->Cur.F, kd->Cur.F);
    return 0;
}

/*****************************************************************************/
/**
* @brief  Apply: builds an Ad9826_Config from the six adc_gain and adc_offset
* params and writes it to the ad9826 (Config/Mux use the power-up defaults).
*
* @param  p  Unused (the values are read from the parameter table).
*
* @return 0 on success, -1 if the SPI configuration write failed.
******************************************************************************/
static int Apply_AdcGainOffset(const Protocol_Param *p)
{
    Ad9826_Config c;

    (void)p;
    c.Config = AD9826_DEFAULT_CONFIG;
    c.Mux = AD9826_DEFAULT_MUX;
    c.GainR = (u8)Proto_FindParam("adc_gain_r")->Cur.I;
    c.GainG = (u8)Proto_FindParam("adc_gain_g")->Cur.I;
    c.GainB = (u8)Proto_FindParam("adc_gain_b")->Cur.I;
    c.OffR = (u16)Proto_FindParam("adc_offset_r")->Cur.I;
    c.OffG = (u16)Proto_FindParam("adc_offset_g")->Cur.I;
    c.OffB = (u16)Proto_FindParam("adc_offset_b")->Cur.I;
    return (Ad9826_Configure(&gAd9826, &c) == XST_SUCCESS) ? 0 : -1;
}

/* ============================================================================
 * Serialize callbacks (Format): write the current/live value as a protocol string
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  Format: serializes an int param as its decimal string.
*
* @param  p    Parameter (uses p->Cur.I).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_Int(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    Pb_Init(&b, buf, cap);
    Pb_AppendInt(&b, p->Cur.I);
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes an enum param as its label ("line_binning", ...).
*
* @param  p    Parameter (uses p->Cur.I as index into p->Constraint).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_Enum(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    char label[PROTO_STR_MAX];

    Pb_Init(&b, buf, cap);
    if (Proto_EnumLabel(p->Constraint, (u32)p->Cur.I, label, sizeof label) != 0) {
        Pb_Append(&b, "?");
    } else {
        Pb_Append(&b, label);
    }
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes a bool param as "1"/"0".
*
* @param  p    Parameter (uses p->Cur.B).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_Bool(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    Pb_Init(&b, buf, cap);
    Pb_Append(&b, p->Cur.B ? "1" : "0");
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes a string param wrapped in double quotes.
*
* @param  p    Parameter (uses p->Cur.S).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_String(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    Pb_Init(&b, buf, cap);
    Pb_Append(&b, "\"");
    Pb_Append(&b, p->Cur.S);
    Pb_Append(&b, "\"");
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes a float param with decimals taken from its constraint step.
*
* @param  p    Parameter (uses p->Cur.F and p->Constraint).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_Float(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    int dec = Proto_StepDecimals(p->Constraint);
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b, p->Cur.F, dec);
    return (int)b.Len;
}

/* ---- RO params: live values from monitor / ccd ---- */
/*****************************************************************************/
/**
* @brief  Format: reads the live sensor NTC temperature from the monitor.
*
* @param  p    Unused (live value).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_SensorTemp(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b, Monitor_GetNtcTemp(&gMonitor, ADS1118_MUX_SENSOR_NTC), 1);
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: reads the live environment NTC temperature from the monitor.
*
* @param  p    Unused (live value).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_EnvTemp(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b, Monitor_GetNtcTemp(&gMonitor, ADS1118_MUX_ENV_NTC), 1);
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: reads the live TEC output voltage (Vvm monitor via
* Vtec = 4*(Vvm - 1.25)) from the monitor.
*
* @param  p    Unused (live value).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_TecVoltage(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b,
                   Tec_VmonToVtec(Monitor_GetVoltage(&gMonitor, ADS1118_MUX_TEC_V)),
                   3);
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: reads the live TEC output current (Vim monitor via
* Itec = 1.905*(Vim - 1.25)) from the monitor.
*
* @param  p    Unused (live value).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_TecCurrent(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendFloat(&b,
                   Tec_ImonToItec(Monitor_GetVoltage(&gMonitor, ADS1118_MUX_TEC_I)),
                   3);
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes the current CCD acquisition state ("idle", "exposing", ...).
*         Frame sending (fetch) is orthogonal to this state machine and not
*         reflected here.
*
* @param  p    Unused (state comes from gCcd).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_AcqState(const Protocol_Param *p, char *buf, u32 cap)
{
    static const char *const states[] = { "idle", "exposing", "reading" };
    ProtoBuf b;
    u32 idx = (u32)gCcd.State;
    (void)p;
    if (idx >= (sizeof states / sizeof states[0])) idx = 0U;
    Pb_Init(&b, buf, cap);
    Pb_Append(&b, states[idx]);
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes the number of frames ready in the cache.
*
* @param  p    Unused (value comes from gCcd).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_FrameNum(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendInt(&b, (s32)Ccd_GetFrameNum(&gCcd));
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes the max frame cache capacity (CCD_MAX_FRAMES).
*
* @param  p    Unused (compile-time constant).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_FrameCapacity(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendInt(&b, (s32)CCD_MAX_FRAMES);
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes the live frame exception flag (STATUS[8]).
*
* @param  p    Unused (value comes from gCcd).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_ExceptionFlag(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_Append(&b, Ccd_GetException(&gCcd) ? "1" : "0");
    return (int)b.Len;
}

/*****************************************************************************/
/**
* @brief  Format: serializes the accumulated frame exception count (STATUS[15:9]).
*
* @param  p    Unused (value comes from gCcd).
* @param  buf  Destination buffer.
* @param  cap  Buffer capacity in bytes.
*
* @return Number of bytes written (excluding NUL).
******************************************************************************/
static int Fmt_ExceptionCnt(const Protocol_Param *p, char *buf, u32 cap)
{
    ProtoBuf b;
    (void)p;
    Pb_Init(&b, buf, cap);
    Pb_AppendInt(&b, (s32)Ccd_GetExceptionCnt(&gCcd));
    return (int)b.Len;
}

/* Attach Apply / Format to each parameter (centralized assignment to keep the
 * initializer list short) */
/*****************************************************************************/
/**
* @brief  Binds the Apply/Format callbacks to every parameter (called once by Protocol_Init).
******************************************************************************/
static void Proto_BindHandlers(void)
{
    g_params[0].Format = Fmt_Int;                /* exposure_time_us */
    g_params[1].Apply  = Apply_ReadMode;   g_params[1].Format = Fmt_Enum;
    g_params[2].Apply  = Apply_FreqSel;    g_params[2].Format = Fmt_Enum;
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
    g_params[13].Apply = Apply_TecEnable;   g_params[13].Format = Fmt_Bool;
    g_params[14].Apply = Apply_TecSetTemp;  g_params[14].Format = Fmt_Float;
    g_params[15].Apply = Apply_TecTunings;  g_params[15].Format = Fmt_Float;
    g_params[16].Apply = Apply_TecTunings;  g_params[16].Format = Fmt_Float;
    g_params[17].Apply = Apply_TecTunings;  g_params[17].Format = Fmt_Float;
    g_params[18].Format = Fmt_SensorTemp;
    g_params[19].Format = Fmt_EnvTemp;
    g_params[20].Format = Fmt_TecVoltage;
    g_params[21].Format = Fmt_TecCurrent;
    g_params[22].Format = Fmt_String;
    g_params[23].Format = Fmt_AcqState;
    g_params[24].Format = Fmt_FrameNum;
    g_params[25].Format = Fmt_FrameCapacity;
    g_params[26].Format = Fmt_ExceptionFlag;
    g_params[27].Format = Fmt_ExceptionCnt;
    g_params[28].Apply = Apply_AdcGainOffset; g_params[28].Format = Fmt_Int;
    g_params[29].Apply = Apply_AdcGainOffset; g_params[29].Format = Fmt_Int;
    g_params[30].Apply = Apply_AdcGainOffset; g_params[30].Format = Fmt_Int;
    g_params[31].Apply = Apply_AdcGainOffset; g_params[31].Format = Fmt_Int;
    g_params[32].Apply = Apply_AdcGainOffset; g_params[32].Format = Fmt_Int;
    g_params[33].Apply = Apply_AdcGainOffset; g_params[33].Format = Fmt_Int;
}

/* ============================================================================
 * Parameter lookup
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  Looks up a parameter by its protocol keyword.
*
* @param  name  Parameter keyword (ASCII, no spaces).
*
* @return Pointer to the parameter, or NULL if not found.
******************************************************************************/
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
 * Command handling
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  LISTPARAMS [group]: replies with the comma-separated names of matching parameters.
*
* @param  argc  Token count (>= 1).
* @param  argv  Tokens; argv[1] is the optional group filter.
*
* @return 0.
******************************************************************************/
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

/*****************************************************************************/
/**
* @brief  GETINFO <name>: replies with name, type, access, description, unit and constraint.
*
* @param  argc  Token count (>= 2).
* @param  argv  Tokens; argv[1] is the parameter name.
*
* @return 0.
******************************************************************************/
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

/*****************************************************************************/
/**
* @brief  GETPARAM <name>: replies with the formatted current/live value of the parameter.
*
* @param  argc  Token count (>= 2).
* @param  argv  Tokens; argv[1] is the parameter name.
*
* @return 0.
******************************************************************************/
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

/*****************************************************************************/
/**
* @brief  SETPARAM <name> <value>: parses, stores, and applies the value to hardware.
*
* @param  argc  Token count (>= 3).
* @param  argv  Tokens; argv[1] = name, argv[2] = value.
*
* @return 0.
******************************************************************************/
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

/*****************************************************************************/
/**
* @brief  ACQ single|live|burst|fetch|abort: capture/send control.
*
*   - single      : capture one frame (frame written to cache -> IDLE), host fetches it
*   - live        : continuous capture into cache (host fetch drains frames)
*   - burst <n>   : capture n frames continuously into cache, then IDLE
*   - fetch <n>   : send n cached frames to FX2 (immediate OK; the send itself
*                   is paced by TX_DONE; poll acq_state / frame_num_ready)
*   - abort       : stop capture / pending fetch / burst
*
* All three capture modes go through Ccd_Start(d, n, us): single/live use the
* exposure_time_us parameter; burst uses the same exposure_time_us value too.
* A burst (or single) whose frames cannot fit the free cache space is rejected
* (ERR 3 ... exceeds cache).
*
* @param  argc  Token count (>= 2).
* @param  argv  Tokens; argv[1] is the mode, argv[2] the frame count for
*               burst/fetch.
*
* @return 0.
******************************************************************************/
static int Cmd_Acq(int argc, char **argv)
{
    const Protocol_Param *pt;
    u32 n;
    int st;

    if (argc < 2) { Proto_Err(PROTO_ERR_INVALID_VALUE, "missing mode"); return 0; }

    if (strcmp(argv[1], "abort") == 0) {
        Ccd_Stop(&gCcd);
        Proto_Ok0();
        return 0;
    }

    pt = Proto_FindParam("exposure_time_us");

    if (strcmp(argv[1], "burst") == 0) {
        if (argc < 3 || Proto_ParseUInt(argv[2], &n) != 0 || n == 0U) {
            Proto_Err(PROTO_ERR_INVALID_VALUE, "burst needs frame count");
            return 0;
        }

        st = Ccd_Start(&gCcd, n, (u64)((pt != NULL) ? pt->Cur.I : 1000L));
        if (st == XST_DEVICE_BUSY) { Proto_Err(PROTO_ERR_BUSY, "busy"); return 0; }
        if (st != XST_SUCCESS)     { Proto_Err(PROTO_ERR_INVALID_VALUE,
                                               "burst exceeds cache"); return 0; }
        Proto_Ok0();
        return 0;
    }

    if (strcmp(argv[1], "single") == 0 || strcmp(argv[1], "live") == 0) {
        u64 us;

        us = (u64)((pt != NULL) ? pt->Cur.I : 1000L);
        st = Ccd_Start(&gCcd, (argv[1][0] == 'l') ? 0U : 1U, us);
        if (st == XST_DEVICE_BUSY) { Proto_Err(PROTO_ERR_BUSY, "busy"); return 0; }
        if (st != XST_SUCCESS)     { Proto_Err(PROTO_ERR_INTERNAL, "acq start failed"); return 0; }
        Proto_Ok0();
        return 0;
    }

    if (strcmp(argv[1], "fetch") == 0) {
        char msg[PROTO_RESP_MAX];
        ProtoBuf b;

        if (argc < 3 || Proto_ParseUInt(argv[2], &n) != 0 || n == 0U) {
            Proto_Err(PROTO_ERR_INVALID_VALUE, "fetch needs frame count");
            return 0;
        }
        st = Ccd_StartFetch(&gCcd, n);
        if (st == XST_DEVICE_BUSY) { Proto_Err(PROTO_ERR_BUSY, "busy"); return 0; }
        if (st != XST_SUCCESS) {
            Pb_Init(&b, msg, sizeof msg);
            Pb_Append(&b, "insufficient frames (");
            Pb_AppendInt(&b, (s32)Ccd_GetFrameNum(&gCcd));
            Pb_Append(&b, " ready)");
            Proto_Err(PROTO_ERR_BUSY, msg);
            return 0;
        }
        Proto_Ok0();
        return 0;
    }

    Proto_Err(PROTO_ERR_INVALID_VALUE, "invalid mode (single|live|burst|fetch|abort)");
    return 0;
}

/* ============================================================================
 * Line parsing (spaces + double quotes, "\"" escaping)
 * ==========================================================================*/
/*****************************************************************************/
/**
* @brief  Copies src into itself, decoding "\"" escapes.
*
* Stops at an unescaped '"' or NUL.
*
* @param  src  Source/destination buffer (in-place).
*
* @return Pointer to the stopping char (the '"' or the NUL terminator).
******************************************************************************/
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

/*****************************************************************************/
/**
* @brief  Splits line into whitespace-separated tokens into argv (max max).
*
* Honors double quotes with "\"" escaping.
*
* @param  line  Line buffer (modified in place: tokens become NUL-terminated).
* @param  argv  Receives pointers to the tokens (capacity max).
* @param  max   Maximum number of tokens.
*
* @return Token count, or -1 if more than max tokens are present.
******************************************************************************/
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

/*****************************************************************************/
/**
* @brief  Dispatches a command: tokenizes then routes the first token through the verb table.
*
* The slave replies to every received line: token overflow (more than PROTO_MAX_ARGS)
* and empty lines get an ERR response instead of being silently dropped, so the host
* (send one command, wait for the reply) never hangs.
*
* @note Verb matching is case-insensitive; parameter names / values remain
* case-sensitive (matching the existing lower-case convention).
*
* @param  line  Complete command line (modified in place by tokenizing).
******************************************************************************/
static void Proto_Dispatch(char *line)
{
    char *argv[PROTO_MAX_ARGS];
    int argc;
    u32 i;
    char *v;

    argc = Proto_Tokenize(line, argv, PROTO_MAX_ARGS);
    if (argc < 0) {
        Proto_Err(PROTO_ERR_INVALID_VALUE, "too many args");
        return;
    }
    if (argc == 0) {
        Proto_Err(PROTO_ERR_INVALID_VALUE, "empty line");
        return;
    }

    /* Uppercase the verb token in place: g_cmds[].Verb keys are upper-case, but
     * tolerate lower/mixed-case host input for debug convenience. */
    for (v = argv[0]; *v != '\0'; ++v) {
        if ((*v >= 'a') && (*v <= 'z')) {
            *v = (char)(*v - ('a' - 'A'));
        }
    }

    for (i = 0; i < PROTO_NUM_CMDS; i++) {
        if (strcmp(argv[0], g_cmds[i].Verb) == 0) {
            g_cmds[i].Handler(argc, argv);
            return;
        }
    }
    Proto_Err(PROTO_ERR_UNKNOWN_VERB, "unknown verb");
}

/* ============================================================================
 * ISR -> main loop pending channel
 * ==========================================================================*/
static volatile u8 gLinePending;
static volatile u8 gLineTooLong;
static char gPendingLine[UART_LINE_MAX];

/*****************************************************************************/
/**
* @brief  UART received a complete line (ISR context): copies into the pending buffer and
* sets the flag.
*
* @param  line  Received line.
* @param  ref   Unused callback reference.
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
* @brief  UART error callback (ISR context): sets a flag for an over-long line, the main
* loop replies ERR 6.
*
* @param  err  UART error code.
* @param  ref  Unused callback reference.
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
* @brief  Main loop polling: handles the pending ERR 6 and the command lines to dispatch.
******************************************************************************/
void Protocol_ProcessPending(void)
{
    char line[UART_LINE_MAX];

    if (gLineTooLong) {
        gLineTooLong = 0;
        Proto_Err(PROTO_ERR_LINE_TOO_LONG, "line too long");
    }

    if (gLinePending == 0) return;

    /* Copy out in a critical section, to avoid being overwritten by the ISR */
    microblaze_disable_interrupts();
    memcpy(line, gPendingLine, sizeof line);
    gLinePending = 0;
    microblaze_enable_interrupts();

    Proto_Dispatch(line);
}

/*****************************************************************************/
/**
* @brief  Protocol initialization: binds Apply/Format, applies the parameter defaults to
* hardware, prints READY.
*
* @return XST_SUCCESS.
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
