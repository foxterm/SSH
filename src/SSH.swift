// FoxTerm | SSH.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libetos
import libssh
import Sync

/// SSH 核心客户端实例，管理 SSH 会话、Shell、SFTP 及 SCP 交互
public actor SSH {
    // MARK: - 底层句柄属性

    public internal(set) var rawSession: ssh_session?
    public internal(set) var rawChannel: ssh_channel?
    public internal(set) var rawSFTP: sftp_session?
    public internal(set) var rawSCP: ssh_scp?

    // MARK: - 网络与连接状态

    /// 底层 TCP 套接字文件描述符
    public internal(set) nonisolated(unsafe) var fd: Int32 = -1
    /// 记录最近一次发生的错误描述
    public internal(set) var error: String?
    /// 会话回调代理，用于同步连接状态、认证交互
    public internal(set) var sessionDelegate: SessionDelegate?
    /// Shell 数据交互回调代理
    public internal(set) var shellDelegate: ShellDelegate?
    /// 主机密钥算法列表
    public internal(set) var hostKeyAlgorithms: String = ""
    /// Socket 读取监听队列
    let queueSocket = DispatchQueue(label: "app.foxterm.ssh.readQueue", qos: .userInitiated)
    /// DispatchSource 读取源
    var socketSource: DispatchSourceRead?
    /// 窗口尺寸调整防抖 Task
    var resizeTask: Task<Void, Never>?
    /// 目录读取时过滤的文件列表
    public var ignoredFiles: [String] = [".", ".."]
    /// 文件过滤列表，用于目录读取时忽略特定文件或目录
    public var filterFiles: [String] = [".DS_Store"]
    /// 数据传输缓冲区大小，默认 64KB
    public nonisolated let bufferSize = 64 << 10
    /// 环境变量配置
    var environment: [String: String] = [:]
    /// 内部并发互斥锁
    let mutex: Mutex = .init()
    /// 等待组，用于并发任务的同步
    let wait: WaitGroup = .init()
    /// 是否已通过身份认证
    public internal(set) var isAuth: Bool = false
    /// 是否已关闭连接
    public internal(set) var isClose: Bool = false

    // MARK: - 基本连接配置

    /// 目标主机地址
    public let host: String
    /// 登录用户名
    public internal(set) var user: String = ""
    /// 服务端端口(默认 22)
    public let port: Int
    /// 连接超时时间(秒，默认 5)
    public let timeout: Int
    /// 是否开启数据传输压缩
    public let compress: Bool
    /// 传输压缩级别(1-9)，默认 6
    public let compress_level: Int

    // MARK: - 初始化与销毁

    /// 初始化 SSH 客户端配置
    /// - Parameters:
    ///   - host: 远程主机地址或 IP
    ///   - port: SSH 端口号(默认 22)
    ///   - timeout: 超时秒数(默认 5)
    ///   - compress: 是否开启传输压缩(默认 false)
    ///   - compress_level: 压缩级别(1-9)，默认 6
    public init(host: String, port: Int = 22, timeout: Int = 5, compress: Bool = false, compress_level: Int = 6) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.compress = compress
        self.compress_level = compress_level
        ssh_init()
    }

    deinit {
        // 兜底：任何未走 close() 的销毁路径（如持有方意外释放）都不能让一个
        // 仍处于 resume 状态的 DispatchSource / 未取消的防抖 Task 随对象一起
        // 被释放——那会在下一次事件投递时触发 libdispatch "Resurrection" 陷阱。
        // cancel() 同步且幂等，在这里调用是安全的。
        socketSource?.cancel()
        socketSource = nil
        resizeTask?.cancel()
        ssh_finalize()
        #if DEBUG
            print("♻️", "SSH 核心实例已安全销毁")
        #endif
    }

    // MARK: - 会话关闭与资源释放

    /// 关闭并释放当前 SSH 实例的所有连接与子系统资源
    ///
    /// 幂等：断连路径可能被多个入口先后触发（用户主动断开、`SessionDelegate.close()`
    /// 回调、取消回调），重复进入会让底层资源被释放两次。首次进入置 `isClose`，
    /// 后续调用直接返回。
    public func close() {
        guard !isClose else { return }
        isClose = true
        closeSCP()
        closeShell()
        closeSFTP()
        freeSession()
        closeSocket()
    }
}
