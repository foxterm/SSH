// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Extension
import Foundation

/// 企业级网络 Socket 封装结构体
public struct Socket: Sendable {
    /// Socket 文件描述符
    public internal(set) var fd: Int32 = -1
    /// 目标主机名称或解析后的 IP 地址
    public internal(set) var hostname: String = ""
    /// 目标端口号
    public internal(set) var port: String = ""

    /// 使用指定的文件描述符初始化 Socket 实例
    /// - Parameter fd: 文件描述符，默认 `-1`（无效）
    public init(fd: Int32 = -1) {
        self.fd = fd
    }
}

public extension Socket {
    /// 检查 Socket 连接是否仍然存活且正常
    var isConnected: Bool {
        guard fd >= 0 else { return false }

        // 1. 检查套接字层面的底层错误 (SO_ERROR)
        var optval: Int32 = 0
        var optlen = socklen_t(MemoryLayout<Int32>.size)
        let errResult = getsockopt(fd, SOL_SOCKET, SO_ERROR, &optval, &optlen)
        guard errResult == 0, optval == 0 else { return false }

        // 2. 使用 MSG_PEEK + MSG_DONTWAIT 非阻塞探查对端状态
        var buf: UInt8 = 0
        let peekResult = Darwin.recv(fd, &buf, 1, Int32(MSG_PEEK | MSG_DONTWAIT))

        if peekResult == 0 {
            // 返回 0 表示接收到对端的 FIN 包 (EOF)，对端已主动关闭连接
            return false
        } else if peekResult < 0 {
            // EAGAIN / EWOULDBLOCK 表示缓冲区当前无数据但连接健康
            return errno == EAGAIN || errno == EWOULDBLOCK
        }

        // peekResult > 0 说明缓冲区中有有效数据待读取，连接正常
        return true
    }

    /// 关闭或优雅终止 Socket 连接
    ///
    /// - Parameter how: 终止模式，默认为 `.rw`（同时关闭读写通道并释放资源）
    mutating func shutdown(_ how: Shout = .rw) {
        guard fd >= 0 else { return }
        if how == .rw {
            Darwin.close(fd)
            fd = -1
        } else {
            Darwin.shutdown(fd, how.raw)
        }
    }

    /// 异步创建 Socket 并建立网络连接（支持超时控制与 SO_NOSIGPIPE 防爆）
    static func create(_ host: String, _ port: String, _ timeout: Int) async -> Socket {
        await io.call {
            var socket = Socket()
            socket.port = port

            IP.getAddrInfo(host: host, port: port) { info in
                let newFd = Darwin.socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
                guard newFd >= 0 else { return false }

                var optVal: Int32 = 1
                setsockopt(newFd, SOL_SOCKET, SO_NOSIGPIPE, &optVal, socklen_t(MemoryLayout<Int32>.size))

                let originalFlags = fcntl(newFd, F_GETFL, 0)
                guard originalFlags >= 0, fcntl(newFd, F_SETFL, originalFlags | O_NONBLOCK) != -1 else {
                    Darwin.close(newFd)
                    return false
                }

                let connectResult = Darwin.connect(newFd, info.pointee.ai_addr, info.pointee.ai_addrlen)
                if connectResult != 0 {
                    guard errno == EINPROGRESS else {
                        Darwin.close(newFd)
                        return false
                    }

                    var pollFd = pollfd(fd: newFd, events: Int16(POLLOUT), revents: 0)
                    let timeoutMs = max(timeout, 1) * 1000
                    let pollResult = poll(&pollFd, 1, Int32(timeoutMs))

                    if pollResult <= 0 {
                        Darwin.close(newFd)
                        return false
                    }

                    var socketError: Int32 = 0
                    var errorLength = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(newFd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength)

                    if socketError != 0 {
                        Darwin.close(newFd)
                        return false
                    }
                }

                let buf: Buffer<CChar> = .init(Int(NI_MAXHOST))
                guard Darwin.getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, buf.buffer, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else {
                    Darwin.close(newFd)
                    return false
                }

                socket.fd = newFd
                socket.hostname = buf.buffer.string
                return true
            }

            return socket
        }
    }

    /// 设置 Socket 的阻塞模式
    func setBlocking(_ isBlocking: Bool) -> Bool {
        guard fd >= 0 else { return false }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return false }

        let newFlags = isBlocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK)
        return fcntl(fd, F_SETFL, newFlags) != -1
    }

    /// 将 Socket 设置为非阻塞模式
    func setNonBlocking() -> Bool {
        setBlocking(false)
    }

    /// 发送数据到 Socket (已增强抗 SIGPIPE 风险)
    @inline(__always)
    func send(_ buffer: UnsafeRawPointer, _ length: Int, _ flags: Int32 = MSG_NOSIGNAL) -> Int {
        guard fd >= 0 else { return -Int(EBADF) }
        let size = Darwin.send(fd, buffer, length, flags)
        return size < 0 ? -Int(errno) : size
    }

    /// 从 Socket 接收数据
    @inline(__always)
    func recv(_ buffer: UnsafeMutableRawPointer, _ length: Int, _ flags: Int32 = 0) -> Int {
        guard fd >= 0 else { return -Int(EBADF) }
        let size = Darwin.recv(fd, buffer, length, flags)
        return size < 0 ? -Int(errno) : size
    }

    /// 从套接字流中读取字节（低级文件描述符 API）
    @inline(__always)
    func read(_ buffer: UnsafeMutableRawPointer, _ len: Int) -> Int {
        guard fd >= 0 else { return -Int(EBADF) }
        let size = Darwin.read(fd, buffer, len)
        return size < 0 ? -Int(errno) : size
    }

    /// 向套接字流中写入字节（低级文件描述符 API）
    @inline(__always)
    func write(_ buffer: UnsafeRawPointer, _ len: Int) -> Int {
        guard fd >= 0 else { return -Int(EBADF) }
        let size = Darwin.write(fd, buffer, len)
        return size < 0 ? -Int(errno) : size
    }

    /// 主动安全关闭 Socket 并回收底层资源
    mutating func close() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }
}

/// 表示 Socket 阶段性关闭（Shutdown）模式的枚举
public enum Shout: Sendable {
    /// 仅关闭读取通道
    case r
    /// 仅关闭写入通道
    case w
    /// 同时关闭读取与写入通道
    case rw

    /// 映射对应的 POSIX shutdown 常量
    var raw: Int32 {
        switch self {
        case .r:
            SHUT_RD
        case .w:
            SHUT_WR
        case .rw:
            SHUT_RDWR
        }
    }
}
