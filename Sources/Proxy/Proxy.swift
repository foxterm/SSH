// FoxTerm | Proxy.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libetos

/// 代理服务器与目标连接的配置结构体
public struct ProxyConfiguration: Codable, Equatable {
    // MARK: - Properties

    /// 代理类型
    public var type: ProxyType

    /// 代理服务器地址
    public var proxyHost: String

    /// 代理服务器端口
    public var proxyPort: Int

    /// 全局超时时间（毫秒）
    public var timeoutMs: Int

    /// 认证信息（可选）
    public var authentication: Auth?

    // MARK: - Nested Auth Struct

    public struct Auth: Codable, Equatable {
        public var user: String
        public var password: String

        public init(user: String, password: String) {
            self.user = user
            self.password = password
        }
    }

    // MARK: - Initializer

    public init(
        type: ProxyType = .socks5,
        proxyHost: String,
        proxyPort: Int,
        timeoutMs: Int = 50000,
        auth: Auth? = nil
    ) {
        self.type = type
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.timeoutMs = timeoutMs
        authentication = auth
    }
}

public extension ProxyConfiguration {
    func connect(host: String, port: Int) async -> Int32 {
        await io.call { [self] in
            etos_socket_connect_proxy(
                type.raw, proxyHost, proxyPort.int32, timeoutMs.int32, host,
                port.int32, authentication?.user ?? nil, authentication?.password ?? nil
            )
        }
    }
}
