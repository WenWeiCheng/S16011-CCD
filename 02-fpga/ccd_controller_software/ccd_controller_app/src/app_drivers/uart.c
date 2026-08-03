/******************************************************************************
* @file uart.c
*
* UART line-buffer driver implementation. RX interrupt fills the buffer byte by byte,
* and \r\n / \r / \n complete a line and trigger the callback; an over-long line
* clears the buffer and reports UART_ERR_LINE_TOO_LONG. TX sends blocking.
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
* @brief  Completes a line: NUL-terminates and calls back LineHandler, then resets the buffer.
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
* @brief  Error handling: clears the buffer and calls back ErrHandler.
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
* @brief  Processes a single received byte (called in ISR context).
******************************************************************************/
static void Uart_PushByte(Uart *d, u8 ch)
{
    if (ch == '\n') {
        /* \n in a \r\n pair: the previous \r already completed the line, skip to avoid an empty line */
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
* @brief  Initializes: resets the FIFOs, clears the buffer and enables UART interrupts.
*
* @param  d    UART instance.
* @param  uart XUartLite instance (initialized by board_hal).
* @param  IntrVecId INTC vector number.
*
* @return XST_SUCCESS.
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
* @brief  Registers the "complete line received" callback.
******************************************************************************/
void Uart_RegisterLineHandler(Uart *d, UartLineHandler hdl, void *ref)
{
    d->LineHandler = hdl;
    d->LineRef = ref;
}

/*****************************************************************************/
/**
* @brief  Registers the error callback (over-long / overflow).
******************************************************************************/
void Uart_RegisterErrorHandler(Uart *d, UartErrorHandler hdl, void *ref)
{
    d->ErrHandler = hdl;
    d->ErrRef = ref;
}

/*****************************************************************************/
/**
* @brief  Synchronously sends a line, appending \r\n automatically.
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
* @brief  Raw send (no newline appended). Blocks until all bytes are written to the TX FIFO.
******************************************************************************/
int Uart_Send(Uart *d, const char *s, u32 n)
{
    Xil_AssertNonvoid(d != NULL);
    Xil_AssertNonvoid(s != NULL);

    while (n > 0U) {
        u32 sent = XUartLite_Send(d->Uart, (u8 *)s, n);
        if (sent == 0U) {
            continue;   /* TX FIFO full, wait for a free slot (blocking) */
        }
        s += sent;
        n -= sent;
    }
    return XST_SUCCESS;
}

/*****************************************************************************/
/**
* @brief  RX interrupt handler (hooked to INTC, vec3).
*
* Reads the RX FIFO byte by byte into the line buffer, calling back LineHandler when
* a line is complete.
******************************************************************************/
void Uart_InterruptHandler(void *ref)
{
    Uart *d = (Uart *)ref;
    u8 byte;

    while (XUartLite_Recv(d->Uart, &byte, 1U) > 0U) {
        Uart_PushByte(d, byte);
    }
}
