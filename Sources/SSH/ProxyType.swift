// FoxTerm | ProxyType.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libetos

/// An enumeration representing the types of proxy servers that can be used.
///
/// - http: Represents an HTTP proxy server.
/// - https: Represents an HTTPS proxy server.
/// - socks5: Represents a SOCKS5 proxy server.
public enum ProxyType: String, CaseIterable {
    case socks5
    case http
    // case https

    public var portString: String {
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

    public var value: Int32 {
        switch self {
        case .http:
            ETOS_PROXY_HTTP
        // case .https:
        //     ETOS_PROXY_HTTPS
        case .socks5:
            ETOS_PROXY_SOCKS5
        }
    }
}

public struct ProxyInfo {
    public let type: ProxyType
    public let host: String
    public let port: Int
    public let user: String
    public let password: String

    public init(
        type: ProxyType,
        host: String,
        port: Int,
        user: String,
        password: String
    ) {
        self.type = type
        self.host = host
        self.port = port
        self.user = user
        self.password = password
    }

    // public var isSSL: Bool {
    //     type == .https
    // }

    public func connect(
        shost: String, sport: Int, timeout: Int
    ) -> Int32 {
        etos_socket_connect_proxy(
            type.value,
            host,
            port.int32,
            timeout.int32,
            shost,
            sport.int32,
            user,
            password
        )
    }
}
