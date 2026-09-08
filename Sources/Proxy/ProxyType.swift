// FoxTerm | ProxyType.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 表示支持的网络代理协议类型枚举
public enum ProxyType: String, CaseIterable, Codable, Sendable {
    /// HTTP 代理协议 (HTTP CONNECT)
    case http

    /// SOCKS5 代理协议 (RFC 1928)
    case socks5

    /// 该代理协议的标准默认端口号（字符串形式）
    public var portStr: String {
        String(port)
    }

    /// 该代理协议的标准默认端口号（整数形式）
    public var port: Int {
        switch self {
        case .http:
            8080
        case .socks5:
            1080
        }
    }
}
