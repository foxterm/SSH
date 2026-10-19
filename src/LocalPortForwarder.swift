// FoxTerm | LocalPortForwarder.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import Network

/// 本地端口转发器，通过 SSH 隧道将本地端口映射到远程 TCP 或 Unix Socket
///
/// 使用 Network.framework 的 `NWListener` 在本地监听指定端口，
/// 每个新连接通过 SSH 的 Direct TCP/IP 或 Unix Socket 转发通道桥接到远程目标。
public class LocalPortForwarder {
    /// 转发目标枚举
    public enum ForwardTarget {
        /// TCP 目标（如 127.0.0.1:3306）
        case tcp(host: String, port: Int)
        /// Unix Socket 目标（如 /var/run/docker.sock）
        case unixSocket(path: String)
    }

    private let listener: NWListener
    private weak var ssh: SSH?
    private let target: ForwardTarget

    /// 创建一个本地端口转发监听器
    public init(localPort: UInt16, target: ForwardTarget, ssh: SSH) throws {
        guard let port = NWEndpoint.Port(rawValue: localPort) else {
            throw LocalPortForwarderError.invalidPort(localPort)
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: port
        )

        listener = try NWListener(using: parameters)
        self.ssh = ssh
        self.target = target
    }

    /// 便捷构造器：仅 TCP 转发
    public convenience init(localPort: UInt16, remoteHost: String, remotePort: Int, ssh: SSH) throws {
        try self.init(localPort: localPort, target: .tcp(host: remoteHost, port: remotePort), ssh: ssh)
    }

    /// 便捷构造器：仅 Unix Socket 转发
    public convenience init(localPort: UInt16, socketPath: String, ssh: SSH) throws {
        try self.init(localPort: localPort, target: .unixSocket(path: socketPath), ssh: ssh)
    }

    /// 启动本地转发服务
    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    /// 停止转发服务
    public func stop() {
        listener.cancel()
    }

    /// 处理新的本地连接：创建双向 Stream 管道并桥接到 SSH 转发通道
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        // 上行流对(Client -> SSH)
        var sshInputStream: InputStream?
        var boundUpstreamOutput: OutputStream?
        Stream.getBoundStreams(withBufferSize: 64 << 10, inputStream: &sshInputStream, outputStream: &boundUpstreamOutput)

        // 下行流对(SSH -> Client)
        var boundDownstreamInput: InputStream?
        var sshOutputStream: OutputStream?
        Stream.getBoundStreams(withBufferSize: 64 << 10, inputStream: &boundDownstreamInput, outputStream: &sshOutputStream)

        guard let sshInputStream, let boundUpstreamOutput,
              let boundDownstreamInput, let sshOutputStream,
              let ssh
        else {
            connection.cancel()
            return
        }

        boundUpstreamOutput.open()
        boundDownstreamInput.open()

        // 1. 双向桥接泵
        bridgeClientToSSH(connection: connection, upstreamOutput: boundUpstreamOutput)
        bridgeSSHToClient(connection: connection, downstreamInput: boundDownstreamInput)

        // 2. 根据目标选择调用正确的 SSH API
        let forwardTarget = target
        Task {
            switch forwardTarget {
            case let .tcp(host, port):
                await ssh.sshOpenDirectTCPIP(
                    remoteHost: host,
                    remotePort: port,
                    outputStream: sshOutputStream,
                    inputStream: sshInputStream
                )
            case let .unixSocket(path):
                await ssh.sshOpenUnixSocket(
                    socketPath: path,
                    outputStream: sshOutputStream,
                    inputStream: sshInputStream
                )
            }
        }
    }

    /// 上行：Client -> SSH (修复内存安全)
    private func bridgeClientToSSH(connection: NWConnection, upstreamOutput: OutputStream) {
        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { [weak upstreamOutput] data, _, isComplete, error in
                guard let upstreamOutput else {
                    connection.cancel()
                    return
                }

                if let data, !data.isEmpty {
                    let bytes = [UInt8](data)
                    _ = upstreamOutput.write(bytes, maxLength: bytes.count)
                }

                if isComplete || error != nil {
                    upstreamOutput.close()
                    connection.cancel()
                } else {
                    receiveNext()
                }
            }
        }
        receiveNext()
    }

    /// 下行：SSH -> Client
    private func bridgeSSHToClient(connection: NWConnection, downstreamInput: InputStream) {
        Task.detached(priority: .userInitiated) {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 << 10)
            defer {
                buffer.deallocate()
                downstreamInput.close()
            }

            while downstreamInput.streamStatus != .closed, downstreamInput.streamStatus != .error {
                let readCount = downstreamInput.read(buffer, maxLength: 64 << 10)
                if readCount <= 0 {
                    break
                }

                let data = Data(bytes: buffer, count: readCount)
                connection.send(content: data, completion: .contentProcessed { error in
                    if error != nil {
                        connection.cancel()
                    }
                })
            }
        }
    }
}

/// 本地端口转发错误
public enum LocalPortForwarderError: Error, CustomStringConvertible {
    /// 端口号非法(0 不被 NWEndpoint.Port 接受)
    case invalidPort(UInt16)

    public var description: String {
        switch self {
        case let .invalidPort(port):
            "Invalid local port: \(port) (port 0 is not supported)"
        }
    }
}
