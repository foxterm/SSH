// FoxTerm | WaitGroup.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 等待组类，提供一种同步机制，用于等待多个并发任务全部完成
/// 类似于 Go 语言中的 sync.WaitGroup
public final class WaitGroup {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var count: Int32 = 0

    /// 初始化等待组
    public init() {}

    deinit {
        #if DEBUG
            print("♻️", "WaitGroup 资源已释放")
        #endif
    }
}

public extension WaitGroup {
    /// 增加等待组的计数器（默认为 1）
    /// - Parameter n: 增加的数量
    func add(_ n: Int32 = 1) {
        guard n > 0 else { return }
        lock.lock()
        count += n
        lock.unlock()
    }

    /// 减少等待组的计数器（通常在任务结束时调用）
    /// 当计数器归零时，唤醒所有处于 `wait()` 状态的线程
    func done() {
        lock.lock()
        guard count > 0 else {
            lock.unlock()
            assertionFailure("WaitGroup counter negative: done() called more times than add()")
            return
        }

        count -= 1
        let isZero = (count == 0)
        lock.unlock()

        // 计数归零时释放信号量（发送通知）
        if isZero {
            semaphore.signal()
        }
    }

    /// 阻塞当前线程，直到等待组的计数器变为 0
    func wait() {
        lock.lock()
        let currentCount = count
        lock.unlock()

        // 如果计数本身就为 0，直接返回无需等待
        if currentCount == 0 {
            return
        }

        // 阻塞等待
        semaphore.wait()

        // 唤醒后再次发送 signal，保证如果有多个线程在 wait() 都能被依次唤醒（广播机制）
        semaphore.signal()
    }

    /// 在等待组上下文中执行闭包，自动处理 add() 和 done()
    /// 支持同步闭包与抛出异常的情况
    /// - Parameter body: 需要执行的任务闭包
    /// - Returns: 闭包执行的返回值
    @discardableResult
    func with<T>(_ body: () throws -> T) rethrows -> T {
        add()
        defer {
            self.done()
        }
        return try body()
    }

    /// 针对无返回值闭包的等待组封装
    func withVoid(_ body: () throws -> Void) rethrows {
        try with(body)
    }
}
