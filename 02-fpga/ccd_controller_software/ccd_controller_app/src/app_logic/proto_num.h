/******************************************************************************
* @file proto_num.h
*
* 协议数字/集合解析与格式化（纯逻辑，无硬件/Xilinx 依赖，可独立主机测试）。
* 手写实现以避免引入 newlib printf/strtod（体积过大，128KB local mem 装不下）。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/03 First release
* </pre>
******************************************************************************/
#ifndef PROTO_NUM_H
#define PROTO_NUM_H

#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 十进制格式化（返回写入长度，不含 NUL） */
u32  Proto_Utoa(char *buf, u32 v);
u32  Proto_Itoa(char *buf, s32 v);

/* 十进制解析（整串须合法，成功返回 0） */
int  Proto_ParseInt(const char *s, s32 *out);
int  Proto_ParseUInt(const char *s, u32 *out);
int  Proto_ParseFloat(const char *s, float *out);

/* 定点小数格式化：dec 位小数（0..5），四舍五入，避免 -0 */
void Proto_FmtFloat(char *buf, u32 cap, float v, int dec);

/* 约束串工具："min:max:step" 解析 / step 小数位推导 */
int  Proto_ParseIntConstraint(const char *c, long *mn, long *mx, long *st);
int  Proto_ParseFloatConstraint(const char *c, float *mn, float *mx, float *st);
int  Proto_StepDecimals(const char *constraint);

/* 集合工具："a,b,c" 计数 / 取第 idx 个标签 / 标签匹配 */
u32  Proto_CollCount(const char *list);
int  Proto_CollLabel(const char *list, u32 idx, char *buf, u32 cap);
int  Proto_ParseColl(const char *list, const char *tok, s32 *out);

/* 组过滤：tec_* 前缀匹配，否则精确匹配 */
int  Proto_MatchGroup(const char *name, const char *group);

#ifdef __cplusplus
}
#endif

#endif /* PROTO_NUM_H */
