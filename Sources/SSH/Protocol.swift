// FoxTerm | Protocol.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh

/// SSH 会话事件代理，用于处理连接过程中的交互式回调
public protocol SessionDelegate {
    /// 当 SSH 连接断开时触发
    func disconnect()

    /// 键盘交互式认证回调，服务端发送提示时调用
    /// - Parameters:
    ///   - name: 认证名称
    ///   - instruction: 认证说明信息
    ///   - prompt: 服务端发送的提示文本
    /// - Returns: 用户输入的应答内容
    func keyboardInteractive(name: String, instruction: String, prompt: String) -> String

    /// 已知主机密钥状态校验回调
    /// - Parameters:
    ///   - info: 当前连接的主机详细信息（含公钥指纹）
    ///   - state: 已知主机匹配状态（未知/已变更/已找到等）
    /// - Returns: 是否信任该主机密钥并继续连接
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
