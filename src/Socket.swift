// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libetos
import libssh2
import Proxy

public extension SSH {
    /// 发起标准的 TCP 直接连接
    /// 使用 libetos 库进行非阻塞/带超时的 Socket 初始化
    /// - Returns: 是否连接成功
    func connect() async -> Bool {
        await io.call { [self] in
            // 初始化套接字，设置主机、端口、超时及 TTL/窗口缩放等参数
            fd = etos_socket_connect(host, port.int32, timeout.int32, ttl, window, scale)
            // 启用 Socket 层的 KeepAlive 机制防止链路被运营商中间设备切断
            etos_socket_keepalive(fd)
            return isConnected
        }
    }

    /// 通过代理服务器发起连接
    /// 支持 SOCKS5、HTTP 代理以及 SSL 加密代理
    /// - Parameter proxy: 代理配置信息对象
    /// - Returns: 是否连接成功
    func connect(_ proxy: ProxyInfo) async -> Bool {
        await io.call { [self] in
            isSSL = proxy.isSSL
            ssl = proxy.ssl
            // 调用 etos 代理连接接口，处理握手、认证及可选的 SSL/SNI 验证
            fd = etos_socket_connect_proxy(
                proxy.type.value,
                proxy.host,
                proxy.port.int32,
                timeout.int32,
                host,
                port.int32,
                proxy.user,
                proxy.password,
                proxy.sslVerify,
                proxy.sniHost,
                &ssl
            )
            return isConnected
        }
    }

    /// 内部数据发送方法
    /// 根据当前连接模式（SSL 或普通 TCP）自动路由发送指令
    /// - Parameters:
    ///   - fd: 套接字句柄
    ///   - buffer: 待发送数据指针
    ///   - length: 数据长度
    ///   - flags: 系统 send 标志位
    /// - Returns: 实际发送的字节数，负值代表错误
    internal func send(fd: Int32, buffer: UnsafeRawPointer, length: ssize_t, flags: CInt) -> Int {
        let size = isSSL ? etos_socket_ssl_send(ssl, buffer, length, flags) : etos_socket_send(fd, buffer, length, flags)
        guard size >= 0 else {
            return size
        }
        // 原子增加全局发送流量统计
        sendSize.add(size)
        return size
    }

    /// 内部数据接收方法
    /// 根据当前连接模式（SSL 或普通 TCP）自动路由接收指令
    /// - Parameters:
    ///   - fd: 套接字句柄
    ///   - buffer: 接收缓冲区指针
    ///   - length: 预期接收长度
    ///   - flags: 系统 recv 标志位
    /// - Returns: 实际接收的字节数，负值代表错误
    internal func recv(fd: Int32, buffer: UnsafeMutableRawPointer, length: ssize_t, flags: CInt) -> Int {
        let size = isSSL ? etos_socket_ssl_recv(ssl, buffer, length, flags) : etos_socket_recv(fd, buffer, length, flags)
        guard size >= 0 else {
            return size
        }
        // 原子增加全局接收流量统计
        recvSize.add(size)
        return size
    }

    /// 检查 Socket 是否已关闭（句柄为 -1）
    var closed: Bool {
        fd == -1
    }

    /// 检查底层 Socket 是否处于已连接状态
    var isConnected: Bool {
        etos_socket_is_connect(fd)
    }

    /// 等待套接字就绪（配合 libssh2 的非阻塞 IO）
    /// 当 libssh2 返回 EAGAIN 时，调用此方法根据阻塞方向进行 poll 等待
    internal func waitsocket() {
        guard rawSession != nil else {
            return
        }
        // 获取 libssh2 期望的等待方向（读或写）
        let dir = libssh2_session_block_directions(rawSession)

        var poll = LIBSSH2_POLLFD()
        poll.type = LIBSSH2_POLLFD_SOCKET.uint8
        poll.fd.socket = fd
        poll.events = 0

        // 监听入站数据
        if (dir & LIBSSH2_SESSION_BLOCK_INBOUND) != 0 {
            poll.events |= LIBSSH2_POLLFD_POLLIN.uint
        }
        // 监听出站缓冲区空间
        if (dir & LIBSSH2_SESSION_BLOCK_OUTBOUND) != 0 {
            poll.events |= LIBSSH2_POLLFD_POLLOUT.uint
        }

        // 执行极短时间的轮询以避免过度占用 CPU
        libssh2_poll(&poll, 1, 10)
    }

    /// 执行 Socket 半关闭操作
    /// - Parameter how: 关闭类型
    internal func shutdown(_ how: Shout) {
        etos_socket_shutdown(fd, how.rawValue)
    }

    /// 彻底关闭并释放 Socket 资源
    /// 包含互斥锁保护以确保线程安全，并释放 SSL 上下文
    func closeSocket() {
        // 先停止读取流
        shutdown(.read)
        mutex.withLock {
            etos_socket_close(fd)
            fd = -1
            #if DEBUG
                print("♻️", "Socket 连接已彻底释放")
            #endif
        }
        // 释放 libetos 相关的 SSL 内存
        etos_free_ssl(ssl)
    }
}
