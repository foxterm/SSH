// FoxTerm | Mutex.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libetos

/// 互斥锁类，基于 libetos 提供的底层同步原语实现
/// 用于在多线程环境下保护共享资源（如 SSH 会话指针）
public class Mutex {
    /// libetos 内部定义的互斥锁结构体
    private var _m: etos_sync_mutex_t = .init()

    /// 初始化互斥锁
    public init() {
        etos_sync_mutex_init(&_m)
    }

    deinit {
        // 销毁锁资源
        etos_sync_mutex_destroy(&_m)
        #if DEBUG
            print("♻️", "Mutex 资源已释放")
        #endif
    }
}

public extension Mutex {
    /// 阻塞当前线程直到获得锁
    @inline(__always)
    func lock() {
        etos_sync_mutex_lock(&_m)
    }

    /// 释放锁，允许其他线程竞争
    @inline(__always)
    func unlock() {
        etos_sync_mutex_unlock(&_m)
    }

    /// 尝试获取锁，不会阻塞当前线程
    /// - Returns: 获取成功返回 true，否则返回 false
    @inline(__always)
    func trylock() -> Bool {
        // 修正：C 实现中成功返回 1 (非 0)，失败返回 0
        etos_sync_mutex_trylock(&_m) != 0
    }

    /// 自动锁定执行闭包，并在执行结束后自动解锁（支持抛出异常与返回值）
    /// - Parameter body: 需要在锁保护下执行的代码块
    /// - Returns: 闭包执行的返回值
    @discardableResult
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }

    /// 针对无返回值闭包的锁定封装
    @discardableResult
    @inline(__always)
    func withVoid(_ body: () -> Void) {
        withLock(body)
    }
}
