// FoxTerm | Channel.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

/// SSH 通道封装类，负责具体的命令执行与数据流转
public class Channel {
    /// libssh2 底层通道指针
    public internal(set) var rawChannel: OpaquePointer?
    /// 所属的 SSH 实例
    let ssh: SSH

    init(ssh: SSH) {
        self.ssh = ssh
    }

    deinit {
        #if DEBUG
            print("♻️", "Channel")
        #endif
    }
}

public extension Channel {
    /// 获取底层的 libssh2 会话指针
    internal var rawSession: OpaquePointer? {
        ssh.rawSession
    }

    func newSession() async -> Bool {
        closeChannel()
        rawChannel = await ssh.callSSH2 { [self] in
            libssh2_channel_open_ex(rawSession, "session", 7, 0x200000, 0x8000, nil, 0)
        }
        return rawChannel != nil
    }

    /// 执行简单的 Shell 命令并直接返回结果 Data
    /// - Parameters:
    ///   - command: 待执行的命令字符串
    ///   - max: 最大读取字节数，0 表示不限制
    /// - Returns: 命令标准输出数据，失败返回 nil
    func exec(_ command: String, max: Int = 0) async -> Data? {
        let output: OutputStream = .toMemory()
        guard await exec(command, output: output, outerr: .toMemory(), max: max) else {
            return nil
        }
        return output.data
    }

    /// 执行命令数组（自动以空格连接）
    func exec(_ command: [String]) async -> Data? {
        await exec(command.joined(separator: " "))
    }

    /// 执行命令并将 stdout 和 stderr 重定向到指定的输出流
    /// - Parameters:
    ///   - command: 命令字符串
    ///   - output: 标准输出流 (stdout)
    ///   - outerr: 标准错误流 (stderr)
    ///   - max: 最大读取限制
    /// - Returns: 是否成功启动并完成执行
    func exec(
        _ command: String, output: OutputStream, outerr: OutputStream, max: Int = 0
    ) async -> Bool {
        guard await newSession() else {
            return false
        }
        #if DEBUG
            print("exec", command)
        #endif

        libssh2_channel_set_blocking(rawChannel, 0)

        let startupCode = await ssh.callSSH2 { [self] in
            libssh2_channel_process_startup(
                rawChannel, "exec", 4, command, command.count.uint32
            )
        }

        guard startupCode == LIBSSH2_ERROR_NONE else {
            closeChannel()
            return false
        }

        libssh2_channel_set_blocking(rawChannel, 0)

        await ssh.channelTask.register(
            handle: rawChannel!,
            output: output,
            outerr: outerr,
            write: nil
        ) { [weak self] (currentLoopBytes: Int64, _: Int64) -> Bool in
            return max <= 0 ? true : currentLoopBytes <= max
        }
        closeChannel()

        return true
    }

    var read: InputStream {
        SSHInputStream(handle: rawChannel, ssh: ssh, stream: .stdout)
    }

    var readErr: InputStream {
        SSHInputStream(handle: rawChannel, ssh: ssh, stream: .stderr)
    }

    var write: OutputStream {
        SSHOutputStream(handle: rawChannel, ssh: ssh, stream: .stdout)
    }

    /// 测试通道连通性
    func testEcho() async -> Bool {
        guard let data = await exec("echo \">TEST<\"", max: 7) else {
            return false
        }
        guard data.string?.contains(">TEST<") ?? false else {
            return false
        }
        return true
    }

    /// 通道是否处于可读/活跃状态
    var isRead: Bool {
        !(receivedEOF || receivedExit)
    }

    /// 检查是否收到退出状态码
    var receivedExit: Bool {
        guard rawChannel != nil else {
            return true
        }
        return libssh2_channel_get_exit_status(rawChannel) != 0
    }

    /// 轮询标准输出是否可读
    var isPoll: Bool {
        guard rawChannel != nil else {
            return false
        }
        return libssh2_poll_channel_read(rawChannel, 0) != 0
    }

    /// 轮询标准错误是否可读
    var isPollError: Bool {
        guard rawChannel != nil else {
            return false
        }
        return libssh2_poll_channel_read(rawChannel, SSH_EXTENDED_DATA_STDERR) != 0
    }

    /// 是否收到 EOF (文件传输或流结束)
    var receivedEOF: Bool {
        guard rawChannel != nil else {
            return true
        }
        return libssh2_channel_eof(rawChannel) != 0
    }

    /// 向远程端发送 EOF
    func sendEof() -> Bool {
        guard rawChannel != nil else {
            return false
        }
        let rc = ssh.callSSH2 {
            libssh2_channel_send_eof(self.rawChannel)
        }
        return rc == 0
    }

    /// 阻塞等待远程端发送 EOF
    func waitEOF() {
        guard rawChannel != nil else {
            return
        }
        if libssh2_channel_eof(rawChannel) == 0 {
            libssh2_channel_wait_eof(rawChannel)
        }
    }

    /// 安全关闭并释放通道资源
    func closeChannel() {
        guard let rawChannel else { return }
        ssh.channelTask.unregister(handle: rawChannel)

        // 尝试正常关闭并等待确认
        let rc = ssh.callSSH2 {
            libssh2_channel_close(self.rawChannel)
        }
        if rc == 0 {
            _ = ssh.callSSH2 {
                libssh2_channel_wait_closed(self.rawChannel)
            }
        }

        // 强制释放指针
        libssh2_channel_free(rawChannel)
        self.rawChannel = nil
        #if DEBUG
            print("♻️", "Channel closed and freed safely")
        #endif
    }
}
