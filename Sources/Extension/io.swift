// FoxTerm | io.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Foundation

/// 基础 IO 操作类，提供流式数据拷贝及异步调用封装
public class io {
    /// 专门用于处理阻塞 IO 的后台队列，避免 Task.detached 耗尽 Swift 协程池
    private static let ioQueue = DispatchQueue(label: "app.foxterm.io.queue", attributes: .concurrent)

    /// 将数据从输入流异步拷贝到输出流
    public static func Copy(
        _ r: InputStream,
        _ w: OutputStream,
        _ bufferSize: Int = 0x4000,
        _ progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Int {
        await Call {
            Copy(w, r, bufferSize, progress)
        }
    }

    /// 同步拷贝操作（参数顺序兼容版本 A）
    public static func Copy(
        _ r: InputStream,
        _ w: OutputStream,
        _ bufferSize: Int = 0x4000,
        _ progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) -> Int {
        Copy(w, r, bufferSize, progress)
    }

    /// 异步拷贝操作（参数顺序兼容版本 B）
    public static func Copy(
        _ w: OutputStream,
        _ r: InputStream,
        _ bufferSize: Int = 0x4000,
        _ progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Int {
        await Call {
            Copy(w, r, bufferSize, progress)
        }
    }

    /// 核心拷贝逻辑实现（同步）
    /// 负责流的生命周期管理（Open/Close）、缓冲区分配及错误处理
    /// - Returns: 成功返回总字节数，失败返回负数错误码
    public static func Copy(
        _ w: OutputStream,
        _ r: InputStream,
        _ bufferSize: Int = 0x4000,
        _ progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) -> Int {
        if r.streamStatus == .notOpen {
            r.open()
        }
        if w.streamStatus == .notOpen {
            w.open()
        }
        defer {
            w.close()
            r.close()
        }

        // 分配缓冲区
        let buffer = Buffer<UInt8>(bufferSize)

        var total = 0

        while r.hasBytesAvailable {
            let nread = r.read(buffer.buffer, maxLength: buffer.count)

            if nread < 0 {
                return nread
            }
            if nread == 0 {
                break
            }

            var offset = 0

            while offset < nread {
                let written = w.write(buffer.buffer.advanced(by: offset), maxLength: nread - offset)
                if written < 0 {
                    return written
                }

                offset += written
                total += written
            }

            if !progress(total) {
                return total
            }
        }
        return total
    }

    /// 通用的异步桥接工具函数
    /// 修复：使用 DispatchQueue 代替 Task.detached，避免同步阻塞 IO 耗尽 Swift 协程池
    public static func Call<T>(_ callback: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                let result = callback()
                continuation.resume(returning: result)
            }
        }
    }
}
