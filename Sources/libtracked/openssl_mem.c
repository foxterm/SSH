#include "openssl_mem.h"
#include <openssl/crypto.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static _Atomic size_t g_openssl_allocated_bytes = 0;
static pthread_once_t g_init_once = PTHREAD_ONCE_INIT;
static int g_init_result = 0;

// 自定义 Malloc
static void *custom_openssl_malloc(size_t num, const char *file, int line) {
  (void)file;
  (void)line;
  if (num == 0)
    return NULL;

  size_t total_size = num + sizeof(size_t);
  void *ptr = malloc(total_size);
  if (!ptr)
    return NULL;

  *(size_t *)ptr = num;
  atomic_fetch_add(&g_openssl_allocated_bytes, num);

  return (char *)ptr + sizeof(size_t);
}

// 自定义 Realloc
static void *custom_openssl_realloc(void *addr, size_t num, const char *file,
                                    int line) {
  (void)file;
  (void)line;
  if (!addr)
    return custom_openssl_malloc(num, file, line);
  if (num == 0) {
    void *real_ptr = (char *)addr - sizeof(size_t);
    size_t old_count = *(size_t *)real_ptr;
    atomic_fetch_sub(&g_openssl_allocated_bytes, old_count);
    free(real_ptr);
    return NULL;
  }

  void *old_real_ptr = (char *)addr - sizeof(size_t);
  size_t old_count = *(size_t *)old_real_ptr;

  size_t new_total_size = num + sizeof(size_t);
  void *new_real_ptr = realloc(old_real_ptr, new_total_size);
  if (!new_real_ptr)
    return NULL;

  *(size_t *)new_real_ptr = num;

  if (num > old_count) {
    atomic_fetch_add(&g_openssl_allocated_bytes, num - old_count);
  } else {
    atomic_fetch_sub(&g_openssl_allocated_bytes, old_count - num);
  }

  return (char *)new_real_ptr + sizeof(size_t);
}

// 自定义 Free
static void custom_openssl_free(void *ptr, const char *file, int line) {
  (void)file;
  (void)line;
  if (!ptr)
    return;

  void *real_ptr = (char *)ptr - sizeof(size_t);
  size_t count = *(size_t *)real_ptr;

  atomic_fetch_sub(&g_openssl_allocated_bytes, count);
  free(real_ptr);
}

// 实际执行挂载的内部回调
static void do_openssl_mem_init(void) {
  g_init_result = CRYPTO_set_mem_functions(
      custom_openssl_malloc, custom_openssl_realloc, custom_openssl_free);
}

// 安全初始化入口
int openssl_mem_tracker_init(void) {
  pthread_once(&g_init_once, do_openssl_mem_init);
  return g_init_result;
}

// 获取实时内存大小
size_t openssl_get_current_memory_usage(void) {
  return atomic_load(&g_openssl_allocated_bytes);
}
