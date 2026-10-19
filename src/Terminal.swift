// FoxTerm | Terminal.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

public extension SSH {
    // MARK: - 环境变量与 Shell 启动

    /// 设置环境变量(在启动 Shell 前配置)
    /// - Parameters:
    ///   - name: 环境变量键名
    ///   - value: 环境变量值
    func setEnv(name: String, value: String) {
        mutex.withVoid {
            environment[name] = value
        }
    }

    /// 打开交互式 Shell 终端并绑定 PTY 终端属性
    /// - Parameters:
    ///   - term: 终端类型字符串(如 `"xterm-256color"`)
    ///   - cols: 终端列数
    ///   - rows: 终端行数
    /// - Returns: 是否启动成功
    func shell(term: String, cols: Int, rows: Int, cmd: String = "") -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        let initialized: Bool = mutex.withLock {
            guard let rawSession else {
                return false
            }
            guard let channel = ssh_channel_new(rawSession) else {
                return false
            }
            rawChannel = channel

            guard ssh_channel_open_session(channel) == SSH_OK else {
                error = lastError
                _closeShell()
                return false
            }
            if cmd.isEmpty {
                for (name, value) in environment {
                    ssh_channel_request_env(channel, name.bytesArray, value.bytesArray)
                }
            }

            let modes = Array.defaultTerminalModes.serializedBytes
            let ptyResult = modes.withUnsafeBufferPointer { buffer in
                ssh_channel_request_pty_size_modes(
                    channel,
                    term.bytesArray,
                    cols.int32,
                    rows.int32,
                    buffer.baseAddress,
                    buffer.count
                )
            }
            guard ptyResult == SSH_OK else {
                error = lastError
                _closeShell()
                return false
            }
            if cmd.isEmpty {
                guard ssh_channel_request_shell(channel) == SSH_OK else {
                    error = lastError
                    _closeShell()
                    return false
                }
            } else {
                guard ssh_channel_request_exec(channel, cmd) == SSH_OK else {
                    error = lastError
                    _closeShell()
                    return false
                }
            }

            return true
        }

        guard initialized else {
            return false
        }

        shellDelegate?.shell()
        readLoop()
        return true
    }

    // MARK: - 终端尺寸调整

    /// 防抖调整 PTY 窗口尺寸(50ms 延迟，避免频繁调整触发过多 SSH 报文)
    /// - Parameters:
    ///   - cols: 新列数
    ///   - rows: 新行数
    func debouncedRequestPtySize(cols: Int, rows: Int) {
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms 防抖
                if !Task.isCancelled {
                    await self?.requestPtySize(cols: cols, rows: rows)
                }
            } catch {}
        }
    }

    /// 立即向服务端请求修改 PTY 终端尺寸
    /// - Parameters:
    ///   - cols: 新列数
    ///   - rows: 新行数
    /// - Returns: 是否设置成功
    @discardableResult
    func requestPtySize(cols: Int, rows: Int) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawChannel else {
                return false
            }
            guard ssh_channel_change_pty_size(rawChannel, cols.int32, rows.int32) == SSH_OK else {
                return false
            }
            return true
        }
    }

    // MARK: - 数据写入

    /// 向 SSH Shell 通道写入二进制数据(用户键盘输入/控制序列)
    /// - Parameter data: 待发送的数据
    /// - Returns: 是否发送成功
    @discardableResult
    func write(data: Data) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawChannel else {
                return false
            }
            let rc = data.withCPointer { d, c in
                ssh_channel_write(rawChannel, d, c.uint32)
            }
            return rc == SSH_OK
        }
    }

    // MARK: - 会话关闭与清理

    /// 关闭并释放 Shell 通道(公开安全接口，带锁)
    ///
    /// 幂等：`close()`、事件回调、取消回调可能经不同入口先后触发，重复调用
    /// 必须安全无操作（`_closeShell` 自身有 rawChannel 守卫，`cancel()` 对已取消
    /// 源是 no-op，这里再挡一层避免重复进入 mutex 清理）。
    func closeShell() {
        guard rawChannel != nil || socketSource != nil else { return }
        socketSource?.cancel()
        socketSource = nil
        mutex.withVoid {
            _closeShell()
        }
    }

    /// 内部无锁关闭清理方法(专供已在 mutex 保护内的函数调用，避免死锁)
    private func _closeShell() {
        guard let rawChannel else {
            return
        }
        if ssh_channel_is_open(rawChannel) == 1 {
            ssh_channel_request_send_signal(rawChannel, "HUP".bytesArray)
            ssh_channel_send_eof(rawChannel)
        }
        ssh_channel_close(rawChannel)
        ssh_channel_free(rawChannel)
        self.rawChannel = nil
        #if DEBUG
            print("♻️", "会话关闭与清理")
        #endif
    }

    // MARK: - 事件监听与读取循环

    /// 启动 DispatchSource 事件监听循环
    ///
    /// 线程安全约束：事件与取消回调都在 `queueSocket` 上执行，**绝不能**在这里
    /// 同步触碰 actor 隔离状态（`socketSource`/`rawChannel`/`isClose`）——否则会与
    /// MainActor 上的 `close()`/`disconnect()` 并发释放同一个 DispatchSource，
    /// 触发 libdispatch 的 "API MISUSE: Resurrection" 崩溃。所有状态操作都经
    /// `[weak self]` + `Task { await ... }` 跳回 actor 串行执行，弱引用同时
    /// 打破 handler → self 的强引用环，避免会话在标签关闭后永远存活。
    private func readLoop() {
        socketSource?.cancel()
        socketSource = nil
        socketSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queueSocket)
        socketSource?.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.processReadEvents() }
        }
        socketSource?.setCancelHandler { [weak self] in
            guard let self else { return }
            Task { await self.handleDisconnect() }
        }
        socketSource?.resume()
    }

    /// 处理 Socket 可读事件并从通道获取数据
    private func processReadEvents() {
        wait.add()
        defer {
            wait.done()
        }
        let buffer = Buffer<UInt8>(bufferSize)
        while !isClose {
            // 锁 + 状态校验双重保护，防止 EXC_BAD_ACCESS
            let readResult: (bytesRead: Int, bytesErr: Int, isClosed: Bool) = mutex.withLock {
                guard let rawChannel,
                      ssh_channel_is_open(rawChannel) == 1,
                      ssh_channel_is_eof(rawChannel) == 0
                else {
                    return (0, 0, true)
                }

                // 读取 stdout
                let bytesRead = ssh_channel_read_nonblocking(rawChannel, buffer.buffer, buffer.count.uint32, 0).int
                if bytesRead > 0 {
                    return (bytesRead, 0, false)
                } else if bytesRead == SSH_ERROR || bytesRead == SSH_EOF {
                    return (0, 0, true)
                }

                // 读取 stderr
                let bytesErr = ssh_channel_read_nonblocking(rawChannel, buffer.buffer, buffer.count.uint32, 1).int
                if bytesErr > 0 {
                    return (0, bytesErr, false)
                } else if bytesErr == SSH_ERROR || bytesErr == SSH_EOF {
                    return (0, 0, true)
                }

                return (0, 0, false)
            }

            if readResult.isClosed {
                closeShell()
                break
            }

            if readResult.bytesRead > 0 {
                onStdout(Data(bytes: buffer.buffer, count: readResult.bytesRead))
                continue
            }

            if readResult.bytesErr > 0 {
                onStderr(Data(bytes: buffer.buffer, count: readResult.bytesErr))
                continue
            }
            break
        }
    }

    /// 处理 Socket 断开连接事件
    private func handleDisconnect() {
        shellDelegate?.disconnect()
        socketSource = nil
    }

    /// 处理标准输出回调
    private func onStdout(_ data: Data) {
        autoreleasepool {
            self.shellDelegate?.stdout(data: data)
        }
    }

    /// 处理标准错误回调
    private func onStderr(_ data: Data) {
        autoreleasepool {
            self.shellDelegate?.stderr(data: data)
        }
    }
}
