/******************************************************************************
* @file ntc.h
*
* NTC code -> temperature lookup with linear interpolation (pure logic, no
* hardware/Xilinx dependency, host-testable standalone). Lookup tables are
* generated offline by tools/gen_ntc_table.py (see ntc_tables.h).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/03 First release
* </pre>
******************************************************************************/
#ifndef NTC_H
#define NTC_H

#include "xil_types.h"
#include "ntc_tables.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const NtcPoint *Table;   /* ascending-code lookup table */
    u32 TableN;              /* number of entries */
} NtcTableCfg;

float Ntc_LookupTemp(s16 code, const NtcTableCfg *cfg);   /* degC */

#ifdef __cplusplus
}
#endif

#endif /* NTC_H */
