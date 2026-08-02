/******************************************************************************
* @file uart.c
*
* UART 行缓冲驱动实现。RX 中断按字节入缓冲，\r\n / \r / \n 成行回调；
* 行超长清缓冲并上报 UART_ERR_LINE_TOO_LONG。TX 阻塞发送。
*
* @note <pre>
* MODIFICATION HISTORY:
*
* Ver   Who  Date     Changes
* ----- ---- -------- -----------------------------------------------
* 1.0   whc  26/08/02 First release
* </pre>
******************************************************************************/
#include "uart.h"
#include "xil_assert.h"
#include <string.h>

/*****************************************************************************/
/**
* @brief  完成一行：NUL 结尾并回调 LineHandler，随后复位缓冲。
******************************************************************************/
static void Uart_CompleteLine(Uart *d)
{
    d->RxBuf[d->RxLen] = '\0';
    if (d->LineHandler != NULL) {
        d->LineHandler((const char *)d->RxBuf, d->LineRef);
    }
    d->RxLen = 0U;
}

/*****************************************************************************/
/**
* @brief  错误处理：清缓冲并回调 ErrHandler。
******************************************************************************/
static void Uart_Reset(Uart *d, UartError err)
{
    d->RxLen = 0U;
    d->CrPending = 0U;
    if (d->ErrHandler != NULL) {
        d->ErrHandler(err, d->ErrRef);
    }
}

/*****************************************************************************/
/**
* @brief  处理一个接收字节（在 ISR 上下文中调用）。
******************************************************************************/
static void Uart_PushByte(Uart *d, u8 ch)
{
    if (ch == '\n') {
        /* \r\n 中的 \n：上一字节 \r 已成行，跳过以免产生空行 */
        if (d->CrPending) {
            d->CrPending = 0U;
            return;
        }
        Uart_CompleteLine(d);
        return;
    }

    if (ch == '\r') {
        d->CrPending = 1U;
        Uart_CompleteLine(d);
        return;
    }

    d->CrPending = 0U;
    if (d->RxLen >= (UART_LINE_MAX - 1U)) {
        Uart_Reset(d, UART_ERR_LINE_TOO_LONG);
        return;
    }
    d->RxBuf[d->RxLen++] = ch;
}

/*****************************************************************************/
/**
* @brief  初始化：清 FIFO、清缓冲并启用 UART 中断。
*
* @param  d    UART 实例。
* @param  uart XUartLite 实例（board_hal 已初始化）。
* @param  IntrVecId INTC 向量号。
*
* @return XST_SUCCESS。
******************************************************************************/
int Uart_Init(Uart *d, XUartLite *uart, u32 IntrVecId)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(uart != NULL);

    d->Uart = uart;
    d->IntrVecId = IntrVecId;
    d->RxLen = 0U;
    d->CrPending = 0U;
    d->LineHandler = NULL;
    d->LineRef = NULL;
    d->ErrHandler = NULL;
    d->ErrRef = NULL;

    XUartLite_ResetFifos(uart);
    XUartLite_EnableInterrupt(uart);

    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  注册"收到完整一行"回调。
******************************************************************************/
void Uart_RegisterLineHandler(Uart *d, UartLineHandler hdl, void *ref)
{
    d->LineHandler = hdl;
    d->LineRef = ref;
}

/*****************************************************************************/
/**
* @brief  注册错误回调（超长/溢出）。
******************************************************************************/
void Uart_RegisterErrorHandler(Uart *d, UartErrorHandler hdl, void *ref)
{
    d->ErrHandler = hdl;
    d->ErrRef = ref;
}

/*****************************************************************************/
/**
* @brief  同步发送一行，自动补 \r\n。
******************************************************************************/
int Uart_SendLine(Uart *d, const char *line)
{
    int status;

    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(line != NULL);

    status = Uart_Send(d, line, (u32)strlen(line));
    if (status != XST_SUCCESS) {
        return status;
    }
    return Uart_Send(d, "\r\n", 2U);
}

/*****************************************************************************/
/**
* @brief  raw 发送（不补换行）。阻塞直到全部写入 TX FIFO。
******************************************************************************/
int Uart_Send(Uart *d, const char *s, u32 n)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(s != NULL);

    while (n > 0U) {
        u32 sent = XUartLite_Send(d->Uart, (u8 *)s, n);
        if (sent == 0U) {
            continue;   /* TX FIFO 满，等待空位（阻塞） */
        }
        s += sent;
        n -= sent;
    }
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  RX 中断处理（挂 INTC，vec3）。
*
* 逐字节读出 RX FIFO 并送入行缓冲，成行即回调 LineHandler。
******************************************************************************/
void Uart_InterruptHandler(void *ref)
{
    Uart *d = (Uart *)ref;
    u8 byte;

    while (XUartLite_Recv(d->Uart, &byte, 1U) > 0U) {
        Uart_PushByte(d, byte);
    }
}
