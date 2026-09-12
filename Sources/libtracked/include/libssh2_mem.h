#ifndef LIBSSH2_MEM_H
#define LIBSSH2_MEM_H

#include <libssh2.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 创建带内存监控功能的 Session（内部会自动调用 safe 初始化）
 */
LIBSSH2_SESSION *ssh2_session_init_tracked(void *abstract);

#ifdef __cplusplus
}
#endif

#endif // LIBSSH2_MEM_H
