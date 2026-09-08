#ifndef LIBSSH2_MEM_H
#define LIBSSH2_MEM_H

#include <libssh2.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 安全的 libssh2 全局初始化（线程安全，仅执行一次）
 * @return int 0 表示成功，非 0 表示失败
 */
int ssh2_global_init_safe(void);

/**
 * @brief 获取当前 libssh2 占用的实时内存大小 (Bytes)
 */
size_t libssh2_get_current_memory_usage(void);

/**
 * @brief 创建带内存监控功能的 Session（内部会自动调用 safe 初始化）
 */
LIBSSH2_SESSION *ssh2_session_init_tracked(void *abstract);

#ifdef __cplusplus
}
#endif

#endif // LIBSSH2_MEM_H
