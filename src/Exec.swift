// FoxTerm | Exec.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

public extension SSH {
    // MARK: - 远程命令执行 (Exec)

    /// 执行远程命令(字符串数组形式)并返回合并输出数据
    /// - Parameter command: 命令及参数数组(例如 `["ls", "-la", "/var/log"]`)
    /// - Returns: 标准输出二进制数据 `Data`，失败返回 `nil`
    func exec(_ command: [String]) async -> Data? {
        await exec(command.joined(separator: " "))
    }

    /// 执行远程命令并返回合并输出数据
    /// - Parameter command: 待执行的 Shell 命令字符串
    /// - Returns: 标准输出二进制数据 `Data`，失败返回 `nil`
    func exec(_ command: String) async -> Data? {
        let output: OutputStream = .toMemory()
        guard await exec(command, output: output) else {
            return nil
        }
        return output.data
    }

    /// 执行远程命令并分别返回标准输出与标准错误数据
    /// - Parameter command: 待执行的 Shell 命令字符串
    /// - Returns: 元组 `(stdout: Data?, stderr: Data?)`，命令执行失败时两个值均为 `nil`
    func exec(_ command: String) async -> (Data?, Data?) {
        let output: OutputStream = .toMemory()
        let outerr: OutputStream = .toMemory()
        _ = await exec(command, output: output, outerr: outerr)
        return (output.data, outerr.data)
    }

    /// 执行远程命令并返回布尔值表示命令是否成功执行
    /// - Parameter command: 待执行的 Shell 命令字符串
    /// - Returns: 命令是否成功完整执行
    func exec(_ command: String) async -> Bool {
        let output: OutputStream = .toMemory()
        guard await exec(command, output: output) else {
            return false
        }
        return true
    }

    /// 执行远程命令（参数数组形式）并返回是否成功
    /// - Parameter command: 命令及参数数组
    /// - Returns: 命令是否成功执行
    func exec(_ command: [String]) async -> Bool {
        await exec(command.joined(separator: " "))
    }

    /// 执行远程命令并将结果流式写入指定的输出流(支持区分 stdout 与 stderr)
    /// - Parameters:
    ///   - command: 待执行的 Shell 命令字符串
    ///   - output: 接收标准输出(stdout)的 Output Stream
    ///   - outerr: 接收标准错误(stderr)的 Output Stream(可选)
    /// - Returns: 命令是否成功完整执行
    func exec(_ command: String, output: OutputStream, outerr: OutputStream? = nil) async -> Bool {
        guard !isClose else {
            return false
        }
        wait.add()
        defer {
            wait.done()
        }
        let channel: ssh_channel? = mutex.withLock {
            guard let rawSession else {
                return nil
            }
            return ssh_channel_new(rawSession)
        }

        guard let channel else {
            return false
        }

        let cleanup = {
            self.mutex.withVoid {
                ssh_channel_close(channel)
                ssh_channel_free(channel)
            }
        }

        let openResult = mutex.withLock {
            ssh_channel_open_session(channel)
        }
        guard openResult == SSH_OK else {
            cleanup()
            return false
        }

        let execResult = mutex.withLock {
            ssh_channel_request_exec(channel, command.bytesArray)
        }
        guard execResult == SSH_OK else {
            cleanup()
            return false
        }

        if output.streamStatus == .notOpen {
            output.open()
        }
        if outerr?.streamStatus == .notOpen {
            outerr?.open()
        }
        defer {
            output.close()
            outerr?.close()
        }

        let buffer = Buffer<UInt8>(bufferSize)

        var success = true

        repeat {
            let bytesRead = mutex.withLock { ssh_channel_read_nonblocking(channel, buffer.buffer, buffer.count.uint32, 0).int }
            if bytesRead > 0 {
                if !writeAll(bytesRead, to: output, buffer: buffer) {
                    success = false
                    break
                }
            } else if bytesRead == SSH_ERROR {
                success = false
                break
            }

            let bytesErr = mutex.withLock { ssh_channel_read_nonblocking(channel, buffer.buffer, buffer.count.uint32, 1).int }
            if bytesErr > 0 {
                // stderr 有输出只代表命令写了警告/错误信息，不代表命令执行失败
                if let outerr {
                    if !writeAll(bytesErr, to: outerr, buffer: buffer) {
                        success = false
                        break
                    }
                }
                // 未提供 outerr 时静默丢弃 stderr 数据，继续读取直至 EOF
            } else if bytesErr == SSH_ERROR {
                success = false
                break
            }
            do {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            } catch {
                break
            }
        } while mutex.withLock({ ssh_channel_is_open(channel) != 0 && ssh_channel_is_eof(channel) == 0 })

        cleanup()
        return success
    }

    // MARK: - 内部辅助方法

    /// 向输出流完整写入指定字节数的数据
    private func writeAll(_ bytesToWrite: Int, to stream: OutputStream, buffer: Buffer<UInt8>) -> Bool {
        var offset = 0
        while offset < bytesToWrite {
            let written = stream.write(buffer.buffer.advanced(by: offset), maxLength: bytesToWrite - offset)
            if written < 0 {
                return false
            }
            offset += written
        }
        return true
    }
}
