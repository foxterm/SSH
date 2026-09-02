// FoxTerm | Atomic.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Atomics
import Foundation

public final class Atomic {
    private let value: ManagedAtomic<Int64>

    public init(_ initialValue: Int64 = 0) {
        value = ManagedAtomic(initialValue)
    }

    deinit {
        #if DEBUG
            print("♻️", "Atomic")
        #endif
    }
}

public extension Atomic {
    /// 原子级累加（使用 CPU 原生指令，性能最高）
    @inline(__always)
    func add(_ delta: Int64) {
        value.wrappingIncrement(by: delta, ordering: .relaxed)
    }

    @inline(__always)
    func add(_ delta: Int) {
        add(Int64(delta))
    }

    @inline(__always)
    func add(_ delta: Int32) {
        add(Int64(delta))
    }

    /// 原子级读取当前数值
    var load: Int64 {
        @inline(__always)
        get {
            value.load(ordering: .relaxed)
        }
    }

    /// 原子级写入/重置数值
    @inline(__always)
    func store(_ newValue: Int64) {
        value.store(newValue, ordering: .relaxed)
    }
}
