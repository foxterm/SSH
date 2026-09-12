#ifndef ETOS_SYNC_H
#define ETOS_SYNC_H

#include <os/lock.h>
#include <pthread.h>
#include <stdatomic.h>

/* ------------------------------------------------------------
   并发与同步控制 (macOS / POSIX)
   ------------------------------------------------------------ */

typedef struct {
  os_unfair_lock lock; // 使用 Apple 原生轻量锁替代 pthread_mutex
} etos_sync_mutex_t;

typedef struct {
  int count;
  pthread_mutex_t lock;
  pthread_cond_t cv;
} etos_sync_waitgroup_t;

/** 初始化互斥锁 */
void etos_sync_mutex_init(etos_sync_mutex_t *m);

/** 加锁 */
void etos_sync_mutex_lock(etos_sync_mutex_t *m);

/** 尝试加锁 */
int etos_sync_mutex_trylock(etos_sync_mutex_t *m);

/** 解锁 */
void etos_sync_mutex_unlock(etos_sync_mutex_t *m);

/** 销毁互斥锁 */
void etos_sync_mutex_destroy(etos_sync_mutex_t *m);

/** 初始化等待组 */
void etos_sync_waitgroup_init(etos_sync_waitgroup_t *wg);

/** 设置计数 */
void etos_sync_waitgroup_add(etos_sync_waitgroup_t *wg, int delta);

/** 标记任务完成 */
void etos_sync_waitgroup_done(etos_sync_waitgroup_t *wg);

/** 等待任务归零 */
void etos_sync_waitgroup_wait(etos_sync_waitgroup_t *wg);

/** 销毁等待组 */
void etos_sync_waitgroup_destroy(etos_sync_waitgroup_t *wg);

/* ------------------------------------------------------------
   原子操作
   ------------------------------------------------------------ */

/** 原子读取 */
int64_t etos_sync_atomic_load(volatile int64_t *addr);

/** 原子写入 */
void etos_sync_atomic_store(volatile int64_t *addr, int64_t value);

/** 原子加 */
int64_t etos_sync_atomic_add(volatile int64_t *addr, int64_t delta);

/** 原子减 */
int64_t etos_sync_atomic_sub(volatile int64_t *addr, int64_t delta);

/** 原子交换 */
int64_t etos_sync_atomic_exchange(volatile int64_t *addr, int64_t value);

/** 原子比较交换 (CAS) */
int64_t etos_sync_atomic_cas(volatile int64_t *addr, int64_t expected, int64_t desired);

#endif /* ETOS_SYNC_H */
