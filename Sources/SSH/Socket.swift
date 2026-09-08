// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation
import Proxy
import Socket

public extension SSH {
    /// 发起标准的 TCP 直接连接
    /// 使用 libetos 库进行非阻塞/带超时的 Socket 初始化
    /// - Returns: 是否连接成功
    func connect() async -> Bool {
        socket = await Socket.create(host, "\(port)", timeout)
        return isConnected
    }

    /// 获取当前连接的主机名
    /// - Returns: 主机名字符串
    var hostname: String {
        socket.hostname
    }

    /// 通过代理服务器发起连接
    /// 支持 SOCKS5、HTTP 代理以及 SSL 加密代理
    /// - Parameter proxy: 代理配置信息对象
    /// - Returns: 是否连接成功
    func connect(proxy: ProxyConfig) async -> Bool {
        socket = await Proxy(proxy).connect(host, "\(port)", timeout)
        return isConnected
    }

    /// 内部数据发送方法
    /// - Parameters:
    ///   - fd: 套接字句柄
    ///   - buffer: 待发送数据指针
    ///   - length: 数据长度
    ///   - flags: 系统 send 标志位
    /// - Returns: 实际发送的字节数，负值代表错误
    func send(fd _: Int32, buffer: UnsafeRawPointer, length: ssize_t, flags: CInt) -> Int {
        let size = socket.send(buffer, length, flags)
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
    func recv(fd _: Int32, buffer: UnsafeMutableRawPointer, length: ssize_t, flags: CInt)
        -> Int
    {
        let size = socket.recv(buffer, length, flags)
        if size < 0 {
            return size
        }
        // 原子增加全局接收流量统计
        recvSize.add(size)
        return size
    }

    /// 检查底层 Socket 是否处于已连接状态
    var isConnected: Bool {
        socket.isConnected
    }

    /// 等待套接字就绪（配合 libssh2 的非阻塞 IO）
    func waitSocket() -> Bool {
        guard rawSession != nil, isConnected else {
            return false
        }

        let dir = libssh2_session_block_directions(rawSession)

        var pollFd = LIBSSH2_POLLFD()
        pollFd.type = LIBSSH2_POLLFD_SOCKET.uint8
        pollFd.fd.socket = socket.fd
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

        let rc = libssh2_poll(&pollFd, 1, 50)

        if rc < 0 {
            return false
        } else if rc == 0 {
            return true
        }

        let revents = Int32(pollFd.revents)
        if (revents & (LIBSSH2_POLLFD_POLLERR | LIBSSH2_POLLFD_POLLEXT | LIBSSH2_POLLFD_POLLHUP)) != 0 {
            return false
        }

        return true
    }

    /// 执行 Socket 半关闭操作
    /// - Parameter how: 关闭类型
    func shutdown(_ how: Shout) {
        socket.shutdown(how)
    }

    /// 彻底关闭并释放 Socket 资源
    /// 包含互斥锁保护以确保线程安全，并释放 SSL 上下文
    func closeSocket() {
        shutdown(.rw)
    }
}
