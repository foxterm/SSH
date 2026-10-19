// FoxTerm | ClosureOutputStream.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 将 OutputStream 的写入操作实时转接给 Swift 闭包的内存流
///
/// 用于 `exec`/`compress`/`decompress` 等命令执行时，将 stdout/stderr 数据流
/// 实时解码后通过闭包回调给调用方（如 UI 日志面板），无需先缓存到内存再返回。
public final class ClosureOutputStream: OutputStream {
    /// 数据写入回调闭包
    private let onData: (Data) -> Void
    /// 内部流状态跟踪
    private var _streamStatus: Stream.Status = .notOpen

    /// 初始化闭包输出流
    /// - Parameter onData: 每次有数据写入时触发的回调闭包
    public init(onData: @escaping (Data) -> Void) {
        self.onData = onData
        super.init(toMemory: ())
    }

    override public func open() {
        _streamStatus = .open
    }

    override public func close() {
        _streamStatus = .closed
    }

    override public var streamStatus: Stream.Status {
        _streamStatus
    }

    override public func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        guard len > 0 else { return 0 }
        let data = Data(bytes: buffer, count: len)
        onData(data)
        return len
    }

    override public var hasSpaceAvailable: Bool {
        true
    }
}
