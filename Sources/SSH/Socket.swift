// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation
import libetos
import Proxy
import Darwin

public extension SSH {
    /// 发起标准的 TCP 直接连接
    /// 使用 libetos 库进行非阻塞/带超时的 Socket 初始化
    /// - Returns: 是否连接成功（Bool）
    func connect() async -> Bool {
        // 异步调用底层 IO 执行连接操作
        fd = await io.Call { [self] in
            etos_socket_connect(host, port.int32, timeout.int32 * 1000)
        }
        // 校验连接状态，若失败则提取并保存错误信息
        guard isConnected else {
            error = socketLastStrError
            return false
        }
        return true
    }

    /// 通过代理服务器发起连接
    /// 支持 SOCKS5、HTTP 代理
    /// - Parameter proxy: 代理配置信息对象
    /// - Returns: 是否连接成功（Bool）
    func connect(proxy: ProxyConfiguration) async -> Bool {
        // 使用代理配置发起异步连接
        fd = await proxy.connect(host: host, port: port)
        // 校验连接状态，若失败则提取并保存错误信息
        guard isConnected else {
            error = socketLastStrError
            return false
        }
        return true
    }

    /// 获取当前连接的远程地址
    var remoteAddr: (host: String, port: Int)? {
        let buffer = Buffer<CChar>(0x40)
        var port: Int32 = 0
        guard etos_socket_get_peer_info(fd, buffer.buffer, buffer.count, &port) == 0 else {
            return nil
        }
        let host = buffer.buffer.string
        return (host, port.int)
    }

    /// 获取当前连接的本地地址
    var localAddr: (host: String, port: Int)? {
        let buffer = Buffer<CChar>(0x40)
        var port: Int32 = 0
        guard etos_socket_get_local_info(fd, buffer.buffer, buffer.count, &port) == 0 else {
            return nil
        }
        let host = buffer.buffer.string
        return (host, port.int)
    }

//    /// 内部数据发送方法
//    /// - Parameters:
//    ///   - fd: 套接字句柄
//    ///   - buffer: 待发送数据指针
//    ///   - length: 数据长度
//    ///   - flags: 系统 send 标志位
//    /// - Returns: 实际发送的字节数，负值代表错误
//    func send(fd: Int32, buffer: UnsafeRawPointer, length: ssize_t, flags: CInt) -> Int {
//        let size = libssh2_send(fd, buffer, length, flags)
//        if size < 0 {
//            return size
//        }
//        // 原子增加全局发送流量统计
//        sendSize.add(size)
//        return size
//    }
//
//    /// 内部数据接收方法
//    /// - Parameters:
//    ///   - fd: 套接字句柄
//    ///   - buffer: 接收缓冲区指针
//    ///   - length: 预期接收长度
//    ///   - flags: 系统 recv 标志位
//    /// - Returns: 实际接收的字节数，负值代表错误
//    func recv(fd: Int32, buffer: UnsafeMutableRawPointer, length: ssize_t, flags: CInt)
//        -> Int
//    {
//        let size = libssh2_recv(fd, buffer, length, flags)
//        if size < 0 {
//            return size
//        }
//        // 原子增加全局接收流量统计
//        recvSize.add(size)
//        return size
//    }

    /// 当前 Socket 的网络流量统计
    /// - Returns: 元组 (send: 已发送字节数, recv: 已接收字节数, rtt: 实时往返时间（微秒))
    var trafficStats: (send: UInt64, recv: UInt64, rtt: UInt32) {
        guard fd >= 0 else { return (0, 0, 0) }
        var stats = FdTrafficStats()
        guard etos_socket_get_traffic_stats(fd, &stats) == 0 else {
            return (0, 0, 0)
        }
        let tx = etos_stats_get_tx(&stats)
        let rx = etos_stats_get_rx(&stats)
        let rtt = etos_stats_get_rtt(&stats)
        return (tx, rx, rtt)
    }

    /// 检查底层 Socket 是否处于已连接状态
    var isConnected: Bool {
        etos_socket_is_connect(fd)
    }

    /// 获取底层 Socket 的最近一次错误码
    var socketLastError: Int32 {
        etos_socket_last_error()
    }

    /// 获取底层 Socket 的最近一次错误描述字符串
    var socketLastStrError: String {
        etos_socket_strerror(socketLastError).string
    }

    /// 等待套接字就绪（配合 libssh2 的非阻塞 IO 进行事件轮询）
    /// - Returns: 套接字是否正常/可继续操作
    func waitSocket() -> Bool {
        guard rawSession != nil, isConnected, fd >= 0 else {
            return false
        }

        let dir = libssh2_session_block_directions(rawSession)

        var pfd = Darwin.pollfd()
        pfd.fd = fd
        pfd.events = 0
        pfd.revents = 0

        if dir == 0 {
            pfd.events |= POLLIN.int16
        } else {
            if (dir & LIBSSH2_SESSION_BLOCK_INBOUND) != 0 {
                pfd.events |= POLLIN.int16
            }
            if (dir & LIBSSH2_SESSION_BLOCK_OUTBOUND) != 0 {
                pfd.events |= POLLOUT.int16
            }
        }

        // 调用 C 标准库 poll，超时时间为 10 毫秒
        let rc = Darwin.poll(&pfd, 1, 10)
        if rc < 0 {
            // poll 执行出错
            return false
        } else if rc == 0 {
            // 超时，套接字暂无数据就绪，返回 true 继续重试
            return true
        }

        // 检查是否有异常标志（错误、挂断、非法 fd）
        let revents = pfd.revents.int32
        if (revents & (POLLERR | POLLHUP | POLLNVAL)) != 0 {
            return false
        }

        return true
    }

    /// 执行 Socket 半关闭操作（关闭读或写通道）
    /// - Parameter how: 关闭类型（如只关发送或只关接收）
    func shutdown(_ how: Shout) {
        etos_socket_shutdown(fd, how.raw)
    }

    /// 彻底关闭并释放 Socket 资源
    func closeSocket() {
        etos_socket_close(fd)
        #if DEBUG
            print("♻️", "彻底关闭并释放 Socket 资源")
        #endif
    }
}
