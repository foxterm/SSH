// FoxTerm | Shell.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh2

/// Shell 交互类，负责管理 SSH 渠道的伪终端 (PTY) 会话与数据交互
public class Shell {
    /// Shell 事件回调代理
    public var shellDelegate: ShellDelegate?
    /// 用于轮询读取远程输出的专用串行队列，避免阻塞主线程
    let queue = DispatchQueue(label: "app.foxterm.ssh-loop", qos: .userInitiated)
    /// 关联的底层通信渠道
    let channel: Channel

    init(channel: Channel) {
        self.channel = channel
    }

    deinit {
        #if DEBUG
            print("♻️", "Shell 实例已释放")
        #endif
    }
}

extension Shell {
    /// 获取底层的 libssh2 渠道指针
    var rawChannel: OpaquePointer? {
        channel.rawChannel
    }

    /// 启动 Shell 会话
    /// - Parameters:
    ///   - type: 终端类型 (如 xterm, vt100)
    ///   - width: 终端字符宽度
    ///   - height: 终端字符高度
    /// - Returns: 启动是否成功
    func shell(
        type: PtyType = .xterm, width: Int32 = LIBSSH2_TERM_WIDTH,
        height: Int32 = LIBSSH2_TERM_HEIGHT
    ) async -> Bool {
        guard let rawChannel else { return false }

        // 设置渠道为非阻塞模式，以便进行轮询
        libssh2_channel_set_blocking(rawChannel, 0)

        // 1. 请求伪终端 (PTY)
        var code = await channel.ssh.callSSH2 {
            libssh2_channel_request_pty_ex(
                rawChannel, type.name, type.name.count.uint32, nil, 0, width, height,
                LIBSSH2_TERM_WIDTH_PX, LIBSSH2_TERM_HEIGHT_PX
            )
        }
        guard code == LIBSSH2_ERROR_NONE else {
            closeShell()
            return false
        }

        // 2. 启动 Shell 进程
        code = await channel.ssh.callSSH2 {
            libssh2_channel_process_startup(rawChannel, "shell", 5, nil, 0)
        }
        guard code == LIBSSH2_ERROR_NONE else {
            closeShell()
            return false
        }

        // 通知代理并开始轮询远程输出
        shellDelegate?.shell(shell: self)
        pollShell()
        return true
    }

    /// 动态调整终端窗口大小（通常在 App 窗口尺寸变化时调用）
    func requestPtySize(width: Int32, height: Int32) async -> Bool {
        guard let rawChannel else { return false }
        let code = await channel.ssh.callSSH2 {
            libssh2_channel_request_pty_size_ex(
                rawChannel, width, height, LIBSSH2_TERM_WIDTH_PX, LIBSSH2_TERM_HEIGHT_PX
            )
        }
        return code == LIBSSH2_ERROR_NONE
    }

    /// 设置环境变量
    func setEnv(name: String, value: String) async -> Bool {
        guard let rawChannel else { return false }
        let code = await channel.ssh.callSSH2 {
            libssh2_channel_setenv_ex(
                rawChannel, name, name.count.uint32, value, value.count.uint32
            )
        }
        return code == LIBSSH2_ERROR_NONE
    }

    /// 向 Shell 写入二进制数据
    func write(data: Data, stream: StreamType = .stdout) async -> Bool {
        await write(data: .init(data: data), stream: stream, size: data.count)
    }

    /// 通过流向 Shell 写入数据
    func write(data: InputStream, stream: StreamType = .stdout, size: Int) async -> Bool {
        guard rawChannel != nil else { return false }
        // 使用自定义的 SSHInputStream 封装进行写入
        let code = await io.Copy(
            data, SSHInputStream(handle: rawChannel, ssh: channel.ssh, stream: stream),
            size
        )
        return code > 0
    }

    /// 轮询 Shell 输出
    /// 在独立后台队列中运行，通过 libssh2_poll 监听读取事件
    private func pollShell() {
        libssh2_channel_set_blocking(rawChannel, 0)
        queue.async { [self] in
            guard let rawChannel else { return }

            var poll = LIBSSH2_POLLFD()
            poll.type = LIBSSH2_POLLFD_SOCKET.uint8
            poll.fd.channel = rawChannel
            poll.events = LIBSSH2_POLLFD_POLLIN.uint | LIBSSH2_POLLFD_POLLEXT.uint

            let data: Buffer<CChar> = .init(channel.ssh.bufferSize)

            var rc, revents: Int32
            var n: Int
            // 循环监听直到渠道关闭或收到 EOF
            while self.rawChannel != nil, !channel.receivedEOF {
                rc = libssh2_poll(&poll, 1, 10)
                if rc > 0 {
                    revents = Int32(poll.revents)
                    // 处理标准输出 (stdout)
                    if (revents & LIBSSH2_POLLFD_POLLIN) != 0 {
                        n = libssh2_channel_read_ex(rawChannel, 0, data.buffer, data.count)
                        if n > 0 {
                            onStdout(.init(bytes: data.buffer, count: n))
                        }
                    }
                    // 处理标准错误 (stderr/ext)
                    if (revents & LIBSSH2_POLLFD_POLLEXT) != 0 {
                        n = libssh2_channel_read_ex(rawChannel, 1, data.buffer, data.count)
                        if n > 0 {
                            onStderr(.init(bytes: data.buffer, count: n))
                        }
                    }
                    // 检查渠道是否已关闭
                    if (revents & LIBSSH2_POLLFD_CHANNEL_CLOSED) != 0 {
                        closeShell()
                        break
                    }
                }
            }
        }
    }

    /// 处理标准输出回调
    private func onStdout(_ data: Data) {
        channel.ssh.addOperation {
            self.shellDelegate?.stdout(shell: self, data: data)
        }
    }

    /// 处理标准错误回调
    private func onStderr(_ data: Data) {
        channel.ssh.addOperation {
            self.shellDelegate?.dtderr(shell: self, data: data)
        }
    }

    /// 关闭 Shell 会话并释放关联资源
    func closeShell() {
        if channel.sendEof() {
            channel.waitEOF()
        }
        channel.closeChannel()
        shellDelegate?.disconnect(shell: self)
        #if DEBUG
            print("♻️", "Shell 已安全关闭")
        #endif
    }
}
