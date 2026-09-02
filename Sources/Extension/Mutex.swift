// FoxTerm | Mutex.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin

/// 基于 C 语言 pthread_mutex 的高性能互斥锁
public final class Mutex {
    public static let shared: Mutex = .init()
    private var mutex = pthread_mutex_t()

    public init() {
        // 初始化 C 语言互斥锁
        pthread_mutex_init(&mutex, nil)
    }

    deinit {
        // 销毁 C 语言互斥锁资源
        pthread_mutex_destroy(&mutex)
    }
}

public extension Mutex {
    @inline(__always)
    func lock() {
        pthread_mutex_lock(&mutex)
    }

    @inline(__always)
    func unlock() {
        pthread_mutex_unlock(&mutex)
    }

    @inline(__always)
    func tryLock() -> Bool {
        pthread_mutex_trylock(&mutex) == 0
    }

    /// 执行闭包并自动管理锁的释放
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
