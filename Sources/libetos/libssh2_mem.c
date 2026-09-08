#include "libssh2_mem.h"
#include "openssl_mem.h" // 包含 OpenSSL 内存监控头文件
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

// 原子变量记录 libssh2 专属实时内存（字节数）
static _Atomic size_t g_allocated_bytes = 0;

// 全局初始化控制变量
static pthread_once_t g_libssh2_init_once = PTHREAD_ONCE_INIT;
static int g_libssh2_init_result = -1;

// 自定义 Malloc
static LIBSSH2_ALLOC_FUNC(custom_malloc) {
  (void)abstract;
  if (count == 0)
    return NULL;

  size_t total_size = count + sizeof(size_t);
  void *ptr = malloc(total_size);
  if (!ptr)
    return NULL;

  *(size_t *)ptr = count;
  atomic_fetch_add(&g_allocated_bytes, count);

  return (char *)ptr + sizeof(size_t);
}

// 自定义 Free
static LIBSSH2_FREE_FUNC(custom_free) {
  (void)abstract;
  if (!ptr)
    return;

  void *real_ptr = (char *)ptr - sizeof(size_t);
  size_t count = *(size_t *)real_ptr;

  atomic_fetch_sub(&g_allocated_bytes, count);
  free(real_ptr);
}

// 自定义 Realloc
static LIBSSH2_REALLOC_FUNC(custom_realloc) {
  (void)abstract;
  if (!ptr)
    return custom_malloc(count, abstract);
  if (count == 0) {
    custom_free(ptr, abstract);
    return NULL;
  }

  void *old_real_ptr = (char *)ptr - sizeof(size_t);
  size_t old_count = *(size_t *)old_real_ptr;

  size_t new_total_size = count + sizeof(size_t);
  void *new_real_ptr = realloc(old_real_ptr, new_total_size);
  if (!new_real_ptr)
    return NULL;

  *(size_t *)new_real_ptr = count;

  if (count > old_count) {
    atomic_fetch_add(&g_allocated_bytes, count - old_count);
  } else {
    atomic_fetch_sub(&g_allocated_bytes, old_count - count);
  }

  return (char *)new_real_ptr + sizeof(size_t);
}

// 内部单次调用的全局初始化回调
static void do_libssh2_global_init(void) {
  // 1. 严格优先挂载 OpenSSL 内存 Hook
  // 必须在 libssh2_init(0) 之前，否则 OpenSSL 提前初始化后 Hook 会失败
  openssl_mem_tracker_init();

  // 2. 初始化 libssh2 全局环境
  g_libssh2_init_result = libssh2_init(0);
}

// 安全的全局初始化（线程安全，仅执行一次）
int ssh2_global_init_safe(void) {
  pthread_once(&g_libssh2_init_once, do_libssh2_global_init);
  return g_libssh2_init_result;
}

// 获取 libssh2 本身占用的实时内存
size_t libssh2_get_current_memory_usage(void) {
  return atomic_load(&g_allocated_bytes);
}

// 初始化 Session 接口实现（带有自动全局安全初始化保护）
LIBSSH2_SESSION *ssh2_session_init_tracked(void *abstract) {
  // 自动触发安全的全局初始化
  if (ssh2_global_init_safe() != 0) {
    return NULL;
  }

  return libssh2_session_init_ex(custom_malloc, custom_free, custom_realloc,
                                 abstract);
}
