// FoxTerm | Proxy.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import Socket

public class Proxy {
    let configuration: ProxyConfig
    public init(_ configuration: ProxyConfig) {
        self.configuration = configuration
    }
}

public extension Proxy {
    /// Connects to a remote server through a proxy.
    ///
    /// This method attempts to establish a connection to the specified `host` and `port` through a proxy. The type of proxy (HTTP/HTTPS or SOCKS5) is determined by the `type` property of the proxy.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor of the socket to use for the connection.
    ///   - host: The hostname or IP address of the remote server to connect to.
    ///   - port: The port number of the remote server to connect to.
    /// - Returns: A `Bool` indicating whether the connection was successful.
    ///
    /// - Throws: This method does not throw exceptions but returns `false` if any step of the connection process fails.
    func connect(_ host: String, _ port: String, _ timeout: Int = 5) async -> Socket {
        let socket = await Socket.create(configuration.host, configuration.port, timeout)
        guard socket.isConnected else {
            return .init()
        }
        socket.setBlocking(true)
        for ip in await IP.resolveDomainName(host) {
            guard connect(socket, ip, port) else {
                continue
            }
            socket.setBlocking(false)
            return socket
        }
        socket.close()
        return socket
    }

    func readExactly(_ fd: Socket, buffer: UnsafeMutablePointer<UInt8>, count: Int) -> Bool {
        var totalRead = 0
        while totalRead < count {
            let rc = fd.read(buffer.advanced(by: totalRead), count - totalRead)
            if rc <= 0 {
                return false
            }
            totalRead += rc
        }
        return true
    }

    func connect(_ fd: Socket, _ host: String, _ port: String) -> Bool {
        switch configuration.type {
        case .http:
            var connectString = "CONNECT \(host):\(port) HTTP/1.1\r\n"
            if !configuration.username.isEmpty || !configuration.password.isEmpty {
                let authStr = "\(configuration.username):\(configuration.password)"
                let authData = Data(authStr.utf8).base64EncodedString()
                connectString += "Proxy-Authorization: Basic \(authData)\r\n"
            }
            connectString += "Host: \(host):\(port)\r\n\r\n"

            let bytes = connectString.bytes
            guard fd.write(bytes, connectString.count) == connectString.count else { return false }

            // HTTP 响应头通常以 \r\n\r\n 结尾，这里读取前 1024 字节校验状态码
            let buffer: Buffer<UInt8> = .init(0x400)
            let rc = fd.read(buffer.buffer, buffer.count)
            guard rc > 0, let response = buffer.data(rc).string else { return false }

            // 兼容 "HTTP/1.1 200 OK" 或 "HTTP/1.0 200 Connection Established" 等变体
            guard response.contains(" 200 ") || response.hasPrefix("HTTP/1.1 200") || response.hasPrefix("HTTP/1.0 200") else {
                return false
            }

        case .socks5:
            // 1. 握手阶段 (Greeting)
            var greeting: [UInt8] = [0x05, 0x01, 0x00]
            if !configuration.username.isEmpty || !configuration.password.isEmpty {
                greeting = [0x05, 0x01, 0x02] // 支持用户名密码认证
            }
            guard fd.write(&greeting, greeting.count) == greeting.count else { return false }

            var responseBuffer = [UInt8](repeating: 0, count: 2)
            guard readExactly(fd, buffer: &responseBuffer, count: 2) else { return false }
            guard responseBuffer[0] == 0x05 else { return false }

            // 2. 账号密码认证阶段
            if responseBuffer[1] == 0x02 {
                guard !configuration.username.isEmpty || !configuration.password.isEmpty else { return false }
                let usernameBytes = [UInt8](configuration.username.utf8)
                let passwordBytes = [UInt8](configuration.password.utf8)

                // 长度防御性检查，防崩溃
                guard usernameBytes.count <= 255, passwordBytes.count <= 255 else { return false }

                var authRequest: [UInt8] = [0x01, UInt8(usernameBytes.count)] + usernameBytes + [UInt8(passwordBytes.count)] + passwordBytes
                guard fd.write(&authRequest, authRequest.count) == authRequest.count else { return false }

                var authResponse = [UInt8](repeating: 0, count: 2)
                guard readExactly(fd, buffer: &authResponse, count: 2) else { return false }
                guard authResponse[0] == 0x01, authResponse[1] == 0x00 else { return false }
            } else if responseBuffer[1] != 0x00 {
                return false // 不支持的认证方式
            }

            // 3. 连接请求阶段 (CONNECT)
            var request: [UInt8] = [0x05, 0x01, 0x00]
            if host.isIPv4 {
                request.append(0x01)
                guard let addr = host.addr else { return false }
                request += addr
            } else if host.isIPv6 {
                request.append(0x04)
                guard let addr = host.addr else { return false }
                request += addr
            } else {
                request.append(0x03)
                let domainBytes = [UInt8](host.utf8)
                guard domainBytes.count <= 255 else { return false } // 域名长度防溢出
                request.append(UInt8(domainBytes.count))
                request += domainBytes
            }

            let portNumber = UInt16(port) ?? 22
            request += portNumber.bytes.reversed() // 大端序端口号

            guard fd.write(&request, request.count) == request.count else { return false }

            // 4. 解析变长的 CONNECT 响应 header
            var header = [UInt8](repeating: 0, count: 4)
            guard readExactly(fd, buffer: &header, count: 4) else { return false }
            guard header[0] == 0x05, header[1] == 0x00 else { return false } // 0x00 代表成功

            // 根据 ATYP (地址类型) 动态消耗掉服务器返回的地址和端口字节
            var remainingBytesCount = 0
            switch header[3] {
            case 0x01: // IPv4 (4 字节地址 + 2 字节端口)
                remainingBytesCount = 4 + 2
            case 0x04: // IPv6 (16 字节地址 + 2 字节端口)
                remainingBytesCount = 16 + 2
            case 0x03: // 动态域名
                var domainLen = [UInt8](repeating: 0, count: 1)
                guard readExactly(fd, buffer: &domainLen, count: 1) else { return false }
                remainingBytesCount = Int(domainLen[0]) + 2
            default:
                return false
            }

            var dummyBuffer = [UInt8](repeating: 0, count: remainingBytesCount)
            guard readExactly(fd, buffer: &dummyBuffer, count: remainingBytesCount) else { return false }
        }
        return true
    }
}
