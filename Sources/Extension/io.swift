// FoxTerm | io.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Foundation

/// 基础 IO 操作类，提供流式数据拷贝及异步调用封装
public class io {
    /// 将数据从输入流异步拷贝到输出流
    /// - Parameters:
    ///   - r: 数据源输入流
    ///   - w: 目标输出流
    ///   - bufferSize: 拷贝时使用的缓冲区大小，默认 16KB (0x4000)
    ///   - progress: 进度回调闭包。参数为累计发送字节数，返回 `false` 可中止拷贝。
    /// - Returns: 实际拷贝的总字节数
    public static func Copy(
        _ r: InputStream,
        _ w: OutputStream,
        _ bufferSize: Int = 0x4000,
        _ progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Int {
        await call {
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
        await call {
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
        // 确保流在操作前开启
        w.open()
        r.open()
        defer {
            // 操作完成后确保流已关闭，释放资源
            w.close()
            r.close()
        }

        // 分配指定的缓冲区
        let buffer: Buffer<CChar> = .init(bufferSize)
        var total = 0

        // 循环读取直到流结束
        while r.hasBytesAvailable {
            let nread = r.read(buffer.buffer, maxLength: buffer.count)
            guard nread > 0 else {
                if nread < 0 { return nread } // 读取出错
                break // 读取完毕
            }

            var offset = 0
            // 确保将读取到的数据完整写入输出流
            while offset < nread, w.hasSpaceAvailable {
                let written = w.write(buffer.buffer + offset, maxLength: nread - offset)
                if written < 0 { return written } // 写入出错
                offset += written
                total += written
            }

            // 触发进度回调，若外部返回 false 则提前中止传输（如用户点击取消）
            if !progress(total) {
                return total
            }
        }
        return total
    }

    /// 通用的异步桥接工具函数
    /// 将基于同步回调的操作转换为 Swift 的 async 异步流
    /// - Parameters:
    ///   - callback: 需要在后台执行的任务闭包
    /// - Returns: 任务执行的返回值
    public static func call<T>(_ callback: @escaping () -> T) async -> T {
        await withUnsafeContinuation { continuation in
            let ret: T = callback()
            continuation.resume(returning: ret)
        }
    }
}
