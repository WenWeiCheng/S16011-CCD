/******************************************************************************
* @file tec.c
*
* TEC control / monitor unit conversions (pure logic). See tec.h for the
* conversion relationships.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   wwc  26/08/04 First release
* </pre>
******************************************************************************/
#include "tec.h"
#include "../include/board_config.h"

/*****************************************************************************/
/**
* @brief  TEC output voltage -> DAC output voltage Vcont.
*
* Inverse of Vtec = 5 * (1.25 - Vcont): Vcont = 1.25 - Vtec / 5.
*
* @param  vtec  Desired/commanded TEC output voltage (V).
*
* @return DAC output voltage Vcont (V).
******************************************************************************/
float Tec_VtecToVcont(float vtec)
{
    return ADN8833_VCONT_REF_V - vtec / ADN8833_VTEC_PER_VCONT;
}

/*****************************************************************************/
/**
* @brief  ADN8833 VVM monitor voltage -> TEC output voltage.
*
* Vtec = 4 * (Vvm - 1.25).
*
* @param  vvm  ADN8833 VVM monitor voltage (V).
*
* @return TEC output voltage Vtec (V).
******************************************************************************/
float Tec_VmonToVtec(float vvm)
{
    return (vvm - ADN8833_VCONT_REF_V) * ADN8833_VTEC_PER_VMON;
}

/*****************************************************************************/
/**
* @brief  ADN8833 VIM monitor voltage -> TEC output current.
*
* Itec = 1.905 * (Vim - 1.25).
*
* @param  vim  ADN8833 VIM monitor voltage (V).
*
* @return TEC output current Itec (A).
******************************************************************************/
float Tec_ImonToItec(float vim)
{
    return (vim - ADN8833_VCONT_REF_V) * ADN8833_ITEC_PER_IMON;
}
