// FoxTerm | Protocol.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// SSH 会话级别的回调协议
/// 用于处理连接生命周期、身份验证交互以及流量统计
public protocol SessionDelegate {
    /// 当 SSH 连接断开时调用
    func disconnect()

    /// 握手阶段的回调，可在此处进行主机密钥 (HostKey) 验证
    /// - Returns: 返回 true 以继续连接，false 则中止
    func handshake(ssh: SSH) -> Bool

    /// 处理 SSH 键盘交互式认证 (Keyboard-Interactive)
    /// 当服务器请求额外信息（如 OTP 验证码、二次确认）时触发
    /// - Parameters:
    ///   - ssh: 触发请求的 SSH 实例
    ///   - prompt: 服务器发送的提示文本
    /// - Returns: 返回用户的输入内容
    func keyboardInteractive(ssh: SSH, prompt: String) -> String
}

/// 为 SessionDelegate 提供默认空实现，方便开发者只关注需要的接口
public extension SessionDelegate {
    func disconnect() {}
    func handshake(ssh _: SSH) -> Bool {
        true
    }

    func keyboardInteractive(ssh _: SSH, prompt _: String) -> String {
        ""
    }
}

/// Shell 交互层的回调协议
/// 专门用于处理终端 (Terminal) 的输入输出与状态变更
public protocol ShellDelegate {
    /// 接收到远程终端的标准输出 (stdout)
    /// 通常将此数据直接喂给终端组件 (如 Xterm.js 视图)
    func stdout(shell: Shell, data: Data)

    /// 接收到远程终端的标准错误 (stderr)
    func dtderr(shell: Shell, data: Data)

    /// 当前 Shell 通道已关闭或断开
    func disconnect(shell: Shell)

    /// Shell 会话启动成功，终端已就绪
    func shell(shell: Shell)
}

/// 为 ShellDelegate 提供默认空实现
public extension ShellDelegate {
    func stdout(shell _: Shell, data _: Data) {}
    func dtderr(shell _: Shell, data _: Data) {}
    func disconnect(shell _: Shell) {}

    func shell(shell _: Shell) {}
}
