/******************************************************************************
* @file tec.h
*
* TEC control / monitor unit conversions (pure logic, no hardware/Xilinx
* dependency, host-testable standalone). Constants come from board_config.h.
*
* Relationships (ADN8833 + dac8311):
*   Vtec = 5 * (1.25 - Vcont)    DAC output Vcont -> TEC output voltage
*   Vtec = 4 * (Vvm - 1.25)      VVM monitor -> TEC output voltage
*   Itec = 1.905 * (Vim - 1.25)  VIM monitor -> TEC output current
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/04 First release
* </pre>
******************************************************************************/
#ifndef TEC_H
#define TEC_H

#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

float Tec_VtecToVcont(float vtec);   /* Vtec -> DAC output Vcont (V) */
float Tec_VmonToVtec(float vvm);     /* ADN8833 VVM monitor -> Vtec (V) */
float Tec_ImonToItec(float vim);     /* ADN8833 VIM monitor -> Itec (A) */

#ifdef __cplusplus
}
#endif

#endif /* TEC_H */
