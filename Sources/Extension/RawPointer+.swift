// FoxTerm | RawPointer+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// `UnsafeRawPointer` 的扩展，提供更便捷的数据加载方法。
public extension UnsafeRawPointer {
    /// 从原始内存指针中加载指定类型 `T` 的数据。
    ///
    /// - Returns: 从内存中读取到的 `T` 类型数据。
    /// - Note: 本方法假设内存地址已针对类型 `T` 正确对齐。若处理未对齐的二进制字节流，
    ///         建议使用 `loadUnaligned(fromByteOffset:as:)`。
    func load<T>() -> T {
        load(as: T.self)
    }

    /// 从原始内存指针中加载非对齐的指定类型 `T` 数据（对内存对齐更安全）。
    ///
    /// - Returns: 从内存中读取到的 `T` 类型数据。
    func loadUnaligned<T>() -> T {
        loadUnaligned(as: T.self)
    }
}

/// `UnsafeMutablePointer` 的扩展，提供地址转换与便捷的数据加载功能。
public extension UnsafeMutablePointer {
    /// 获取指向当前可变指针内存地址的 `UnsafeRawPointer`（不可变原始内存指针）。
    ///
    /// - Returns: 当前内存地址的原始指针表示。
    var address: UnsafeRawPointer {
        UnsafeRawPointer(self)
    }

    /// 从当前指针指向的内存位置加载指定类型 `T` 的值。
    ///
    /// - Returns: 从内存中读取到的 `T` 类型值。
    /// - Note: 假设该内存区域已正确初始化且满足类型 `T` 的内存对齐要求。
    func load<T>() -> T {
        address.load()
    }
}
