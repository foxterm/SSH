// FoxTerm | Proxy.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import Socket

/// 企业级代理客户端类，支持通过 HTTP/HTTPS CONNECT 与 SOCKS5 协议建立隧道连接
public class Proxy: Sendable {
    /// 代理配置项（包含代理主机、端口、认证凭据及代理类型）
    public let configuration: ProxyConfig

    /// 使用指定的代理配置初始化 Proxy 实例
    /// - Parameter configuration: 代理配置对象 `ProxyConfig`
    public init(_ configuration: ProxyConfig) {
        self.configuration = configuration
    }
}

public extension Proxy {
    /// 异步通过代理服务器建立到目标远程主机的 Socket 连接
    ///
    /// 建立连接流程：
    /// 1. 创建到代理服务器的底层 TCP 套接字；
    /// 2. 若目标为域名，解析 DNS 并遍历 IP 进行依次重试；
    /// 3. 切换至阻塞模式完成代理协议握手（HTTP CONNECT 或 SOCKS5）；
    /// 4. 握手成功后恢复非阻塞状态并返回，若全部失败则安全清理资源。
    ///
    /// - Parameters:
    ///   - host: 目标远程主机的域名或 IP 地址
    ///   - port: 目标远程主机的服务端口
    ///   - timeout: 连接代理服务器的超时时间（秒），默认 5 秒
    /// - Returns: 连接成功且完成代理握手的 `Socket` 实例；若失败则返回无效 Socket (`fd == -1`)
    func connect(_ host: String, _ port: String, _ timeout: Int = 5) async -> Socket {
        var socket = await Socket.create(configuration.host, configuration.port, timeout)
        guard socket.isConnected else {
            return Socket()
        }

        // 切换为阻塞模式以安全执行同步代理握手
        socket.setBlocking(true)

        // 解析目标 host 对应的 IP 列表并逐个尝试建立代理通道
        let targetIPs = await IP.resolveDomainName(host)
        let candidateHosts = targetIPs.isEmpty ? [host] : targetIPs

        for ip in candidateHosts {
            if performHandshake(on: socket, targetHost: ip, targetPort: port) {
                // 代理握手成功，恢复非阻塞模式供上层 I/O 事件循环（如 SwiftNIO/Poll）使用
                socket.setBlocking(false)
                return socket
            }
        }

        // 所有尝试均失败，主动回收 Socket 句柄以防资源泄漏
        socket.close()
        return Socket()
    }

    /// 从 Socket 准确读取指定字节长度的数据（确保完全填满 Buffer）
    ///
    /// - Parameters:
    ///   - socket: 底层网络套接字
    ///   - buffer: 存放读取数据的内存目标指针
    ///   - count: 需要读取的精确字节数
    /// - Returns: `true` 表示精确读取到指定字节数；`false` 表示中途遇到 EOF、断开连接或 I/O 错误
    func readExactly(_ socket: Socket, buffer: UnsafeMutablePointer<UInt8>, count: Int) -> Bool {
        var totalRead = 0
        while totalRead < count {
            let bytesToRead = count - totalRead
            let rc = socket.read(buffer.advanced(by: totalRead), bytesToRead)
            if rc <= 0 {
                return false // 连接中断或遇到系统错误
            }
            totalRead += rc
        }
        return true
    }

    /// 针对 Socket 执行 HTTP / SOCKS5 代理协议握手的核心内部方法
    ///
    /// - Parameters:
    ///   - socket: 已经建立 TCP 连接的代理 Socket
    ///   - host: 目标主机地址
    ///   - port: 目标主机端口
    /// - Returns: `true` 握手成功并建立隧道，`false` 握手失败
    func performHandshake(on socket: Socket, targetHost host: String, targetPort port: String) -> Bool {
        switch configuration.type {
        case .http:
            handshakeHTTP(on: socket, targetHost: host, targetPort: port)
        case .socks5:
            handshakeSOCKS5(on: socket, targetHost: host, targetPort: port)
        }
    }
}

// MARK: - Private Protocol Handshakes

private extension Proxy {
    /// 执行 HTTP CONNECT 代理隧道建立协议
    func handshakeHTTP(on socket: Socket, targetHost host: String, targetPort port: String) -> Bool {
        var connectString = "CONNECT \(host):\(port) HTTP/1.1\r\n"
        if !configuration.username.isEmpty || !configuration.password.isEmpty {
            let authStr = "\(configuration.username):\(configuration.password)"
            let authData = Data(authStr.utf8).base64EncodedString()
            connectString += "Proxy-Authorization: Basic \(authData)\r\n"
        }
        connectString += "Host: \(host):\(port)\r\n"
        connectString += "User-Agent: FoxTerm/1.0\r\n\r\n"
        let bytes = [UInt8](connectString.utf8)
        guard socket.write(bytes, bytes.count) == bytes.count else { return false }

        // HTTP Header 响应解析：精准逐字节扫描 `\r\n\r\n` 分隔符，防止粘包影响后续流式数据
        var headerData = Data()
        var singleByte: UInt8 = 0

        while headerData.count < 8192 { // 8KB 防爆限制
            guard readExactly(socket, buffer: &singleByte, count: 1) else { return false }
            headerData.append(singleByte)

            let count = headerData.count
            if count >= 4,
               headerData[count - 4] == 0x0D, headerData[count - 3] == 0x0A,
               headerData[count - 2] == 0x0D, headerData[count - 1] == 0x0A
            {
                break
            }
        }

        guard let responseString = String(data: headerData, encoding: .ascii) else { return false }

        // 校验 HTTP Status Line 是否符合 200 OK
        let firstLine = responseString.components(separatedBy: "\r\n").first ?? ""
        return firstLine.contains(" 200 ") || firstLine.hasPrefix("HTTP/1.1 200") || firstLine.hasPrefix("HTTP/1.0 200")
    }

    /// 执行 SOCKS5 代理协议三阶段握手（Greeting -> Auth -> Connect）
    func handshakeSOCKS5(on socket: Socket, targetHost host: String, targetPort port: String) -> Bool {
        // 1. 协商认证阶段 (Greeting)
        let hasAuth = !configuration.username.isEmpty || !configuration.password.isEmpty
        var greeting: [UInt8] = hasAuth ? [0x05, 0x01, 0x02] : [0x05, 0x01, 0x00]

        guard socket.write(&greeting, greeting.count) == greeting.count else { return false }

        var responseBuffer = [UInt8](repeating: 0, count: 2)
        guard readExactly(socket, buffer: &responseBuffer, count: 2) else { return false }
        guard responseBuffer[0] == 0x05 else { return false } // 验证 SOCKS 协议版本 5

        // 2. 用户名 / 密码子认证阶段 (RFC 1929)
        if responseBuffer[1] == 0x02 { // 0x02 代表 SERVER 要求 USERNAME/PASSWORD 认证
            guard hasAuth else { return false }
            let usernameBytes = [UInt8](configuration.username.utf8)
            let passwordBytes = [UInt8](configuration.password.utf8)

            // 针对 RFC 1929 协议做 255 字节边界保护，防止溢出攻击
            guard usernameBytes.count <= 255, passwordBytes.count <= 255 else { return false }

            var authRequest: [UInt8] = [0x01, UInt8(usernameBytes.count)] + usernameBytes + [UInt8(passwordBytes.count)] + passwordBytes
            guard socket.write(&authRequest, authRequest.count) == authRequest.count else { return false }

            var authResponse = [UInt8](repeating: 0, count: 2)
            guard readExactly(socket, buffer: &authResponse, count: 2) else { return false }
            guard authResponse[0] == 0x01, authResponse[1] == 0x00 else { return false } // 0x00 代表认证成功
        } else if responseBuffer[1] != 0x00 { // 0x00 代表无需认证，其余响应码均为失败或不匹配
            return false
        }

        // 3. 建立连接请求阶段 (CONNECT Request)
        var request: [UInt8] = [0x05, 0x01, 0x00] // VER=5, CMD=1(CONNECT), RSV=0
        if host.isIPv4 {
            request.append(0x01) // ATYP: IPv4 (4 字节)
            guard let addr = host.addr else { return false }
            request += addr
        } else if host.isIPv6 {
            request.append(0x04) // ATYP: IPv6 (16 字节)
            guard let addr = host.addr else { return false }
            request += addr
        } else {
            request.append(0x03) // ATYP: 域名 (1 字节 Length + Domain 字节)
            let domainBytes = [UInt8](host.utf8)
            guard domainBytes.count <= 255 else { return false }
            request.append(UInt8(domainBytes.count))
            request += domainBytes
        }

        // 写入大端序 (Network Byte Order) 目标端口号
        let portNumber = UInt16(port) ?? 22
        request += [UInt8(portNumber >> 8), UInt8(portNumber & 0xFF)]

        guard socket.write(&request, request.count) == request.count else { return false }

        // 4. 解析 SOCKS5 CONNECT 响应头
        var header = [UInt8](repeating: 0, count: 4)
        guard readExactly(socket, buffer: &header, count: 4) else { return false }
        guard header[0] == 0x05, header[1] == 0x00 else { return false } // REP=0x00 代表连接成功

        // 根据响应中的 ATYP 消费掉剩余的服务器绑定地址与端口，保持 Socket 缓冲区干净
        var remainingBytesCount = 0
        switch header[3] {
        case 0x01: // IPv4 (4 字节地址 + 2 字节端口)
            remainingBytesCount = 4 + 2
        case 0x04: // IPv6 (16 字节地址 + 2 字节端口)
            remainingBytesCount = 16 + 2
        case 0x03: // 变长域名 (1 字节 Length + N 字节域名 + 2 字节端口)
            var domainLen = [UInt8](repeating: 0, count: 1)
            guard readExactly(socket, buffer: &domainLen, count: 1) else { return false }
            remainingBytesCount = Int(domainLen[0]) + 2
        default:
            return false
        }

        var dummyBuffer = [UInt8](repeating: 0, count: remainingBytesCount)
        return readExactly(socket, buffer: &dummyBuffer, count: remainingBytesCount)
    }
}
