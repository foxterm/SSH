// FoxTerm | Direct.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

public extension SSH {
    // MARK: - Direct TCP/IP 端口转发

    /// 开启一条通过 SSH 隧道的 Direct TCP/IP 转发通道，并绑定输入输出流
    /// - Parameters:
    ///   - remoteHost: 远程目标主机地址
    ///   - remotePort: 远程目标端口
    ///   - sourceHost: 来源主机地址（默认 `"localhost"`）
    ///   - sourcePort: 来源端口（默认 `22`）
    ///   - outputStream: 下行数据输出流（SSH -> 客户端）
    ///   - inputStream: 上行数据输入流（客户端 -> SSH）
    /// - Returns: 是否成功打开通道
    @discardableResult
    func sshOpenDirectTCPIP(
        remoteHost: String,
        remotePort: Int,
        sourceHost: String = "localhost",
        sourcePort: Int = 22,
        outputStream: OutputStream,
        inputStream: InputStream
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        guard let rawSession else {
            return false
        }

        let channel: ssh_channel? = mutex.withLock {
            ssh_channel_new(rawSession)
        }
        guard let channel else {
            return false
        }

        let rc = mutex.withLock {
            ssh_channel_open_forward(
                channel,
                remoteHost.bytesArray,
                remotePort.int32,
                sourceHost.bytesArray,
                sourcePort.int32
            )
        }

        guard rc == SSH_OK else {
            mutex.withLock {
                ssh_channel_close(channel)
                ssh_channel_free(channel)
            }
            return false
        }

        startDirectStreamLoop(channel: channel, outputStream: outputStream, inputStream: inputStream, bufSize: bufferSize)
        return true
    }

    // MARK: - Unix Domain Socket 转发

    /// 开启一条通过 SSH 隧道的 Unix Domain Socket 转发通道，并绑定输入输出流
    /// - Parameters:
    ///   - socketPath: 远程 Unix Socket 文件路径（如 `/var/run/docker.sock`）
    ///   - sourceHost: 来源主机地址（默认 `"localhost"`）
    ///   - sourcePort: 来源端口（默认 `22`）
    ///   - outputStream: 下行数据输出流（SSH -> 客户端）
    ///   - inputStream: 上行数据输入流（客户端 -> SSH）
    /// - Returns: 是否成功打开通道
    @discardableResult
    func sshOpenUnixSocket(
        socketPath: String,
        sourceHost: String = "localhost",
        sourcePort: Int = 22,
        outputStream: OutputStream,
        inputStream: InputStream
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        guard let rawSession else {
            return false
        }

        let channel: ssh_channel? = mutex.withLock {
            ssh_channel_new(rawSession)
        }
        guard let channel else {
            return false
        }

        let rc = mutex.withLock {
            ssh_channel_open_forward_unix(
                channel,
                socketPath.bytesArray,
                sourceHost.bytesArray,
                sourcePort.int32
            )
        }

        guard rc == SSH_OK else {
            mutex.withLock {
                ssh_channel_close(channel)
                ssh_channel_free(channel)
            }
            return false
        }

        startDirectStreamLoop(channel: channel, outputStream: outputStream, inputStream: inputStream, bufSize: bufferSize)
        return true
    }

    // MARK: - Stream 转发引擎

    /// 启动针对特定 channel 的双向 Stream 流式转发泵
    ///
    /// 线程安全说明：上行/下行两个 `Task.detached` 共享同一个 `channel`，
    /// 任一 Task 退出时都会尝试关闭 channel。通过 `closeLock` + `channelClosed`
    /// 确保 close/free 只执行一次，避免 use-after-free 崩溃。
    private nonisolated func startDirectStreamLoop(
        channel: ssh_channel,
        outputStream: OutputStream,
        inputStream: InputStream,
        bufSize: Int
    ) {
        outputStream.open()
        inputStream.open()

        let actualBufferSize = bufSize > 0 ? bufSize : 64 << 10

        // 确保 channel 只被 close/free 一次的同步原语
        let closeLock = NSLock()
        var channelClosed = false

        func closeChannelOnce() {
            closeLock.lock()
            defer { closeLock.unlock() }
            guard !channelClosed else { return }
            channelClosed = true
            if ssh_channel_is_open(channel) == 1 {
                ssh_channel_close(channel)
            }
            ssh_channel_free(channel)
            #if DEBUG
                print("♻️", "彻底关闭并安全释放 Direct Channel 资源")
            #endif
        }

        // 1. 上行流转发：从 inputStream 读出并写入 SSH channel
        Task.detached(priority: .userInitiated) { [weak self] in
            let buffer = Buffer<UInt8>(actualBufferSize)
            defer {
                inputStream.close()
                closeChannelOnce()
            }

            while true {
                let readCount = inputStream.read(buffer.buffer, maxLength: buffer.count)
                if readCount <= 0 {
                    break
                }

                guard let self, writeAllToDirect(channel: channel, bytesToWrite: readCount, buffer: buffer) else {
                    break
                }
            }
        }

        // 2. 下行流转发：从 SSH channel 读出并写入 outputStream
        Task.detached(priority: .userInitiated) { [weak self] in
            let buffer = Buffer<UInt8>(actualBufferSize)
            defer {
                outputStream.close()
                closeChannelOnce()
            }

            while true {
                guard let self else {
                    break
                }

                let bytesRead: Int = mutex.withLock {
                    guard ssh_channel_is_open(channel) == 1,
                          ssh_channel_is_eof(channel) == 0
                    else {
                        return SSH_ERROR.int
                    }
                    return ssh_channel_read_nonblocking(channel, buffer.buffer, buffer.count.uint32, 0).int
                }

                if bytesRead > 0 {
                    if !writeAllToStream(bytesToWrite: bytesRead, to: outputStream, buffer: buffer) {
                        break
                    }
                } else if bytesRead == SSH_EOF || bytesRead == SSH_ERROR {
                    break
                } else {
                    // EAGAIN: 暂无数据，休眠 5ms 避让 CPU
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
    }

    // MARK: - 内部管道辅助方法

    /// 循环写入 OutputStream，确保 bytesToWrite 个字节完全写入
    private nonisolated func writeAllToStream(bytesToWrite: Int, to stream: OutputStream, buffer: Buffer<UInt8>) -> Bool {
        var offset = 0
        var retryCount = 0

        while offset < bytesToWrite {
            if stream.streamStatus == .error || stream.streamStatus == .closed {
                return false
            }

            let written = stream.write(buffer.buffer.advanced(by: offset), maxLength: bytesToWrite - offset)
            if written < 0 {
                return false // 写入异常直接退出
            } else if written == 0 {
                // 缓冲区满，重试计数防死锁
                retryCount += 1
                if retryCount > 3000 { // 累计等待 3 秒未写入成功则报超时错误退出
                    return false
                }
                Thread.sleep(forTimeInterval: 0.001)
                continue
            }

            retryCount = 0
            offset += written
        }
        return true
    }

    /// 循环写入 SSH Channel，确保 bytesToWrite 个字节完全写入
    private nonisolated func writeAllToDirect(channel: ssh_channel, bytesToWrite: Int, buffer: Buffer<UInt8>) -> Bool {
        var offset = 0
        while offset < bytesToWrite {
            let written: Int = mutex.withLock {
                guard ssh_channel_is_open(channel) == 1 else {
                    return SSH_ERROR.int
                }
                let ptr = buffer.buffer.advanced(by: offset)
                return ssh_channel_write(channel, ptr, (bytesToWrite - offset).uint32).int
            }

            if written <= 0 {
                return false
            }
            offset += written
        }
        return true
    }
}
