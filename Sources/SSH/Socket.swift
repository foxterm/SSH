// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation
import libetos

public extension SSH {
    /// 发起标准的 TCP 直接连接
    /// 使用 libetos 库进行非阻塞/带超时的 Socket 初始化
    /// - Returns: 是否连接成功
    func connect() async -> Bool {
        fd = await io.call { [self] in
            etos_socket_connect(host, port.int32, timeout.int32 * 1000)
        }
        guard isConnected else {
            error = socketLastStrError
            return false
        }
        nodelay()
        keepalive()
        return true
    }

    /// 通过代理服务器发起连接
    /// 支持 SOCKS5、HTTP 代理
    /// - Parameter proxy: 代理配置信息对象
    /// - Returns: 是否连接成功
    func connect(proxy: ProxyConfiguration) async -> Bool {
        fd = await io.call { [self] in
            etos_socket_connect_proxy(
                proxy.type.raw, proxy.proxyHost, proxy.proxyPort.int32, proxy.timeoutMs.int32, host,
                port.int32, proxy.authentication?.user ?? nil, proxy.authentication?.password ?? nil
            )
        }
        guard isConnected else {
            error = socketLastStrError
            return false
        }
        nodelay()
        keepalive()
        return true
    }

    /// 获取当前连接的远程地址
    var remoteAddr: String? {
        var ipBuffer = [CChar](repeating: 0, count: 64)
        var port: Int32 = 0

        guard etos_socket_get_peer_info(fd, &ipBuffer, ipBuffer.count, &port) == 0 else {
            return nil
        }
        let host = ipBuffer.string
        return Net.joinHostPort(host: host, port: port.int)
    }

    /// 获取当前连接的本地地址
    var localAddr: String? {
        var ipBuffer = [CChar](repeating: 0, count: 64)
        var port: Int32 = 0

        guard etos_socket_get_local_info(fd, &ipBuffer, ipBuffer.count, &port) == 0 else {
            return nil
        }
        let host = ipBuffer.string
        return Net.joinHostPort(host: host, port: port.int)
    }

    /// 内部数据发送方法
    /// - Parameters:
    ///   - fd: 套接字句柄
    ///   - buffer: 待发送数据指针
    ///   - length: 数据长度
    ///   - flags: 系统 send 标志位
    /// - Returns: 实际发送的字节数，负值代表错误
    func send(fd: Int32, buffer: UnsafeRawPointer, length: ssize_t, flags: CInt) -> Int {
        let size = libssh2_send(fd, buffer, length, flags)
        if size < 0 {
            return size
        }
        // 原子增加全局发送流量统计
        sendSize.add(size)
        return size
    }

    /// 内部数据接收方法
    /// - Parameters:
    ///   - fd: 套接字句柄
    ///   - buffer: 接收缓冲区指针
    ///   - length: 预期接收长度
    ///   - flags: 系统 recv 标志位
    /// - Returns: 实际接收的字节数，负值代表错误
    func recv(fd: Int32, buffer: UnsafeMutableRawPointer, length: ssize_t, flags: CInt)
        -> Int
    {
        let size = libssh2_recv(fd, buffer, length, flags)
        if size < 0 {
            return size
        }
        // 原子增加全局接收流量统计
        recvSize.add(size)
        return size
    }

    /// 检查底层 Socket 是否处于已连接状态
    var isConnected: Bool {
        etos_socket_is_connect(fd)
    }

    /// 获取底层 Socket 的错误码
    var socketLastError: Int32 {
        etos_socket_last_error()
    }

    /// 获取底层 Socket 的错误描述字符串
    var socketLastStrError: String {
        etos_socket_strerror(socketLastError).string
    }

    /// 设置底层 Socket 的 keepalive
    internal func keepalive() {
        etos_socket_set_keepalive(fd, true, 5, 5, 10)
    }

    /// 禁用 Nagle 算法，降低延迟
    internal func nodelay() {
        etos_socket_set_nodelay(fd, true)
    }

    /// 等待套接字就绪（配合 libssh2 的非阻塞 IO）
    func waitSocket() -> Bool {
        guard rawSession != nil, isConnected else {
            return false
        }

        let dir = libssh2_session_block_directions(rawSession)

        var pollFd = LIBSSH2_POLLFD()
        pollFd.type = LIBSSH2_POLLFD_SOCKET.uint8
        pollFd.fd.socket = fd
        pollFd.events = 0
        pollFd.revents = 0

        if dir == 0 {
            pollFd.events |= LIBSSH2_POLLFD_POLLIN.uint
        } else {
            if (dir & LIBSSH2_SESSION_BLOCK_INBOUND) != 0 {
                pollFd.events |= LIBSSH2_POLLFD_POLLIN.uint
            }
            if (dir & LIBSSH2_SESSION_BLOCK_OUTBOUND) != 0 {
                pollFd.events |= LIBSSH2_POLLFD_POLLOUT.uint
            }
        }

        let rc = libssh2_poll(&pollFd, 1, 10)

        if rc < 0 {
            return false
        } else if rc == 0 {
            return true
        }

        let revents = Int32(pollFd.revents)
        if (revents & (LIBSSH2_POLLFD_POLLERR | LIBSSH2_POLLFD_POLLEXT | LIBSSH2_POLLFD_POLLHUP))
            != 0
        {
            return false
        }

        return true
    }

    /// 执行 Socket 半关闭操作
    /// - Parameter how: 关闭类型
    func shutdown(_ how: Shout) {
        etos_socket_shutdown(fd, how.raw)
    }

    /// 彻底关闭并释放 Socket 资源
    /// 包含互斥锁保护以确保线程安全，并释放 SSL 上下文
    func closeSocket() {
        etos_socket_close(fd)
        #if DEBUG
            print("♻️", "彻底关闭并释放 Socket 资源")
        #endif
    }
}
