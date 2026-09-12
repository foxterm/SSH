// FoxTerm | Net.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public struct Net {}

public extension Net {
    /// 将指定的域名解析为 IP 地址列表。
    ///
    /// - Parameter domain: 要解析的域名。
    /// - Returns: 与给定域名关联的 IP 地址数组。
    static func resolveDomainName(_ domain: String) async -> [IP] {
        await io.call {
            if domain.isIP {
                return [domain]
            }
            var results = [IP]()
            getAddrInfo(host: domain) { info in
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if Darwin.getnameinfo(
                    info.pointee.ai_addr,
                    info.pointee.ai_addrlen,
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    results.append(hostname.string)
                }
                return false
            }
            return results
        }
    }

    /// `getAddrInfo` 静态方法用于获取给定主机名和可选端口的地址信息。
    ///
    /// - Parameters:
    ///   - host: 要解析的主机名或 IP 地址。
    ///   - port: （可选）用于地址解析的端口号。如果不提供，将使用默认端口。
    ///   - callback: 接收 `UnsafeMutablePointer<addrinfo>` 参数的闭包。对检索到的每个地址信息结构体都会调用该闭包。如果闭包返回 `true`，遍历将停止。
    ///
    /// - Description:
    ///   该方法使用 `getaddrinfo` 函数将给定的主机和端口解析为 `addrinfo` 结构体的链表。然后遍历该链表，并对每个结构体调用提供的回调函数。如果回调返回 `true`，则终止遍历。该方法确保在完成前使用 `freeaddrinfo` 释放已分配的地址信息内存。
    ///
    /// - Note:
    ///   此方法使用了 Darwin 框架的 `addrinfo` 及相关函数，这些函数属于类 Unix 操作系统网络编程 POSIX 标准的一部分。
    static func getAddrInfo(
        host: String,
        port: String? = nil,
        _ callback: @escaping (UnsafeMutablePointer<addrinfo>) -> Bool
    ) {
        var hints = Darwin.addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_ADDRCONFIG | AI_CANONNAME
        hints.ai_protocol = IPPROTO_TCP

        var addrInfo: UnsafeMutablePointer<Darwin.addrinfo>?
        let result = Darwin.getaddrinfo(host.bytesArray, port?.bytesArray, &hints, &addrInfo)
        guard result == 0, addrInfo != nil else {
            return
        }
        defer {
            Darwin.freeaddrinfo(addrInfo)
        }
        for info in sequence(first: addrInfo, next: { $0?.pointee.ai_next }) {
            guard let info else {
                continue
            }
            if callback(info) {
                break
            }
        }
    }

    /// 将主机名和端口号拼接为标准的 "主机:端口" 格式字符串（如果是 IPv6 地址则会自动补充方括号）。
    static func joinHostPort(host: String, port: Int) -> String {
        if host.contains(":"), !host.hasPrefix("[") {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }
}
