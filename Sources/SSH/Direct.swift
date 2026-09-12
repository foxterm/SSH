// FoxTerm | Direct.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

/// SSH 端口/Socket 转发管理类
///
/// 该类用于管理基于 libssh2 的底层通道转发逻辑，主要包含以下功能：
/// - **Direct TCP/IP**: 实现类似于 `ssh -L` 的本地端口转发。
/// - **Direct Stream Local**: 实现对远程 Unix Domain Socket 的直接流转发（例如连接远程 `/var/run/docker.sock`）。
public class Direct {
    /// 关联的通信通道对象
    let channel: Channel

    /// 初始化转发实例
    /// - Parameter channel: 绑定的 SSH 基础通道
    init(channel: Channel) {
        self.channel = channel
    }

    deinit {
        #if DEBUG
            print("♻️", "Forward")
        #endif
    }
}

extension Direct {
    /// 获取底层的 libssh2 通道句柄指针 (`LIBSSH2_CHANNEL*`)
    var rawChannel: OpaquePointer? {
        channel.rawChannel
    }

    /// 获取底层的 libssh2 会话句柄指针 (`LIBSSH2_SESSION*`)
    var rawSession: OpaquePointer? {
        channel.rawSession
    }

    /// 建立直接 TCP/IP 转发通道 (Direct TCP/IP Forwarding)
    ///
    /// 类似于 `ssh -L local_port:remote_host:remote_port` 功能。
    /// 建立从本地数据流到目标主机与端口的底层 TCP 通道，并在建立成功后开始双向数据传输。
    ///
    /// - Parameters:
    ///   - host: 目标主机地址或域名（远程服务器可达的地址）
    ///   - port: 目标主机 TCP 端口
    ///   - shost: 源主机地址（通常填写 `"127.0.0.1"` 或 `"localhost"`）
    ///   - sport: 源主机绑定端口
    ///   - read: 本地输入流（用于读取本地数据并发送至远程 SSH 通道）
    ///   - write: 本地输出流（用于接收远程通道数据并写入本地）
    /// - Returns: `true` 表示转发通道成功建立且传输正常完成；`false` 表示 Session 无效或创建通道失败
    public func tcpip(
        host: String, port: Int, shost: String = "127.0.0.1", sport: Int = 22, read: InputStream, write: OutputStream
    ) async -> Bool {
        guard rawSession != nil else {
            return false
        }

        // 异步向 libssh2 请求建立直接 TCP/IP 转发通道
        channel.rawChannel = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_direct_tcpip_ex(rawSession, host.bytesArray, port.int32, shost.bytesArray, sport.int32)
        }

        guard rawChannel != nil else {
            return false
        }

        // 设置底层通道为非阻塞模式，并开始进行本地与远程之间的双向数据拷贝
        libssh2_channel_set_blocking(rawChannel, 0)
        await copy(read: read, write: write)
        return true
    }

    /// 建立直接流转发通道 (Direct Stream Local Forwarding)
    ///
    /// 常用于转发远程服务器的 Unix Domain Socket 文件（例如 Docker Socket 或数据库套接字）。
    ///
    /// - Parameters:
    ///   - socketPath: 远程 Socket 文件绝对路径（如 `/var/run/docker.sock`）
    ///   - shost: 源主机地址（通常为 `"localhost"`）
    ///   - sport: 源主机端口
    ///   - read: 本地输入流（用于读取本地数据并发送至远程 Socket）
    ///   - write: 本地输出流（用于接收远程 Socket 数据并写入本地）
    /// - Returns: `true` 表示 Socket 通道建立成功；`false` 表示 Session 无效或创建通道失败
    public func streamLocal(
        socketPath: String, shost: String = "127.0.0.1", sport: Int = 22, read: InputStream, write: OutputStream
    ) async -> Bool {
        guard rawSession != nil else {
            return false
        }

        // 异步向 libssh2 请求建立 Unix Domain Socket 转发通道
        channel.rawChannel = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_direct_streamlocal_ex(rawSession, socketPath.bytesArray, shost.bytesArray, sport.int32)
        }

        guard rawChannel != nil else {
            return false
        }

        // 设置底层通道为非阻塞模式并启动数据传输
        libssh2_channel_set_blocking(rawChannel, 0)
        await copy(read: read, write: write)
        return true
    }

    /// 注册本地 I/O 流与 SSH 通道之间的数据轮询与拷贝
    ///
    /// 将输入输出流挂载至 `channelPoll` 事件循环中，传输结束后会自动调用 `close()` 关闭通道。
    ///
    /// - Parameters:
    ///   - read: 读取数据的输入流
    ///   - write: 写入数据的输出流
    func copy(read: InputStream, write: OutputStream) async {
        guard let rawChannel else {
            return
        }

        // 将 SSH 通道句柄与本地 Foundation 流挂载至事件轮询器中
        await channel.ssh.channelPoll.register(
            handle: rawChannel,
            output: write,
            outerr: nil,
            write: read
        )

        // 数据传输完成或流关闭后，释放清理 SSH 通道
        close()
    }

    /// 关闭并释放当前转发通道
    public func close() {
        channel.closeChannel()
    }
}
