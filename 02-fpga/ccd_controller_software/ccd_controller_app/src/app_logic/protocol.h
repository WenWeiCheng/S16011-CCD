/******************************************************************************
* @file protocol.h
*
* UART control protocol (app logic layer): parameter table + command dispatch table +
* line parsing/response + acquisition commands.
* Protocol spec is in 00-docs/embed-design/uart_protocol_design.md.
*
* Thread model: the UART RX interrupt only copies a complete line into a pending buffer
* (Protocol_OnLine); the real command dispatch happens in Protocol_ProcessPending in the
* main loop, avoiding slow operations (e.g. blocking SPI) in ISR context.
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/03 First release
* </pre>
******************************************************************************/
#ifndef PROTOCOL_H
#define PROTOCOL_H

#include "xil_types.h"
#include "../app_drivers/uart.h"

#ifdef __cplusplus
extern "C" {
#endif

int  Protocol_Init(void);                          /* app parameter defaults + print READY */
void Protocol_OnLine(const char *line, void *ref); /* UART LineHandler (ISR) */
void Protocol_OnError(UartError err, void *ref);   /* UART ErrHandler (ISR) */
void Protocol_ProcessPending(void);                /* called from main loop: dispatch queued commands */

#ifdef __cplusplus
}
#endif

#endif /* PROTOCOL_H */
