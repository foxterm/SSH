// FoxTerm | WaitGroup.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin

public final class WaitGroup {
    private var mutex = pthread_mutex_t()
    private var cond = pthread_cond_t()
    private var count: Int32 = 0

    public init() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
    }

    deinit {
        pthread_mutex_destroy(&mutex)
        pthread_cond_destroy(&cond)
        #if DEBUG
            print("♻️", "WaitGroup")
        #endif
    }
}

public extension WaitGroup {
    /// 增加等待组的计数器
    @inline(__always)
    func add(_ n: Int32 = 1) {
        guard n > 0 else { return }
        pthread_mutex_lock(&mutex)
        count += n
        pthread_mutex_unlock(&mutex)
    }

    /// 减少等待组的计数器
    @inline(__always)
    func done() {
        pthread_mutex_lock(&mutex)
        guard count > 0 else {
            pthread_mutex_unlock(&mutex)
            assertionFailure("WaitGroup counter negative: done() called more times than add()")
            return
        }

        count -= 1
        let isZero = (count == 0)
        pthread_mutex_unlock(&mutex)

        // 计数归零时，触发 C 级别的条件变量广播（原生唤醒所有 wait 线程）
        if isZero {
            pthread_cond_broadcast(&cond)
        }
    }

    /// 阻塞当前线程，直到计数归零
    @inline(__always)
    func wait() {
        pthread_mutex_lock(&mutex)
        // 遵循 POSIX C 标准规范：利用 while 循环防止虚假唤醒 (Spurious Wakeup)
        while count > 0 {
            // pthread_cond_wait 会在阻塞前自动释放锁，唤醒后自动重新获取锁
            pthread_cond_wait(&cond, &mutex)
        }
        pthread_mutex_unlock(&mutex)
    }

    /// 在 WaitGroup 上下文中执行任务，自动管理 add 与 done
    @discardableResult
    @inline(__always)
    func with<T>(_ body: () throws -> T) rethrows -> T {
        add()
        defer { done() }
        return try body()
    }

    @inline(__always)
    func withVoid(_ body: () throws -> Void) rethrows {
        try with(body)
    }
}
