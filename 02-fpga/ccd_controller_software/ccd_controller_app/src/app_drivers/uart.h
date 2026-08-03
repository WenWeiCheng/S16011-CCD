/******************************************************************************
* @file uart.h
*
* UART line-buffer + send/receive driver: wraps XUartLite, providing line-based
* send/receive semantics for the app logic.
* Only converts byte stream <-> line buffer; it does not parse command content
* (parsing belongs to the app logic layer).
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#ifndef UART_H
#define UART_H

#include "xil_types.h"
#include "xstatus.h"
#include "xuartlite.h"

#ifdef __cplusplus
extern "C" {
#endif

#define UART_LINE_MAX   256U   /* max line length, including \r\n */

typedef enum {
    UART_ERR_NONE = 0,
    UART_ERR_LINE_TOO_LONG,     /* line over-long (corresponds to protocol ERR 6 line too long) */
    UART_ERR_RX_OVERFLOW        /* receive buffer overflow (reserved, currently unused) */
} UartError;

typedef void (*UartLineHandler)(const char *line, void *ref);
typedef void (*UartErrorHandler)(UartError err, void *ref);

typedef struct {
    XUartLite *Uart;
    u32 IntrVecId;
    u8  RxBuf[UART_LINE_MAX];    /* buffer accumulating the current line */
    u16 RxLen;
    u8  CrPending;               /* flag that the previous byte was \r */
    UartLineHandler LineHandler;
    void *LineRef;
    UartErrorHandler ErrHandler;
    void *ErrRef;
} Uart;

int  Uart_Init(Uart *d, XUartLite *uart, u32 IntrVecId);
void Uart_RegisterLineHandler(Uart *d, UartLineHandler hdl, void *ref);
void Uart_RegisterErrorHandler(Uart *d, UartErrorHandler hdl, void *ref);
int  Uart_SendLine(Uart *d, const char *line);   /* appends \r\n automatically */
int  Uart_Send(Uart *d, const char *s, u32 n);   /* raw: no newline appended */
void Uart_InterruptHandler(void *ref);           /* RX ISR, hooked to INTC */

#ifdef __cplusplus
}
#endif

#endif /* UART_H */
