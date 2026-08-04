/******************************************************************************
* @file ntc.c
*
* NTC code -> temperature lookup with linear interpolation over an offline
* generated table (ascending code order). Direction-agnostic: works whether the
* temperature rises or falls with the code, clamps at both table ends, and skips
* zero-width segments (adjacent identical codes produced by ADC saturation).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/03 First release
* </pre>
******************************************************************************/
#include "ntc.h"

/*****************************************************************************/
/**
* @brief  code -> temperature (degC), linear interpolation over the table, clamped
* at both ends. The table must be sorted by ascending code; the temperature may
* increase or decrease with the code (direction-agnostic).
*
* @param  code  Raw 16-bit ADC code of the NTC channel.
* @param  cfg   NTC table descriptor (Table / TableN).
*
* @return Temperature in degC (0 if the table is empty).
******************************************************************************/
float Ntc_LookupTemp(s16 code, const NtcTableCfg *cfg)
{
    u32 i, c = (u32)(u16)code;
    s32 den;

    if (cfg->TableN == 0U) {
        return 0.0f;
    }
    /* clamp: at/below the smallest table code -> first entry temperature */
    if (c <= cfg->Table[0].Code) {
        return (float)cfg->Table[0].TempX10 / 10.0f;
    }
    /* clamp: at/above the largest table code -> last entry temperature */
    if (c >= cfg->Table[cfg->TableN - 1U].Code) {
        return (float)cfg->Table[cfg->TableN - 1U].TempX10 / 10.0f;
    }

    /* interpolate the segment with Table[i].Code < c <= Table[i+1].Code */
    for (i = 0U; i < cfg->TableN - 1U; i++) {
        if (c <= cfg->Table[i + 1U].Code) {
            den = (s32)cfg->Table[i + 1U].Code - (s32)cfg->Table[i].Code;
            if (den > 0) {
                return (float)((s32)cfg->Table[i].TempX10 * den +
                       (s32)(c - cfg->Table[i].Code) *
                       (s32)(cfg->Table[i + 1U].TempX10 - cfg->Table[i].TempX10)) /
                       (10.0f * (float)den);
            }
            /* zero-width segment: keep searching */
        }
    }
    return (float)cfg->Table[cfg->TableN - 1U].TempX10 / 10.0f;
}
