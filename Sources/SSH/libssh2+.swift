// FoxTerm | libssh2+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Foundation

/// SSH 自定义数据发送函数指针类型 (C 调用约定)
/// 用于劫持 libssh2 的底层发送行为，路由至 libetos 的 SSL 或 Socket 接口
///
/// - Parameters:
///   - socket: 套接字描述符
///   - buffer: 待发送数据的原始指针
///   - length: 待发送数据长度
///   - flags: 系统级发送标志
///   - abstract: libssh2 内部存储的上下文指针 (指向 SSH 实例包装对象)
/// - Returns: 实际发送的字节数，或负值错误码
typealias sendType =
    @convention(c) (libssh2_socket_t, UnsafeRawPointer, ssize_t, CInt, UnsafeRawPointer) -> Int

/// SSH 自定义数据接收函数指针类型 (C 调用约定)
/// 用于劫持 libssh2 的底层接收行为，支持统计接收流量
///
/// - Parameters:
///   - socket: 套接字描述符
///   - buffer: 用于存储接收数据的缓冲区指针
///   - length: 缓冲区容量
///   - flags: 系统级接收标志
///   - abstract: libssh2 内部存储的上下文指针
/// - Returns: 实际接收的字节数，或负值错误码
typealias recvType =
    @convention(c) (libssh2_socket_t, UnsafeMutableRawPointer, ssize_t, CInt, UnsafeRawPointer) ->
    Int

/// SSH 会话断开连接的回调函数类型
/// 当服务器主动断开或协议层触发断开时由 libssh2 调用
///
/// - Parameters:
///   - session: libssh2 会话原始指针
///   - reason: 断开原因代码
///   - message: 错误消息字符串
///   - message_len: 消息长度
///   - language: 语言标识字符串
///   - language_len: 语言标识长度
///   - abstract: 用户上下文指针 (用于寻回 Swift SSH 实例)
typealias disconnectType =
    @convention(c) (
        UnsafeRawPointer,
        CInt,
        UnsafePointer<CChar>,
        CInt,
        UnsafePointer<CChar>,
        CInt,
        UnsafeRawPointer
    ) -> Void

/// SSH 内部调试信息回调函数类型
/// 用于捕获 libssh2 内部产生的详细协议级调试日志
///
/// - Parameters:
///   - session: 会话原始指针
///   - level: 调试级别
///   - file: 产生调试信息的源码文件名
///   - line: 行号
///   - function: 函数名
///   - code: 相关的错误或状态码
///   - abstract: 用户上下文指针
typealias debugType =
    @convention(c) (
        UnsafeRawPointer,
        CInt,
        UnsafePointer<CChar>,
        CInt,
        UnsafePointer<CChar>,
        CInt,
        UnsafeRawPointer
    ) -> Void

/// 通用的无参数、无返回值 C 回调函数类型
/// 常用于简单的事件通知或无需参数的状态变更回调
typealias cbGenericType = @convention(c) () -> Void

typealias allocType = @convention(c) (Int, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer?
typealias freeType = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void
typealias reallocType = @convention(c) (UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer?
