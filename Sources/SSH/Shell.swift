// FoxTerm | Shell.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

/// Shell 交互类，负责管理 SSH 渠道的伪终端 (PTY) 会话与数据交互
public class Shell {
    /// Shell 事件回调代理
    public var shellDelegate: ShellDelegate?

    private var writeInputStream: InputStream?
    private var writeOutputStream: OutputStream?
    private var readOutputStream: OutputStream?
    private var errorOutputStream: OutputStream?

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

public extension Shell {
    /// 获取底层的 libssh2 渠道指针
    var rawChannel: OpaquePointer? {
        channel.rawChannel
    }

    /// 启动 Shell 会话
    /// - Parameters:
    ///   - term: 终端类型 (如 xterm, vt100)
    ///   - width: 终端字符宽度
    ///   - height: 终端字符高度
    /// - Returns: 启动是否成功
    func shell(
        term: String = "xterm-256color", width: Int = LIBSSH2_TERM_WIDTH.int,
        height: Int = LIBSSH2_TERM_HEIGHT.int
    ) async -> Bool {
        guard await channel.newSession() else { return false }

        // 设置渠道为非阻塞模式，以便进行轮询
        libssh2_channel_set_blocking(rawChannel, 0)

        // 1. 请求伪终端 (PTY)
        var code = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_request_pty_ex(
                rawChannel, term, term.count.uint32, nil, 0, width.int32, height.int32,
                LIBSSH2_TERM_WIDTH_PX, LIBSSH2_TERM_HEIGHT_PX
            )
        }
        guard code == LIBSSH2_ERROR_NONE else {
            closeShell()
            return false
        }

        // 2. 启动 Shell 进程
        code = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_process_startup(rawChannel, "shell", 5, nil, 0)
        }
        guard code == LIBSSH2_ERROR_NONE else {
            closeShell()
            return false
        }

        // 通知代理并开始轮询远程输出
        shellDelegate?.shell(shell: self)
        setupStreamsAndRegister()
        return true
    }

    /// 动态调整终端窗口大小（通常在 App 窗口尺寸变化时调用）
    func requestPtySize(width: Int, height: Int) async -> Bool {
        guard rawChannel != nil else { return false }
        let code = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_request_pty_size_ex(
                rawChannel, width.int32, height.int32, LIBSSH2_TERM_WIDTH_PX, LIBSSH2_TERM_HEIGHT_PX
            )
        }
        return code == LIBSSH2_ERROR_NONE
    }

    /// 设置环境变量
    func setEnv(name: String, value: String) async -> Bool {
        guard rawChannel != nil else { return false }
        let code = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_setenv_ex(
                rawChannel, name, name.count.uint32, value, value.count.uint32
            )
        }
        return code == LIBSSH2_ERROR_NONE
    }

    /// 向 Shell 写入二进制数据
    func write(data: Data) {
        guard let outputStream = writeOutputStream, outputStream.hasSpaceAvailable else { return }
        _ = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            if let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                outputStream.write(baseAddress, maxLength: data.count)
            }
        }
    }

    /// 轮询 Shell 输出
    /// 在独立后台队列中运行，通过 libssh2_poll 监听读取事件
    private func setupStreamsAndRegister() {
        guard let rawChannel else { return }
        var createInStream: InputStream?
        var createOutStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: channel.ssh.bufferSize, inputStream: &createInStream, outputStream: &createOutStream)

        writeInputStream = createInStream
        writeOutputStream = createOutStream

        writeOutputStream?.open()

        readOutputStream = BlockOutputStream { [weak self] data in
            guard let self else { return }
            onStdout(data)
        }

        errorOutputStream = BlockOutputStream { [weak self] data in
            guard let self else { return }
            onStderr(data)
        }

        guard let outStream = readOutputStream, let errStream = errorOutputStream else { return }

        // 异步注册到通道任务管理器中
        Task {
            await channel.ssh.channelPoll.register(
                handle: rawChannel,
                output: outStream,
                outerr: errStream,
                write: writeInputStream
            )
            #if DEBUG
                print("⚠️", "ChannelTask 轮询已退出，正在关闭 Shell")
            #endif
            self.closeShell()
        }
    }

    /// 处理标准输出回调
    private func onStdout(_ data: Data) {
        autoreleasepool {
            self.shellDelegate?.stdout(shell: self, data: data)
        }
    }

    /// 处理标准错误回调
    private func onStderr(_ data: Data) {
        autoreleasepool {
            self.shellDelegate?.dtderr(shell: self, data: data)
        }
    }

    /// 关闭 Shell 会话并释放关联资源
    func closeShell() {
        writeInputStream?.close()
        writeOutputStream?.close()
        readOutputStream?.close()
        errorOutputStream?.close()
        if channel.sendEof() {
            channel.waitEOF()
        }
        channel.closeChannel()
        shellDelegate?.disconnect(shell: self)
        shellDelegate = nil
        #if DEBUG
            print("♻️", "Shell 已安全关闭")
        #endif
    }
}
