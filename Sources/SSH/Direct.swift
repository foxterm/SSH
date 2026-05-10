// FoxTerm | Direct.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

/// SSH 转发管理类，支持 TCP 端口转发及 Unix Domain Socket 转发
public class Direct {
    /// 关联的通信通道
    let channel: Channel

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
    /// 获取底层的 libssh2 通道指针
    var rawChannel: OpaquePointer? {
        channel.rawChannel
    }

    /// 获取底层的 libssh2 会话指针
    var rawSession: OpaquePointer? {
        channel.rawSession
    }

    /// 直接 TCP/IP 转发 (Direct TCP/IP Forwarding)
    /// 类似于 ssh -L 功能，建立从本地到远程目标的 TCP 通道
    /// - Parameters:
    ///   - host: 目标主机地址
    ///   - port: 目标主机端口
    ///   - shost: 源主机地址（通常为 "localhost"）
    ///   - sport: 源主机端口
    ///   - read: 本地输入流（读取本地数据发往远程）
    ///   - write: 本地输出流（接收远程数据写向本地）
    /// - Returns: 转发通道是否成功建立
    public func tcpip(
        host: String, port: Int, shost: String, sport: Int, read: InputStream, write: OutputStream
    ) async -> Bool {
        guard rawSession != nil else {
            return false
        }
        // 开启直接 TCP/IP 转发通道
        channel.rawChannel = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_direct_tcpip_ex(rawSession, host, port.int32, shost, sport.int32)
        }
        guard rawChannel != nil else {
            return false
        }
        // 设置非阻塞并开始双向数据拷贝
        libssh2_channel_set_blocking(rawChannel, 0)
        await copy(read: read, write: write)
        return true
    }

    /// 直接流转发 (Direct Stream Local)
    /// 常用于转发 Unix Domain Socket，例如连接远程服务器的 /var/run/docker.sock
    /// - Parameters:
    ///   - socketPath: 远程 Socket 文件路径
    ///   - shost: 源主机地址
    ///   - sport: 源主机端口
    /// - Returns: 转发通道是否成功建立
    public func streamLocal(
        socketPath: String, shost: String, sport: Int, read: InputStream, write: OutputStream
    ) async -> Bool {
        guard rawSession != nil else {
            return false
        }
        // 开启 Unix Domain Socket 转发通道
        channel.rawChannel = await channel.ssh.callSSH2 { [self] in
            libssh2_channel_direct_streamlocal_ex(rawSession, socketPath, shost, sport.int32)
        }
        guard rawChannel != nil else {
            return false
        }
        libssh2_channel_set_blocking(rawChannel, 0)
        await copy(read: read, write: write)
        return true
    }

    /// 在本地流与 SSH 通道之间进行双向数据拷贝
    func copy(read: InputStream, write: OutputStream) async {
        guard rawChannel != nil else {
            return
        }
        // 并发处理双向流：
        // 1. 远程 -> 本地 (stdout 作为数据负载)
        async let toLocal = io.Copy(
            write,
            channel.read,
            channel.ssh.bufferSize
        )
        // 2. 本地 -> 远程
        async let toRemote = io.Copy(
            read,
            channel.write,
            channel.ssh.bufferSize
        )

        _ = await (toLocal, toRemote)
        close()
    }

    /// 关闭转发通道
    public func close() {
        channel.closeChannel()
    }
}
