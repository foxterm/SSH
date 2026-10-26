// FoxTerm | Protocol.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh

/// SSH 会话事件代理，用于处理连接过程中的所有交互式回调和状态变化。
///
/// `HostInfo` 结构体应包含所有关于目标主机（地址、公钥、指纹等）的详细信息。
public protocol SessionDelegate {
    /// 当 SSH 连接因任何原因（如断开、超时）意外断开时触发。
    func disconnect()
    
    /// 键盘交互式认证回调。当服务端需要用户输入（如密码、Passphrase）时调用。
    /// - Parameters:
    ///   - name: 认证机制的名称 (e.g., "password")。
    ///   - instruction: 认证流程的说明信息。
    ///   - prompt: 服务端发送的实际提示文本 (e.g., "Enter password: ")。
    /// - Returns: 用户输入的应答内容字符串。
    func keyboardInteractive(name: String, instruction: String, prompt: String) -> String
    
    /// 已知主机密钥状态校验回调。用于验证服务端公钥是否匹配本地缓存。
    /// - Parameters:
    ///   - info: 当前连接的主机详细信息（包含地址、公钥及指纹）。
    ///   - state: 当前的已知主机状态 (e.g., unknown, changed, found)。
    /// - Returns: 如果返回 `true`，表示信任该主机密钥并允许连接继续；否则连接将被中断。
    func knownState(info: HostInfo, state: ssh_known_hosts_e) -> Bool
}

/// 为 SessionDelegate 提供默认空实现，调用方可按需覆写
public extension SessionDelegate {
    func disconnect() {}
    func knownState(info _: HostInfo, state _: ssh_known_hosts_e) -> Bool {
        true
    }

    func keyboardInteractive(prompt _: String) -> String {
        ""
    }
}

/// Shell 数据交互代理，用于接收终端标准输出/错误及会话状态变化
public protocol ShellDelegate {
    /// 接收 Shell 标准输出数据
    func stdout(data: Data)

    /// 接收 Shell 标准错误数据
    func stderr(data: Data)

    /// Shell 会话成功启动时触发
    func shell()
}

/// 为 ShellDelegate 提供默认空实现
public extension ShellDelegate {
    func stdout(data _: Data) {}
    func stderr(data _: Data) {}
    func disconnect() {}

    func shell() {}
}
