// FoxTerm | SSH.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation
import libetos

/// SSH 核心管理类，负责会话生命周期、底层 Socket 绑定及 libssh2 钩子函数分发
public class SSH {
    /// 内部版本号
    public static let version: String = LIBSSH2_VERSION
    /// 默认的 SSH Banner 标识，包含 libssh2 版本与 FoxTerm 应用版本
    public static let banner =
        "SSH-2.0-libssh2_\(LIBSSH2_VERSION_MAJOR).\(LIBSSH2_VERSION_MINOR).\(LIBSSH2_VERSION_PATCH)-\(Bundle.appName)_\(Bundle.currentAppVersion)"

    public let host: String
    public internal(set) var user: String = ""
    public let port: Int
    /// 连接超时时间（毫秒）
    public let timeout: Int
    /// 是否开启 zlib 压缩
    public let compress: Bool
    /// 客户端向服务器声明的协议标识串
    public let clientbanner: String

    public init(
        host: String, port: Int, compress: Bool = false, timeout: Int = 10 * 1000,
        banner: String = SSH.banner
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout > 0 ? timeout : 10 * 1000
        self.compress = compress
        // 确保 Banner 格式符合 SSH 规范（必须以 SSH- 开头）
        clientbanner = !banner.isEmpty && banner.hasPrefix("SSH-") ? banner : SSH.banner
    }

    /// 会话回调代理，用于同步连接状态、认证交互及流量监控
    public var sessionDelegate: SessionDelegate?

    /// 底层 TCP 套接字文件描述符
    public internal(set) var fd: Int32 = -1

    /// TCP 层参数配置
    public var ttl: Int32 = 0
    public var window: Int32 = 0
    public var scale: Int32 = 0

    /// 数据传输缓冲区大小，默认 64K
    public var bufferSize = 0x10000 // 64K

    /// 记录最近一次发生的错误描述
    public internal(set) var error: String?

    /// 原子计数器：实时统计发送的总字节数
    public let sendSize: Atomic = .init()
    /// 原子计数器：实时统计接收的总字节数
    public let recvSize: Atomic = .init()

    /// 用于保证 libssh2 会话在多线程环境下安全的互斥锁
    let mutex: Mutex = .init()
    /// 用于同步并发任务的等待组
    let wait: WaitGroup = .init()
    /// 用于管理通道的轮询器
    let channelPoll: ChannelPoll = .init()

    /// 指向 libssh2_session 的原始 C 指针
    public internal(set) var rawSession: OpaquePointer?

    // Keepalive 心跳包定时器
    // var timer: DispatchSourceTimer?

    // MARK: - Libssh2 C 回调函数静态封装

    // 这些闭包会被转换为 C 函数指针，并通过 libssh2_session_abstract 找回当前 Swift 实例

    /// 协议调试追踪回调
    let tracCallback: libssh2_trace_handler_func = { session, _, message, messageLen in
        guard let message else { return }
        // 通过 abstract 扩展将 C 指针还原为 Swift 对象并调用其 trace 方法
        libssh2_session_abstract(session).address.ssh.trace(
            message: message, messageLen: messageLen
        )
    }

    /// 远程断开连接通知回调
    let disconnectCallback: disconnectType = {
        sess, reason, message, messageLen, language, languageLen, abstract in
        abstract.ssh.disconnect(
            sess: sess,
            reason: reason,
            message: message,
            messageLen: messageLen,
            language: language,
            languageLen: languageLen
        )
    }

    /// 劫持 libssh2 的底层发送行为，路由到 libetos 处理 SSL 或流量统计
    let sendCallback: sendType = { fd, buffer, length, flags, abstract in
        abstract.ssh.send(fd: fd, buffer: buffer, length: length, flags: flags)
    }

    /// 劫持 libssh2 的底层接收行为
    let recvCallback: recvType = { fd, buffer, length, flags, abstract in
        abstract.ssh.recv(fd: fd, buffer: buffer, length: length, flags: flags)
    }

    deinit {
        close()
        #if DEBUG
            print("♻️", "SSH 核心实例已安全销毁")
        #endif
    }
}

public extension SSH {
    /// 完整关闭流程：释放会话资源并断开 Socket 连接
    func close() {
        freeSession()
        closeSocket()
        #if DEBUG
            print("♻️", "SSH 连接已完全关闭")
        #endif
    }
}
