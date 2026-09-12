#include "libssh2_mem.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

// 全局初始化控制变量
static pthread_once_t g_libssh2_init_once = PTHREAD_ONCE_INIT;
static int g_libssh2_init_result = -1;

// 内部单次调用的全局初始化回调
static void do_libssh2_global_init(void) {
  // 2. 初始化 libssh2 全局环境
  g_libssh2_init_result = libssh2_init(0);
}

// 安全的全局初始化（线程安全，仅执行一次）
int ssh2_global_init_safe(void) {
  pthread_once(&g_libssh2_init_once, do_libssh2_global_init);
  return g_libssh2_init_result;
}

// 初始化 Session 接口实现（带有自动全局安全初始化保护）
LIBSSH2_SESSION *ssh2_session_init_tracked(void *abstract) {
  // 自动触发安全的全局初始化
  if (ssh2_global_init_safe() != 0) {
    return NULL;
  }

  return libssh2_session_init_ex(NULL, NULL, NULL, abstract);
}
