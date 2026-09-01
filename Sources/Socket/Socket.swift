// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Extension
import Foundation

public struct Socket {
    public internal(set) var fd: Int32 = -1
    public internal(set) var hostname: String = ""
    public internal(set) var port: String = ""

    public init(fd: Int32 = -1) {
        self.fd = fd
    }
}

// public typealias Socket = Int32

public extension Socket {
    /// A computed property that checks if the socket is connected.
    ///
    /// This property returns `true` if the socket is connected, and `false` otherwise.
    /// It performs the check by verifying that the socket file descriptor is not -1,
    /// and then using the `getsockopt` function to check for any socket errors.
    ///
    /// - Returns: A Boolean value indicating whether the socket is connected.
    var isConnected: Bool {
        guard fd >= 0 else { return false }

        // 1. 检查套接字层面的错误 (SO_ERROR)
        var optval: Int32 = 0
        var optlen = socklen_t(MemoryLayout<Int32>.size)
        let errResult = getsockopt(fd, SOL_SOCKET, SO_ERROR, &optval, &optlen)
        guard errResult == 0, optval == 0 else { return false }

        // 2. 检测对端是否已断开 (使用 MSG_PEEK + MSG_DONTWAIT 非阻塞预读)
        var buf: UInt8 = 0
        let peekResult = Darwin.recv(fd, &buf, 1, Int32(MSG_PEEK | MSG_DONTWAIT))

        if peekResult == 0 {
            // 返回 0 表示收到对端的 FIN 包 (EOF)，连接已关闭
            return false
        } else if peekResult < 0 {
            // EAGAIN 或 EWOULDBLOCK 表示缓冲区无数据但连接正常，其余 errno 均视作异常/断开
            return errno == EAGAIN || errno == EWOULDBLOCK
        }

        // peekResult > 0 表示有可读数据，连接正常
        return true
    }

    /// Shuts down the socket connection.
    ///
    /// - Parameter how: Specifies the type of shutdown. Default is `.rw` (read and write).
    ///   - `.rw`: Closes both read and write operations.
    ///   - `.read`: Closes read operations.
    ///   - `.write`: Closes write operations.
    ///
    /// If the socket file descriptor is valid (not equal to -1), it performs the shutdown operation
    /// using the specified type. If the type is `.rw`, it also closes the socket.
    ///
    /// - Note: Uses Darwin's `shutdown` and `close` functions.
    func shutdown(_ how: Shout = .rw) {
        if fd != -1 {
            switch how {
            case .rw:
                close()
            default:
                Darwin.shutdown(fd, how.raw)
            }
        }
    }

    /// Creates a socket file descriptor for the specified host and port, with an optional proxy configuration and timeout.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address to connect to.
    ///   - port: The port number to connect to.
    ///   - timeout: The timeout value in seconds for the connection.
    ///
    /// - Returns: A socket file descriptor (`Sock`) on success, or `-1` on failure.
    static func create(_ host: String, _ port: String, _ timeout: Int) async -> Socket {
        await io.call {
            var socket: Socket = .init()
            socket.port = port
            IP.getAddrInfo(host: host, port: port) { info in
                socket.fd = Darwin.socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
                if socket.fd < 0 {
                    return false
                }

                // 1. 设置套接字为非阻塞模式
                let originalFlags = fcntl(socket.fd, F_GETFL, 0)
                _ = fcntl(socket.fd, F_SETFL, originalFlags | O_NONBLOCK)

                // 2. 发起连接
                let connectResult = Darwin.connect(socket.fd, info.pointee.ai_addr, info.pointee.ai_addrlen)

                if connectResult != 0 {
                    if errno != EINPROGRESS {
                        socket.close()
                        socket.fd = -1
                        return false
                    }

                    // 3. 使用 poll 监听 Socket 是否可写（poll 的超时单位是毫秒 ms）
                    var pollFd = pollfd(fd: socket.fd, events: Int16(POLLOUT), revents: 0)
                    let pollResult = poll(&pollFd, 1, Int32(timeout * 1000))

                    // pollResult <= 0 说明超时(0)或出错(<0)
                    if pollResult <= 0 {
                        socket.close()
                        socket.fd = -1
                        return false
                    }

                    // 4. 检查 Socket 是否有错误
                    var socketError: Int32 = 0
                    var errorLength = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(socket.fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength)

                    if socketError != 0 {
                        socket.close()
                        socket.fd = -1
                        return false
                    }
                }

                // 5. 恢复套接字原来的阻塞标志
                _ = fcntl(socket.fd, F_SETFL, originalFlags)

                // 6. 为后续读写设置 Socket 选项
                var timeoutStruct = Darwin.timeval(tv_sec: timeout, tv_usec: 0)
                setsockopt(socket.fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutStruct, socklen_t(MemoryLayout<Darwin.timeval>.size))
                setsockopt(socket.fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutStruct, socklen_t(MemoryLayout<Darwin.timeval>.size))

                let buf: Buffer<CChar> = .init(Int(NI_MAXHOST))
                guard Darwin.getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, buf.buffer, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else {
                    socket.close()
                    socket.fd = -1
                    return false
                }
                socket.hostname = buf.buffer.string
                return true
            }
            return socket
        }
    }

    // 设置套接字为阻塞或非阻塞模式
    //
    // - Parameter isBlocking: `true` 表示阻塞模式，`false` 表示非阻塞模式。
    // - Returns: 操作成功返回 `true`，失败返回 `false`。

    func setBlocking(_ isBlocking: Bool) -> Bool {
        guard fd >= 0 else { return false }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return false }

        let newFlags = isBlocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK)
        return fcntl(fd, F_SETFL, newFlags) != -1
    }

    /// 将套接字设置为非阻塞模式
    func setNonBlocking() -> Bool {
        setBlocking(false)
    }

    /// Sends data through the socket.
    ///
    /// - Parameters:
    ///   - buffer: A pointer to the data to be sent.
    ///   - length: The number of bytes to send from the buffer.
    ///   - flags: Optional flags to modify the behavior of the send operation. Defaults to 0.
    ///
    /// - Returns: The number of bytes sent on success, or a negative error code on failure.
    @inline(__always)
    func send(_ buffer: UnsafeRawPointer, _ length: Int, _ flags: Int32 = 0) -> Int {
        let size = Darwin.send(fd, buffer, length, flags)
        if size < 0 {
            return Int(-errno)
        }
        return size
    }

    // Receives data from the socket.
    //
    // - Parameters:
    //   - buffer: A pointer to a buffer where the received data will be stored.
    //   - length: The maximum number of bytes to receive.
    //   - flags: The flags to control the behavior of the receive function. Defaults to 0.
    // - Returns: The number of bytes received, or a negative error code if the receive operation fails.

    @inline(__always)
    func recv(_ buffer: UnsafeMutableRawPointer, _ length: Int, _ flags: Int32 = 0) -> Int {
        let size = Darwin.recv(fd, buffer, length, flags)
        if size < 0 {
            return Int(-errno)
        }
        return size
    }

    /// Reads data into the provided buffer.
    ///
    /// - Parameters:
    ///   - buffer: A pointer to the buffer where the read data will be stored.
    ///   - len: The maximum number of bytes to read.
    /// - Returns: The number of bytes actually read, or a negative value if an error occurred.
    @inline(__always)
    func read(_ buffer: UnsafeMutableRawPointer, _ len: Int) -> Int {
        Darwin.read(fd, buffer, len)
    }

    /// Writes data from the provided buffer to the socket.
    ///
    /// - Parameters:
    ///   - buffer: A pointer to the data to be written.
    ///   - len: The number of bytes to write from the buffer.
    /// - Returns: The number of bytes that were written, or a negative value if an error occurred.
    @inline(__always)
    func write(_ buffer: UnsafeRawPointer, _ len: Int) -> Int {
        Darwin.write(fd, buffer, len)
    }

    /// Closes the socket file descriptor.
    ///
    /// This function wraps the `Darwin.close` function to close the socket file descriptor
    /// associated with the current instance. It is important to call this function to
    /// release the resources associated with the socket.
    func close() {
        Darwin.close(fd)
    }
}

/// An enumeration representing the type of shutdown operation to perform on a socket.
///
/// This enum defines three cases, each corresponding to a different type of shutdown operation:
/// - `.r`: Shutdown the read half of the socket.
/// - `.w`: Shutdown the write half of the socket.
/// - `.rw`: Shutdown both the read and write halves of the socket.
///
/// The `raw` computed property returns the corresponding POSIX shutdown constant for each case.
///
/// - SeeAlso: `shutdown` function in POSIX sockets.
public enum Shout {
    /// Shutdown the read half of the socket.
    case r

    /// Shutdown the write half of the socket.
    case w

    /// Shutdown both the read and write halves of the socket.
    case rw

    /// The raw POSIX shutdown constant corresponding to the enum case.
    ///
    /// - Returns: An `Int32` representing the POSIX shutdown constant.
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
