// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Extension
import Foundation
import libetos
import Proxy

public extension SSH {
    /// 发起标准的 TCP 直接连接
    /// 使用 libetos 库进行非阻塞/带超时的 Socket 初始化
    /// - Parameter ifname: 绑定的网卡接口名(如 "en0") 或 本地 IP，传 NULL 则跳过绑定
    /// - Returns: 是否连接成功(Bool)
    func connect(ifname: String? = nil) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            fd = etos_socket_connect(host, port.int32, timeout.int32 * 1000, ifname)
            guard isConnected else {
                error = socketLastStrError
                return false
            }
            return true
        }
    }

    /// 通过代理服务器发起连接
    /// 支持 SOCKS5、HTTP 代理
    /// - Parameter proxy: 代理配置信息对象
    /// - Returns: 是否连接成功(Bool)
    func connect(proxy: ProxyConfiguration) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            fd = proxy.connect(host: host, port: port)
            guard isConnected else {
                error = socketLastStrError
                return false
            }
            return true
        }
    }

    /// 获取当前连接的远程地址
    nonisolated var remoteAddr: (host: String, port: Int)? {
        let buffer = Buffer<CChar>(0x40)
        var port: Int32 = 0
        guard etos_socket_get_peer_info(fd, buffer.buffer, buffer.count, &port) == 0 else {
            return nil
        }
        let host = buffer.buffer.string
        return (host, port.int)
    }

    /// 获取当前连接的本地地址
    nonisolated var localAddr: (host: String, port: Int)? {
        let buffer = Buffer<CChar>(0x40)
        var port: Int32 = 0
        guard etos_socket_get_local_info(fd, buffer.buffer, buffer.count, &port) == 0 else {
            return nil
        }
        let host = buffer.buffer.string
        return (host, port.int)
    }

    /// 当前 Socket 的网络流量统计
    /// - Returns: 元组 (send: 已发送字节数, recv: 已接收字节数, rtt: 实时往返时间(微秒))
    nonisolated var trafficStats: (send: UInt64, recv: UInt64, rtt: UInt32) {
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
    nonisolated var isConnected: Bool {
        etos_socket_is_connect(fd)
    }

    /// 获取底层 Socket 的最近一次错误码
    nonisolated var socketLastError: Int32 {
        etos_socket_last_error()
    }

    /// 获取底层 Socket 的最近一次错误描述字符串
    nonisolated var socketLastStrError: String {
        etos_socket_strerror(socketLastError).string
    }

    /// 执行 Socket 半关闭操作(关闭读或写通道)
    /// - Parameter how: 关闭类型(如只关发送或只关接收)
    nonisolated func shutdown(_ how: Shout) {
        etos_socket_shutdown(fd, how.raw)
    }

    /// 彻底关闭并释放 Socket 资源
    ///
    /// 幂等：`fd` 关闭后立即复位为 -1，重复调用（断连路径多入口触发）不会
    /// double-close——已关闭的 fd 可能被内核复用，二次 close 会误杀其它连接。
    ///
    /// 线程安全：`fd` 的读取（guard）与复位（`fd = -1`）均在 mutex 内完成，
    /// 确保 nonisolated 方法（`remoteAddr`/`localAddr` 等）在任意线程读取 `fd`
    /// 时不会拿到已关闭但仍有效的文件描述符。
    func closeSocket() {
        mutex.withVoid {
            guard fd >= 0 else { return }
            let closingFd = fd
            fd = -1
            etos_socket_close(closingFd)
        }
        #if DEBUG
            print("♻️", "彻底关闭并释放 Socket 资源")
        #endif
    }
}
