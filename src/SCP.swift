// FoxTerm | SCP.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh2

/// SCP 协议处理类，支持基于 SSH 通道的安全文件上传与下载
public class SCP {
    /// 关联的通信通道
    let channel: Channel

    init(channel: Channel) {
        self.channel = channel
    }

    deinit {
        #if DEBUG
            print("♻️", "SCP")
        #endif
    }
}

public extension SCP {
    /// 获取底层的 libssh2 通道指针
    internal var rawChannel: OpaquePointer? {
        channel.rawChannel
    }

    /// 获取底层的 libssh2 会话指针
    internal var rawSession: OpaquePointer? {
        channel.rawSession
    }

    /// 上传本地文件到远程路径
    /// - Parameters:
    ///   - localPath: 本地文件完整路径
    ///   - remotePath: 远程目标路径
    ///   - mode: 文件权限位 (默认 0o0644)
    ///   - progress: 进度回调，返回已发送字节数；返回 false 可终止传输
    /// - Returns: 是否上传成功
    func upload(
        localPath: String,
        remotePath: String,
        mode: Int32 = 0o0644,
        progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Bool {
        guard let stream = InputStream(fileAtPath: localPath) else {
            return false
        }
        // 获取本地文件大小（Int64 支持大文件）
        guard let size = try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64 else {
            return false
        }
        return await upload(stream: stream, size: size, remotePath: remotePath, mode: mode, progress: progress)
    }

    /// 上传 Data 数据到远程路径
    func upload(
        data: Data,
        remotePath: String,
        mode: Int32 = 0o0644,
        progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Bool {
        await upload(
            stream: .init(data: data),
            size: Int64(data.count),
            remotePath: remotePath,
            mode: mode,
            progress: progress
        )
    }

    /// 通过流上传指定大小的数据到远程路径
    func upload(
        stream: InputStream,
        size: Int64,
        remotePath: String,
        mode: Int32 = 0o0644,
        progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Bool {
        // 如果通道被占用，先安全关闭
        if rawChannel != nil {
            channel.closeChannel()
        }
        guard rawSession != nil else {
            return false
        }
        // 初始化 SCP 发送会话 (使用 64 位版本以支持 >2GB 文件)
        channel.rawChannel = await channel.ssh.callSSH2 { [self] in
            libssh2_scp_send64(rawSession, remotePath, mode, size, 0, 0)
        }
        guard rawChannel != nil else {
            return false
        }
        libssh2_channel_set_blocking(rawChannel, 0)

        // 执行 I/O 拷贝，校验读取字节数是否等于预设大小
        let bytesSent = await io.Copy(
            stream,
            SSHInputStream(handle: rawChannel, ssh: channel.ssh, stream: .stdout),
            channel.ssh.bufferSize,
            progress
        )

        guard bytesSent == size.int else {
            _ = channel.sendEof()
            channel.closeChannel()
            return false
        }

        _ = channel.sendEof()
        channel.closeChannel()
        return true
    }

    /// 下载远程文件到本地路径
    /// - Parameters:
    ///   - localPath: 本地保存路径
    ///   - remotePath: 远程源路径
    ///   - progress: 进度回调 (已接收字节, 总字节)
    func download(
        localPath: String,
        remotePath: String,
        progress: @escaping (_ send: Int, _ size: Int) -> Bool = { _, _ in true }
    ) async -> Bool {
        guard let stream = OutputStream(toFileAtPath: localPath, append: false) else {
            return false
        }
        return await download(stream: stream, remotePath: remotePath, progress: progress)
    }

    /// 下载远程文件并返回 Data 内存数据
    func download(remotePath: String, progress: @escaping (_ send: Int, _ size: Int) -> Bool = { _, _ in true }) async -> Data? {
        let stream = OutputStream.toMemory()
        guard await download(stream: stream, remotePath: remotePath, progress: progress) else {
            return nil
        }
        return stream.data
    }

    /// 通过流接收远程文件数据
    func download(
        stream: OutputStream,
        remotePath: String,
        progress: @escaping (_ send: Int, _ size: Int) -> Bool = { _, _ in true }
    ) async -> Bool {
        if rawChannel != nil {
            channel.closeChannel()
        }
        guard rawSession != nil else {
            return false
        }
        var fileinfo = libssh2_struct_stat()
        // 初始化 SCP 接收会话，获取文件元数据
        channel.rawChannel = await channel.ssh.callSSH2 { [self] in
            libssh2_scp_recv2(rawSession, remotePath, &fileinfo)
        }
        guard rawChannel != nil else {
            return false
        }
        libssh2_channel_set_blocking(rawChannel, 0)

        let size = fileinfo.st_size.int
        // 处理空文件情况
        guard size > 0 else {
            channel.closeChannel()
            return true
        }

        // 使用专用的 SCPOutputStream 处理接收
        let rc = await io.Copy(
            stream,
            SCPOutputStream(handle: rawChannel, ssh: channel.ssh, size: size),
            channel.ssh.bufferSize
        ) { send in
            progress(send, size)
        }

        guard rc == size else {
            channel.closeChannel()
            return false
        }
        channel.closeChannel()
        return true
    }

    /// 获取远程文件状态信息 (如大小、权限、修改时间)
    /// - Parameter filename: 远程文件路径
    /// - Returns: stat 结构体，失败返回 nil
    func pathStat(_ filename: String) async -> stat? {
        if rawChannel != nil {
            channel.closeChannel()
        }
        guard rawSession != nil else {
            return nil
        }
        var fileinfo = libssh2_struct_stat()
        channel.rawChannel = await channel.ssh.callSSH2 { [self] in
            libssh2_scp_recv2(rawSession, filename, &fileinfo)
        }
        guard rawChannel != nil else {
            return nil
        }
        channel.closeChannel()
        return fileinfo
    }
}
