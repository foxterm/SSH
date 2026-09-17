// FoxTerm | Net.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libetos

public struct Net {}

public extension Net {
    /// 将指定的域名解析为 IP 地址列表。
    ///
    /// - Parameter domain: 要解析的域名。
    /// - maxCount: 最多获取的 IP 数量（默认 16）
    /// - Returns: 与给定域名关联的 IP 地址数组。
    static func resolveDomainName(_ domain: String, maxCount: Int = 16) async -> [IP] {
        var cAddrs = [EtosIPAddr](repeating: EtosIPAddr(), count: maxCount)
        let count = etos_socket_resolve_all_ips(domain, &cAddrs, maxCount)

        guard count > 0 else {
            return []
        }
        var results = [IP]()
        for i in 0 ..< Int(count) {
            let entry = cAddrs[i]
            var ipTuple = entry.ip
            let ipString = withUnsafePointer(to: &ipTuple) { ptr in
                String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
            }
            // let isIPv6 = (entry.family == AF_INET6)
            results.append(ipString)
        }

        return results
    }

    /// 将主机名和端口号拼接为标准的 "主机:端口" 格式字符串（如果是 IPv6 地址则会自动补充方括号）。
    static func joinHostPort(host: String, port: Int) -> String {
        if host.contains(":"), !host.hasPrefix("[") {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }
}
