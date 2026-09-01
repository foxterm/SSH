// FoxTerm | ProxyType.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// An enumeration representing the types of proxy servers that can be used.
///
/// - http: Represents an HTTP proxy server.
/// - https: Represents an HTTPS proxy server.
/// - socks5: Represents a SOCKS5 proxy server.
public enum ProxyType: String, CaseIterable {
    case http
    /// case https
    case socks5

    public var portStr: String {
        switch self {
        case .http:
            "8080"
        // case .https:
        //     "8080"
        case .socks5:
            "1080"
        }
    }

    public var port: Int {
        switch self {
        case .http:
            8080
        // case .https:
        //     8080
        case .socks5:
            1080
        }
    }
}
