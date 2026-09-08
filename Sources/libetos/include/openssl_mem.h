#ifndef OPENSSL_MEM_H
#define OPENSSL_MEM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化 OpenSSL 内存监控（必须在所有 OpenSSL API 调用前执行）
 * @return int 1 成功，0 失败
 */
int openssl_mem_tracker_init(void);

/**
 * @brief 获取当前 OpenSSL 占用的实时内存大小
 * @return size_t 当前已分配的内存字节数 (Bytes)
 */
size_t openssl_get_current_memory_usage(void);

#ifdef __cplusplus
}
#endif

#endif // OPENSSL_MEM_H
