// FoxTerm | IP.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Foundation

public typealias IP = String

public extension IP {
    /// 判断是否为私有 IPv6 地址 (FC00::/7 prefix)
    var isPrivateIPv6: Bool {
        var addr = in6_addr()
        guard inet_pton(AF_INET6, self, &addr) == 1 else { return false }

        // 只读取前 8 字节（高 64 位）并按大端序转换为 UInt64
        let high64 = withUnsafeBytes(of: addr) { ptr -> UInt64 in
            let bigEndianValue = ptr.load(as: UInt64.self)
            return UInt64(bigEndian: bigEndianValue)
        }

        switch high64 {
        // FC00::/7 对应的范围是 FC00:: ~ FDFF:FFFF:...
        // 前 64 位范围即 0xFC00_0000_0000_0000 ... 0xFDFF_FFFF_FFFF_FFFF
        case 0xFC00_0000_0000_0000 ... 0xFDFF_FFFF_FFFF_FFFF:
            return true
        default:
            return false
        }
    }

    /// 判断是否为私有 IPv4 地址 (RFC 1918)
    var isPrivateIPv4: Bool {
        var addr = in_addr()
        guard inet_pton(AF_INET, self, &addr) == 1 else { return false }

        let ipValue = CFSwapInt32BigToHost(addr.s_addr)

        switch ipValue {
        // 10.0.0.0 - 10.255.255.255 (10.0.0.0/8)
        case 0x0A00_0000 ... 0x0AFF_FFFF:
            return true

        // 172.16.0.0 - 172.31.255.255 (172.16.0.0/12)
        case 0xAC10_0000 ... 0xAC1F_FFFF:
            return true

        // 192.168.0.0 - 192.168.255.255 (192.168.0.0/16)
        case 0xC0A8_0000 ... 0xC0A8_FFFF:
            return true

        default:
            return false
        }
    }

    /// 检查 IP 地址是否为伪造 IP（Fake IP）的计算属性。
    ///
    /// 该属性将 IP 地址的字符串形式转换为二进制格式，
    /// 并检查其是否落入伪造 IP 地址范围（198.18.0.0 至 198.19.255.255）。
    ///
    /// - Returns: 如果 IP 地址是伪造 IP 则返回 `true`，否则返回 `false`。
    var isFakeIP: Bool {
        var addr = in_addr()
        guard inet_pton(AF_INET, self, &addr) == 1 else { return false }
        let ip = CFSwapInt32BigToHost(addr.s_addr)

        if case 0xC612_0000 ... 0xC613_FFFF = ip {
            return true
        }
        return false
    }

    /// 检查字符串是否为有效 IPv4 地址的计算属性。
    ///
    /// 该属性使用 `inet_pton` 函数判断字符串是否可以转换为有效的 IPv4 地址。
    ///
    /// - Returns: 如果字符串是有效的 IPv4 地址则返回 `true`，否则返回 `false`。
    var isIPv4: Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, self, &addr) == 1
    }

    /// 检查给定的 IP 地址字符串是否为 IPv6 地址的计算属性。
    ///
    /// 该属性使用 `inet_pton` 函数判断 IP 地址字符串是否可以成功转换为 IPv6 地址。
    ///
    /// - Returns: 指明该 IP 地址字符串是否为 IPv6 地址的布尔值。
    var isIPv6: Bool {
        var addr = in6_addr()
        return inet_pton(AF_INET6, self, &addr) == 1
    }

    /// 检查 IP 地址是否为局域网（LAN）IP 地址的计算属性。
    /// 如果 IP 地址是 IPv4 私有地址或 IPv6 私有地址，则返回 `true`。
    var isPrivateIP: Bool {
        isPrivateIPv4 || isPrivateIPv6
    }

    /// 检查当前实例是否为有效 IP 地址的计算属性。
    /// 如果实例是 IPv4 或 IPv6 地址，则返回 `true`。
    var isIP: Bool {
        isIPv4 || isIPv6
    }

    /// 判断当前 IP 地址是否为公网 IP 的计算属性。
    var isPubIP: Bool {
        isIP && !isPrivateIP
    }

    /// 返回以字节为单位的 IP 地址大小的计算属性。
    ///
    /// - Returns: 以字节为单位的 IP 地址大小；IPv4 返回 `in_addr` 的大小，IPv6 返回 `in6_addr` 的大小。
    var size: Int {
        isIPv4 ? MemoryLayout<in_addr>.size : MemoryLayout<in6_addr>.size
    }

    /// 返回 IP 地址的协议族（Address Family）的计算属性。
    ///
    /// - Returns: `Int32` 类型的协议族；IPv4 返回 `AF_INET`，IPv6 返回 `AF_INET6`。
    var af: Int32 {
        isIPv4 ? AF_INET : AF_INET6
    }

    /// `addr` 计算属性尝试将当前 IP 地址字符串转换为 `Data` 对象形式的二进制表示。
    ///
    /// - Returns: 转换成功时返回包含 IP 地址原始字节的 `Data` 对象；否则返回 `nil`。
    ///
    /// - Note: 该属性使用 `inet_pton` 函数进行转换。调用前请确保 IP 地址字符串针对协议族（IPv4 对应 `AF_INET`，IPv6 对应 `AF_INET6`）格式正确。
    var addr: Data? {
        var bytes = [UInt8](repeating: 0, count: size)
        guard inet_pton(af, self, &bytes) == 1 else {
            return nil
        }
        return Data(bytes)
    }
}
