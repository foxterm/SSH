// FoxTerm | Buffer.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libetos

/// 封装 C 语言实现的泛型缓冲区类
public class Buffer<T> {
    private var cBuffer: UnsafeMutablePointer<etos_buffer_t>?
    public let count: Int

    /// 指向底层内存区域的指针
    public var buffer: UnsafeMutablePointer<T> {
        cBuffer!.pointee.ptr.assumingMemoryBound(to: T.self)
    }

    /// 初始化指定容量的内存缓冲区
    public init(_ capacity: Int = MemoryLayout<T>.size) {
        count = capacity
        cBuffer = etos_buffer_create(MemoryLayout<T>.stride, capacity)
    }

    deinit {
        if let cBuffer {
            etos_buffer_free(cBuffer)
        }
        cBuffer = nil
        #if DEBUG
            print("♻️", "C-Buffer", count)
        #endif
    }
}

public extension Buffer {
    /// 返回包含缓冲区中前指定字节数的 Data 对象
    func data(_ count: Int) -> Data {
        guard let cBuffer else { return Data() }
        var data = Data(count: count)
        data.withUnsafeMutableBytes { targetBuffer in
            if let baseAddress = targetBuffer.baseAddress {
                etos_buffer_copy_bytes(cBuffer, baseAddress, count)
            }
        }
        return data
    }

    /// 获取缓冲区首地址指向的值
    var pointee: T {
        buffer.pointee
    }

    /// 将缓冲区地址作为原始只读指针返回
    var address: UnsafeRawPointer {
        UnsafeRawPointer(buffer)
    }
}

/// 组合“长度缓冲区”和“数据缓冲区”的结构体
public struct BufferData<V, L: FixedWidthInteger> {
    public let len: Buffer<L> = .init()
    public let buf: Buffer<V>

    public init(_ capacity: Int) {
        buf = Buffer<V>(capacity)
    }
}

public extension BufferData {
    /// 读取 len 地址对应的值作为字节长度，生成 Data 对象
    var data: Data {
        let length = len.address.load(as: Int.self)
        return Data(bytes: buf.buffer, count: length)
    }

    func data(count: Int) -> Data {
        Data(bytes: buf.buffer, count: count)
    }
}
