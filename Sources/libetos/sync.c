#include "sync.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>

// ---------------------------------------------------------
// 互斥锁：macOS (POSIX) 实现
// ---------------------------------------------------------

void etos_sync_mutex_init(etos_sync_mutex_t *m) {
  pthread_mutex_init(&m->mutex, NULL);
}

void etos_sync_mutex_lock(etos_sync_mutex_t *m) {
  pthread_mutex_lock(&m->mutex);
}

int etos_sync_mutex_trylock(etos_sync_mutex_t *m) {
  return pthread_mutex_trylock(&m->mutex) == 0;
}

void etos_sync_mutex_unlock(etos_sync_mutex_t *m) {
  pthread_mutex_unlock(&m->mutex);
}

void etos_sync_mutex_destroy(etos_sync_mutex_t *m) {
  pthread_mutex_destroy(&m->mutex);
}

// ---------------------------------------------------------
// 等候组：macOS (POSIX) 实现
// ---------------------------------------------------------

void etos_sync_waitgroup_init(etos_sync_waitgroup_t *wg) {
  wg->count = 0;
  pthread_mutex_init(&wg->lock, NULL);
  pthread_cond_init(&wg->cv, NULL);
}

void etos_sync_waitgroup_add(etos_sync_waitgroup_t *wg, int delta) {
  pthread_mutex_lock(&wg->lock);

  wg->count += delta;
  if (wg->count == 0) {
    pthread_cond_broadcast(&wg->cv);
  } else if (wg->count < 0) {
    pthread_mutex_unlock(&wg->lock);
    exit(EXIT_FAILURE);
  }

  pthread_mutex_unlock(&wg->lock);
}

void etos_sync_waitgroup_done(etos_sync_waitgroup_t *wg) {
  etos_sync_waitgroup_add(wg, -1);
}

void etos_sync_waitgroup_wait(etos_sync_waitgroup_t *wg) {
  pthread_mutex_lock(&wg->lock);

  while (wg->count > 0) {
    pthread_cond_wait(&wg->cv, &wg->lock);
  }

  pthread_mutex_unlock(&wg->lock);
}

void etos_sync_waitgroup_destroy(etos_sync_waitgroup_t *wg) {
  pthread_mutex_destroy(&wg->lock);
  pthread_cond_destroy(&wg->cv);
}

// ---------------------------------------------------------
// 原子操作：C11 标准原子操作 (macOS / Clang 兼容)
// ---------------------------------------------------------

int64_t etos_sync_atomic_load(volatile int64_t *addr) {
  return atomic_load((_Atomic int64_t *)addr);
}

void etos_sync_atomic_store(volatile int64_t *addr, int64_t value) {
  atomic_store((_Atomic int64_t *)addr, value);
}

int64_t etos_sync_atomic_add(volatile int64_t *addr, int64_t delta) {
  return atomic_fetch_add((_Atomic int64_t *)addr, delta);
}

int64_t etos_sync_atomic_sub(volatile int64_t *addr, int64_t delta) {
  return atomic_fetch_sub((_Atomic int64_t *)addr, delta);
}

int64_t etos_sync_atomic_exchange(volatile int64_t *addr, int64_t value) {
  return atomic_exchange((_Atomic int64_t *)addr, value);
}

int64_t etos_sync_atomic_cas(volatile int64_t *addr, int64_t expected,
                             int64_t desired) {
  int64_t expected_local = expected;
  atomic_compare_exchange_strong((_Atomic int64_t *)addr, &expected_local,
                                 desired);
  return expected_local;
}
