/******************************************************************************
* @file protocol.h
*
* UART 控制协议（app 逻辑层）：参数表 + 命令分发表 + 行解析/响应 + 采集命令。
* 协议规范见 00-docs/embed-design/uart_protocol_design.md。
*
* 线程模型：UART RX 中断只把完整行拷入 pending 缓冲（Protocol_OnLine），
* 真正的命令分发在 main 循环 Protocol_ProcessPending 中进行，避免在 ISR
* 上下文执行阻塞 SPI 等耗时操作。
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

int  Protocol_Init(void);                          /* 应用参数默认值 + 打印 READY */
void Protocol_OnLine(const char *line, void *ref); /* UART LineHandler（ISR） */
void Protocol_OnError(UartError err, void *ref);   /* UART ErrHandler（ISR） */
void Protocol_ProcessPending(void);                /* 主循环调用：分发已入队命令 */

#ifdef __cplusplus
}
#endif

#endif /* PROTOCOL_H */
