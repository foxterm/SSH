// FoxTerm | Buffer.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 泛型缓冲区类，用于手动管理连续内存块区域
public class Buffer<T> {
    /// 指向底层分配内存的指针
    public let buffer: UnsafeMutablePointer<T>
    /// 缓冲区容量（可容纳元素数量）
    public let count: Int

    /// 初始化指定容量的内存缓冲区
    /// - Parameter capacity: 缓冲区可容纳的元素数量，默认值为类型的字节大小 (MemoryLayout<T>.size)
    public init(_ capacity: Int = MemoryLayout<T>.size) {
        count = capacity
        // 按照类型对齐和步长分配原始内存
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: capacity * MemoryLayout<T>.stride,
            alignment: MemoryLayout<T>.alignment
        )
        // 将内存全部初始化填充为零
        rawPtr.initializeMemory(as: UInt8.self, repeating: 0, count: capacity * MemoryLayout<T>.stride)
        // 绑定原始内存至目标类型 T
        buffer = rawPtr.bindMemory(to: T.self, capacity: capacity)
    }

    deinit {
        // 析构时释放分配的内存，防止内存泄漏
        buffer.deallocate()
        #if DEBUG
            print("♻️", "Buffer", count)
        #endif
    }
}

public extension Buffer {
    /// 返回包含缓冲区中前指定字节数的 `Data` 对象
    ///
    /// - Parameter count: 包含在 `Data` 对象中的字节数量
    /// - Returns: 包含指定字节的 `Data` 对象
    func data(_ count: Int) -> Data {
        Data(bytes: buffer, count: count)
    }

    /// 获取缓冲区首地址指向的值
    /// - Returns: 缓冲区当前指向的 `T` 类型数据
    var pointee: T {
        buffer.pointee
    }

    /// 计算属性：将缓冲区地址作为原始只读指针 `UnsafeRawPointer` 返回
    ///
    /// 该属性提供对底层原始内存地址的访问，可用于低级内存操作
    ///
    /// - Returns: 代表缓冲区地址的 `UnsafeRawPointer`
    var address: UnsafeRawPointer {
        buffer.address
    }
}

/// 泛型结构体：组合包含“长度缓冲区”和“数据缓冲区”两个内存块
///
/// - Parameters:
///   - V: 数据缓冲区存储的数据类型
///   - L: 长度缓冲区存储的数据类型（须遵循固定宽度整数协议）
public struct BufferData<V, L: FixedWidthInteger> {
    /// 存储长度信息的 `Buffer<L>` 缓冲区，按默认容量初始化
    public let len: Buffer<L> = .init()

    /// 存储实际数据 `V` 的缓冲区
    ///
    /// - Note: 该缓冲区用于存储加密或传输数据
    public let buf: Buffer<V>

    /// 使用指定的容量初始化一个新的缓冲区实例
    ///
    /// - Parameter capacity: 数据缓冲区的容量
    public init(_ capacity: Int) {
        buf = Buffer<V>(capacity)
    }
}

public extension BufferData {
    /// 计算属性：获取包含数据缓冲区有效内容的 `Data` 对象
    /// 数据长度通过读取 `len` 缓冲区地址中的整数值决定
    /// - Returns: 包含缓冲区有效字节的 `Data` 对象
    var data: Data {
        Data(bytes: buf.buffer, count: len.address.load())
    }

    /// 读取数据缓冲区前指定字节数并转化为 `Data` 对象
    /// - Parameter count: 需要提取的字节数量
    /// - Returns: 包含指定字节的 `Data` 对象
    func data(count: Int) -> Data {
        Data(bytes: buf.buffer, count: count)
    }
}
