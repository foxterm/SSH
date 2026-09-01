// FoxTerm | Mutex.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 互斥锁类，基于纯 Swift 与系统底层的 os_unfair_lock 实现
/// 用于在多线程环境下保护共享资源（如 SSH 会话指针）
public final class Mutex {
    private let _lock: UnsafeMutablePointer<os_unfair_lock>

    /// 初始化并分配互斥锁资源
    public init() {
        _lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock())
    }

    deinit {
        // 销毁并释放指针内存
        _lock.deinitialize(count: 1)
        _lock.deallocate()
        #if DEBUG
            print("♻️", "Mutex 资源已释放")
        #endif
    }
}

public extension Mutex {
    /// 阻塞当前线程直到获得锁
    func lock() {
        os_unfair_lock_lock(_lock)
    }

    /// 释放锁，允许其他线程竞争
    func unlock() {
        os_unfair_lock_unlock(_lock)
    }

    /// 尝试获取锁，不会阻塞当前线程
    /// - Returns: 获取成功返回 true，否则返回 false
    func trylock() -> Bool {
        os_unfair_lock_trylock(_lock)
    }

    /// 自动锁定执行闭包，并在执行结束后自动解锁（支持抛出错误）
    /// - Parameter body: 需要在锁保护下执行的代码块
    /// - Returns: 闭包执行的返回值
    @discardableResult
    func with<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer {
            // 使用 defer 确保即使代码块抛出异常或中途退出也能正常解锁
            self.unlock()
        }
        return try body()
    }

    /// `with` 方法的别名，符合标准库命名习惯
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        try with(body)
    }

    /// 针对无返回值闭包的锁封装
    func withVoid(_ body: () throws -> Void) rethrows {
        try with(body)
    }
}
