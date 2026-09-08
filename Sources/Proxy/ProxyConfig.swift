// FoxTerm | ProxyConfig.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

/// 网络代理服务器配置模型
///
/// 包含建立代理连接所需的完整信息，如主机地址、端口、可选的身份验证凭据（用户名/密码）以及代理协议类型。
public struct ProxyConfig: Codable, Sendable, Equatable, Hashable {
    /// 代理服务器的主机名或 IP 地址
    public let host: String

    /// 代理服务器的服务端口号
    public let port: String

    /// 代理身份验证用户名（若无需认证则为空字符串）
    public let username: String

    /// 代理身份验证密码（若无需认证则为空字符串）
    public let password: String

    /// 代理协议类型（如 HTTP、SOCKS5）
    public let type: ProxyType

    /// 初始化一个新的代理配置实例
    /// - Parameters:
    ///   - host: 代理服务器主机名或 IP 地址
    ///   - port: 代理服务器端口号
    ///   - type: 代理协议类型 `ProxyType`
    ///   - username: 认证用户名，默认为空
    ///   - password: 认证密码，默认为空
    public init(
        host: String,
        port: String,
        type: ProxyType,
        username: String = "",
        password: String = ""
    ) {
        self.host = host.trim
        self.port = port.trim
        self.type = type
        self.username = username
        self.password = password
    }
}

public extension ProxyConfig {
    /// 检查当前代理配置是否具备有效的主机地址与端口号
    var isValid: Bool {
        guard !host.isEmpty, let portNum = Int(port), (1 ... 65535).contains(portNum) else {
            return false
        }
        return true
    }

    /// 检查当前代理配置是否包含身份验证凭据
    var requiresAuthentication: Bool {
        !username.isEmpty || !password.isEmpty
    }
}
