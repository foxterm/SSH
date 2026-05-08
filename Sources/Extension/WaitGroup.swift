// FoxTerm | WaitGroup.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libetos

/// 等待组类，提供一种同步机制，用于等待多个并发任务全部完成
/// 类似于 Go 语言中的 sync.WaitGroup
public class WaitGroup {
    /// 全局共享的等待组实例
    public static let shared: WaitGroup = .init()

    /// libetos 内部定义的等待组结构体
    var _wg: etos_sync_waitgroup_t = .init()

    /// 初始化并分配等待组资源
    public init() {
        etos_sync_waitgroup_init(&_wg)
    }

    deinit {
        // 销毁资源，确保底层信号量被正确回收
        etos_sync_waitgroup_destroy(&_wg)
        #if DEBUG
            print("♻️", "WaitGroup 资源已释放")
        #endif
    }
}

public extension WaitGroup {
    /// 增加等待组的计数器（默认为 1）
    /// 在启动一个新的并发任务前调用
    /// - Parameter n: 增加的数量
    func add(_ n: Int32 = 1) {
        etos_sync_waitgroup_add(&_wg, n)
    }

    /// 减少等待组的计数器（通常在任务结束时调用）
    /// 当计数器归零时，会唤醒所有处于 `wait()` 状态的线程
    func done() {
        etos_sync_waitgroup_done(&_wg)
    }

    /// 阻塞当前线程，直到等待组的计数器变为 0
    func wait() {
        etos_sync_waitgroup_wait(&_wg)
    }

    /// 在等待组上下文中执行闭包，自动处理 add() 和 done()
    /// 推荐用于简单的同步包裹，确保任务结束后计数器一定能递减
    /// - Parameter body: 需要执行的任务闭包
    /// - Returns: 闭包执行的返回值
    func with<T>(_ body: () -> T) -> T {
        add()
        defer {
            // 使用 defer 确保即便任务抛出异常也能正确执行 done()
            self.done()
        }
        return body()
    }

    /// 针对无返回值闭包的等待组封装
    func withVoid(_ body: () -> Void) {
        with(body)
    }
}
