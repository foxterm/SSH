// FoxTerm | Call.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Foundation

extension SSH {
    /// 异步执行返回整数类型的 libssh2 函数
    /// 通过 Continuation 将传统的阻塞/轮询逻辑包装为 Swift 并发模型
    /// - Parameter callback: 执行 libssh2 操作的闭包
    /// - Returns: 函数执行结果（通常为错误码或字节数）
    func callSSH2<T: FixedWidthInteger>(_ callback: @escaping () -> T) async -> T {
        await withUnsafeContinuation { continuation in
            let ret: T = callSSH2(callback)
            continuation.resume(returning: ret)
        }
    }

    /// 异步执行返回可选指针或对象的 libssh2 函数
    /// - Parameter callback: 执行 libssh2 操作的闭包
    /// - Returns: 函数执行结果，失败或需要等待时返回 nil
    func callSSH2<T>(_ callback: @escaping () -> T?) async -> T? {
        await withUnsafeContinuation { continuation in
            let ret: T? = callSSH2(callback)
            continuation.resume(returning: ret)
        }
    }

    /// 同步执行并处理 EAGAIN 重试逻辑（整数版本）
    /// 核心逻辑：当 libssh2 返回 EAGAIN 时，调用 waitsocket() 等待数据就绪后重试
    /// - Parameter callback: 执行 libssh2 操作的闭包
    /// - Returns: 最终执行结果
    func callSSH2<T: FixedWidthInteger>(_ callback: @escaping () -> T) -> T {
        var ret: T
        repeat {
            ret = channelPoll.mutex.with { callback() }
            // 如果返回 EAGAIN，说明当前 IO 未就绪，进入 waitsocket 挂起一小段时间后重试
            guard ret == T(LIBSSH2_ERROR_EAGAIN) else { break }
            guard waitSocket() else {
                break
            }
        } while ret == T(LIBSSH2_ERROR_EAGAIN)
        return ret
    }

    /// 同步执行并处理 EAGAIN 重试逻辑（指针/对象版本）
    /// - Parameter callback: 执行 libssh2 操作的闭包
    /// - Returns: 最终执行结果
    func callSSH2<T>(_ callback: @escaping () -> T?) -> T? {
        var ret: T?
        repeat {
            ret = channelPoll.mutex.with { callback() }
            // 只有当返回为 nil 且 errno 为 EAGAIN 时才进行重试
            guard ret == nil, rawSession != nil,
                  libssh2_session_last_errno(rawSession) == LIBSSH2_ERROR_EAGAIN
            else { break }
            guard waitSocket() else {
                break
            }
        } while ret == nil
        return ret
    }

    /// 响应 SSH 服务器主动发起的断开连接回调
    /// 匹配 libssh2 的 `libssh2_session_abstract_set` 毁掉签名
    func disconnect(
        sess _: UnsafeRawPointer,
        reason _: CInt,
        message _: UnsafePointer<CChar>,
        messageLen _: CInt,
        language _: UnsafePointer<CChar>,
        languageLen _: CInt
    ) {
        #if DEBUG
            print("SSH 会话已被远程服务器关闭")
        #endif
        // 释放会话资源
        freeSession()
    }

    /// 处理来自 libssh2 的调试追踪信息
    /// - Parameters:
    ///   - message: 原始消息指针
    ///   - messageLen: 消息长度
    func trace(message: UnsafePointer<CChar>, messageLen: Int) {
        #if DEBUG
            // 在调试模式下打印内部协议交互日志
            print(Data(bytes: message, count: messageLen).string ?? "--")
        #endif
    }
}
