/******************************************************************************
* @file proto_num.h
*
* Protocol number/set parsing and formatting (pure logic, no hardware/Xilinx dependency,
* can be host-tested standalone).
* Hand-written implementation to avoid pulling in newlib printf/strtod (too large for the
* 128KB local mem).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/03 First release
* </pre>
******************************************************************************/
#ifndef PROTO_NUM_H
#define PROTO_NUM_H

#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Decimal formatting (returns the length written, without NUL) */
u32  Proto_Utoa(char *buf, u32 v);
u32  Proto_Itoa(char *buf, s32 v);

/* Decimal parsing (the whole string must be valid, returns 0 on success) */
int  Proto_ParseInt(const char *s, s32 *out);
int  Proto_ParseUInt(const char *s, u32 *out);
int  Proto_ParseFloat(const char *s, float *out);

/* Fixed-point formatting: dec decimal places (0..5), rounded, avoids -0 */
void Proto_FmtFloat(char *buf, u32 cap, float v, int dec);

/* Constraint string utilities: "min:max:step" parsing / step decimal-place derivation */
int  Proto_ParseIntConstraint(const char *c, long *mn, long *mx, long *st);
int  Proto_ParseFloatConstraint(const char *c, float *mn, float *mx, float *st);
int  Proto_StepDecimals(const char *constraint);

/* Enum utilities: "a,b,c" count / get the idx-th label / label matching */
u32  Proto_EnumCount(const char *list);
int  Proto_EnumLabel(const char *list, u32 idx, char *buf, u32 cap);
int  Proto_ParseEnum(const char *list, const char *tok, s32 *out);

/* Group filter: tec_* prefix matching, otherwise exact matching */
int  Proto_MatchGroup(const char *name, const char *group);

#ifdef __cplusplus
}
#endif

#endif /* PROTO_NUM_H */
