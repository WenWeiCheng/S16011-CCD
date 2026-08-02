/******************************************************************************
* @file uart.h
*
* UART 行缓冲 + 收发驱动：封装 XUartLite，为 app 逻辑提供按行收发语义。
* 只做字节流 ↔ 行缓冲转换，不解析命令内容（解析属 app 逻辑层）。
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

#define UART_LINE_MAX   256U   /* 行长度上限，含 \r\n */

typedef enum {
    UART_ERR_NONE = 0,
    UART_ERR_LINE_TOO_LONG,     /* 行超长（对应协议 ERR 6 line too long） */
    UART_ERR_RX_OVERFLOW        /* 接收缓冲溢出（保留，当前未用） */
} UartError;

typedef void (*UartLineHandler)(const char *line, void *ref);
typedef void (*UartErrorHandler)(UartError err, void *ref);

typedef struct {
    XUartLite *Uart;
    u32 IntrVecId;
    u8  RxBuf[UART_LINE_MAX];    /* 当前行累积缓冲 */
    u16 RxLen;
    u8  CrPending;               /* 上一字节为 \r 的标志 */
    UartLineHandler LineHandler;
    void *LineRef;
    UartErrorHandler ErrHandler;
    void *ErrRef;
} Uart;

int  Uart_Init(Uart *d, XUartLite *uart, u32 IntrVecId);
void Uart_RegisterLineHandler(Uart *d, UartLineHandler hdl, void *ref);
void Uart_RegisterErrorHandler(Uart *d, UartErrorHandler hdl, void *ref);
int  Uart_SendLine(Uart *d, const char *line);   /* 自动补 \r\n */
int  Uart_Send(Uart *d, const char *s, u32 n);   /* raw：不补换行 */
void Uart_InterruptHandler(void *ref);           /* RX ISR，挂 INTC */

#ifdef __cplusplus
}
#endif

#endif /* UART_H */
