// FoxTerm | Atomic.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 原子操作类，提供线程安全的 64 位整数运算
/// 适用于无需复杂锁机制的高频计数场景，如流量监控或任务计数
public final class Atomic {
    /// 内部存储的 64 位整型数值指针，用于执行底层硬件级原子操作
    private let _value: UnsafeMutablePointer<Int64>

    /// 初始化原子实例
    /// - Parameter initialValue: 初始值，默认为 0
    public init(_ initialValue: Int64 = 0) {
        _value = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        _value.initialize(to: initialValue)
    }

    deinit {
        _value.deinitialize(count: 1)
        _value.deallocate()
    }
}

public extension Atomic {
    /// 原子级累加指定的 64 位整数
    /// 使用系统级原子指令确保多线程并发累加时的完整性
    /// - Parameter delta: 累加的增量
    func add(_ delta: Int64) {
        OSAtomicAdd64Barrier(delta, _value)
    }

    /// 原子级累加标准的 Int 整数
    func add(_ delta: Int) {
        add(Int64(delta))
    }

    /// 原子级累加 32 位整数
    func add(_ delta: Int32) {
        add(Int64(delta))
    }

    /// 以原子方式读取当前数值
    /// 确保在读取过程中不会受到其他线程写入操作的干扰
    var load: Int64 {
        // 读取时加屏障，保证数据同步与内存可见性
        OSAtomicAdd64Barrier(0, _value)
    }
}
