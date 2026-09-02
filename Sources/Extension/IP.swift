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

        let ipValue = UInt32(bigEndian: addr.s_addr)

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

    /// A computed property that checks if the IP address is a fake IP.
    ///
    /// This property converts the string representation of the IP address to a binary format
    /// and checks if it falls within the range of fake IP addresses (198.18.0.0 to 198.19.255.255).
    ///
    /// - Returns: `true` if the IP address is a fake IP, `false` otherwise.
    var isFakeIP: Bool {
        var addr = in_addr()
        guard inet_pton(AF_INET, self, &addr) == 1 else { return false }
        let ip = CFSwapInt32BigToHost(addr.s_addr)

        if case 0xC612_0000 ... 0xC613_FFFF = ip {
            return true
        }
        return false
    }

    /// A computed property that checks if the string is a valid IPv4 address.
    ///
    /// This property uses the `inet_pton` function to determine if the string
    /// can be converted to a valid IPv4 address.
    ///
    /// - Returns: `true` if the string is a valid IPv4 address, `false` otherwise.
    var isIPv4: Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, self, &addr) == 1
    }

    /// A computed property that checks if the given IP address string is an IPv6 address.
    ///
    /// This property uses the `inet_pton` function to determine if the IP address string
    /// can be successfully converted to an IPv6 address.
    ///
    /// - Returns: A Boolean value indicating whether the IP address string is an IPv6 address.
    var isIPv6: Bool {
        var addr = in6_addr()
        return inet_pton(AF_INET6, self, &addr) == 1
    }

    /// A computed property that checks if the IP address is a LAN (Local Area Network) IP address.
    /// It returns `true` if the IP address is either an IPv4 LAN IP or an IPv6 LAN IP.
    var isPrivateIP: Bool {
        isPrivateIPv4 || isPrivateIPv6
    }

    /// A computed property that checks if the current instance is an IP address.
    /// It returns `true` if the instance is either an IPv4 or IPv6 address.
    var isIP: Bool {
        isIPv4 || isIPv6
    }

    var isPubIP: Bool {
        isIP && !isPrivateIP
    }

    /// A computed property that returns the size of the IP address in bytes.
    ///
    /// - Returns: The size of the IP address in bytes, which is either the size of `in_addr` for IPv4 or `in6_addr` for IPv6.
    var size: Int {
        isIPv4 ? MemoryLayout<in_addr>.size : MemoryLayout<in6_addr>.size
    }

    /// A computed property that returns the address family of the IP address.
    ///
    /// - Returns: The address family as an `Int32`, which is `AF_INET` for IPv4 or `AF_INET6` for IPv6.
    var af: Int32 {
        isIPv4 ? AF_INET : AF_INET6
    }

    /// The `addr` computed property attempts to convert the current IP address string into its binary representation as a `Data` object.
    ///
    /// - Returns: A `Data` object containing the raw bytes of the IP address if conversion is successful; otherwise, `nil`.
    ///
    /// - Note: This property uses the `inet_pton` function to perform the conversion. It is important to ensure that the IP address string is properly formatted for the address family (`AF_INET` for IPv4 or `AF_INET6` for IPv6) before calling this property.
    var addr: Data? {
        var bytes = [UInt8](repeating: 0, count: size)
        guard inet_pton(af, self, &bytes) == 1 else {
            return nil
        }
        return Data(bytes)
    }

    /// Resolves the given domain name to a list of IP addresses.
    ///
    /// - Parameter domain: The domain name to resolve.
    /// - Returns: An array of IP addresses associated with the given domain name.
    static func resolveDomainName(_ domain: IP) async -> [IP] {
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

    /// The `getAddrInfo` static method retrieves address information for a given host and optional port.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address to resolve.
    ///   - port: (Optional) The port number to be used in the address resolution. If not provided, the default port will be used.
    ///   - callback: A closure that takes an `UnsafeMutablePointer<addrinfo>` as its parameter. This closure will be called for each address information structure retrieved. If the closure returns `true`, the iteration will stop.
    ///
    /// - Description:
    ///   This method uses the `getaddrinfo` function to resolve the given host and port into a linked list of `addrinfo` structures. It then iterates over this list, calling the provided callback for each structure. If the callback returns `true`, the iteration stops. The method ensures that allocated memory for address information is freed using `freeaddrinfo` before it completes.
    ///
    /// - Note:
    ///   This method uses the Darwin framework's `addrinfo` and related functions, which are part of the POSIX standard for network programming on Unix-like operating systems.
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
        let result = Darwin.getaddrinfo(host, port, &hints, &addrInfo)
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
}
