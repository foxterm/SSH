// FoxTerm | Mutex.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libetos

/// 互斥锁类，基于 libetos 提供的底层同步原语实现
/// 用于在多线程环境下保护共享资源（如 SSH 会话指针）
public class Mutex {
    /// 全局共享的互斥锁实例（单例）
    public static let shared: Mutex = .init()

    /// libetos 内部定义的互斥锁结构体
    var _m: etos_sync_mutex_t = .init()

    /// 初始化并分配互斥锁资源
    public init() {
        etos_sync_mutex_init(&_m)
    }

    deinit {
        // 销毁锁资源，防止内存泄露或挂起
        etos_sync_mutex_destroy(&_m)
        #if DEBUG
            print("♻️", "Mutex 资源已释放")
        #endif
    }
}

public extension Mutex {
    /// 阻塞当前线程直到获得锁
    func lock() {
        etos_sync_mutex_lock(&_m)
    }

    /// 释放锁，允许其他线程竞争
    func unlock() {
        etos_sync_mutex_unlock(&_m)
    }

    /// 尝试获取锁，不会阻塞当前线程
    /// - Returns: 获取成功返回 true，否则返回 false
    func trylock() -> Bool {
        etos_sync_mutex_trylock(&_m) == 0
    }

    /// 自动锁定执行闭包，并在执行结束后自动解锁（推荐用法）
    /// - Parameter body: 需要在锁保护下执行的代码块
    /// - Returns: 闭包执行的返回值
    func with<T>(_ body: () -> T) -> T {
        lock()
        defer {
            // 使用 defer 确保即使代码块抛出异常或中途退出也能正常解锁
            self.unlock()
        }
        return body()
    }

    /// `with` 方法的别名，符合标准库命名习惯
    func withLock<T>(_ body: () -> T) -> T {
        with(body)
    }

    /// 针对无返回值闭包的锁封装
    func withVoid(_ body: () -> Void) {
        with(body)
    }
}
