// FoxTerm | Integer+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension FixedWidthInteger {
    /// 获取当前整数的原始字节数组（Byte Representation）。
    ///
    /// 利用 `withUnsafeBytes` 访问内存，并将底层字节转为 `[UInt8]`。
    /// 常用于低层网络协议传输、序列化或字节级位操作。
    ///
    /// - Returns: 代表当前整数内存二进制形式的 `UInt8` 字节数组。
    var bytes: [UInt8] {
        withUnsafeBytes(of: self) { Array($0) }
    }

    /// 注意：原先的 address 属性会造成悬空指针（Dangling Pointer）引发崩溃，故已安全修复。
    /// 在闭包作用域内安全地访问当前整数的原始内存指针。
    ///
    /// - Parameter body: 接收内存指针闭包。
    /// - Returns: 闭包执行的返回值。
    func withUnsafeRawPointer<Result>(_ body: (UnsafeRawPointer) throws -> Result) rethrows -> Result {
        try withUnsafePointer(to: self) { ptr in
            try body(UnsafeRawPointer(ptr))
        }
    }

    /// 截断并转换为 Int16（如溢出则截断高位，防止 Runtime 崩溃）。
    var int16: Int16 {
        Int16(truncatingIfNeeded: self)
    }

    /// 截断并转换为 Int32。
    var int32: Int32 {
        Int32(truncatingIfNeeded: self)
    }

    /// 截断并转换为 UInt32。
    var uint32: UInt32 {
        UInt32(truncatingIfNeeded: self)
    }

    /// 截断并转换为 Int。
    var int: Int {
        Int(truncatingIfNeeded: self)
    }

    /// 截断并转换为 UInt。
    var uint: UInt {
        UInt(truncatingIfNeeded: self)
    }

    /// 截断并转换为 UInt8。
    var uint8: UInt8 {
        UInt8(truncatingIfNeeded: self)
    }

    /// 截断并转换为 UInt16。
    var uint16: UInt16 {
        UInt16(truncatingIfNeeded: self)
    }

    /// 截断并转换为 Int64。
    var int64: Int64 {
        Int64(truncatingIfNeeded: self)
    }

    /// 截断并转换为 UInt64。
    var uint64: UInt64 {
        UInt64(truncatingIfNeeded: self)
    }

    /// 转换为 Double 浮点数。
    var double: Double {
        Double(self)
    }

    /// 格式化为网络网速文本表示（例如 "1.5 MB/s"）。
    var formatNetworkSpeed: String {
        Bytes.formatRate(int64)
    }

    /// 格式化为二进制单位字节文本（1024 进制，如 "1.0 KiB"）。
    var formatBinary: String {
        Bytes.formatBinary(int64)
    }

    /// 格式化为十进制单位字节文本（1000 进制，如 "1.0 KB"）。
    var byteFormatterDecimal: String {
        Bytes.formatDecimal(int64)
    }

    /// 格式化为通用字节文本。
    var formatBytes: String {
        Bytes.formatBytes(int64)
    }
}
