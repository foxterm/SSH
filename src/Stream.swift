// FoxTerm | Stream.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh2

/// SSH 写入流实现，将本地数据写入远程 SSH 渠道或 SFTP 文件
/// 继承自 OutputStream 以支持标准的 Swift IO 拷贝操作
class SSHInputStream: OutputStream {
    private var handle: OpaquePointer?
    private var ssh: SSH
    private let stream: StreamType

    init(handle: OpaquePointer?, ssh: SSH, stream: StreamType) {
        self.handle = handle
        self.stream = stream
        self.ssh = ssh
        super.init()
    }

    /// 执行数据写入操作
    /// 根据流类型（SFTP 或 Channel）调用对应的 libssh2 写入函数
    override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        ssh.callSSH2 { [self] in
            // 如果是 SFTP 流则调用 sftp_write，否则调用普通的 channel_write
            stream == .sftp ?
                libssh2_sftp_write(handle, buffer, len) :
                libssh2_channel_write_ex(handle, stream.value, buffer, len)
        }
    }

    override func open() {}
    override func close() {}

    /// 检查流是否可用
    override var hasSpaceAvailable: Bool {
        handle != nil
    }
}

/// SSH 读取流实现，从远程服务器读取数据
/// 继承自 InputStream，常用于下载文件或接收 Shell 输出
class SSHOutputStream: InputStream {
    private var handle: OpaquePointer?
    private var ssh: SSH
    private let stream: StreamType

    init(handle: OpaquePointer?, ssh: SSH, stream: StreamType) {
        self.handle = handle
        self.stream = stream
        self.ssh = ssh
        super.init()
    }

    /// 从远程渠道读取数据到指定缓冲区
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        ssh.callSSH2 { [self] in
            // 根据协议类型选择读取 API
            stream == .sftp ?
                libssh2_sftp_read(handle, buffer, len) :
                libssh2_channel_read_ex(handle, stream.value, buffer, len)
        }
    }

    override func open() {}
    override func close() {}

    /// 检查是否有数据可读
    override var hasBytesAvailable: Bool {
        handle != nil
    }
}

/// 专为 SCP 协议优化的输出流
/// 处理 SCP 传输中特有的文件大小边界与同步逻辑
class SCPOutputStream: InputStream {
    private var handle: OpaquePointer?
    private var ssh: SSH
    private let size: Int
    private var got: Int = 0 // 已读取的字节数
    private var nread: Int = 0 // 最近一次读取的字节数

    init(handle: OpaquePointer?, ssh: SSH, size: Int) {
        self.handle = handle
        self.size = size
        self.ssh = ssh
        super.init()
    }

    /// 带有边界检查的读取操作，确保不会读取超过 SCP 声明的文件大小
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        var amount = len
        // 边界保护：确保读取量不超过剩余未读大小
        if size - got < amount {
            amount = size - got
        }

        nread = ssh.callSSH2 { [self] in
            libssh2_channel_read_ex(handle, 0, buffer, amount)
        }

        if nread > 0 {
            got += nread
        }
        return nread
    }

    override func open() {}
    override func close() {}

    /// 只有在未达到预定大小且没有读取错误时才表示有数据
    override var hasBytesAvailable: Bool {
        handle != nil && got < size && nread >= 0
    }
}

/// 管道输出流，将读取到的数据通过闭包（Callback）重定向
/// 常用于实现自定义的数据处理逻辑，如内存缓存或实时日志解析
class PipeOutputStream: OutputStream {
    /// 数据到达时的回调，返回 Bool 决定是否继续接收数据
    let callback: (Data) -> Bool
    private var _ok: Bool = true

    init(_ callback: @escaping (Data) -> Bool) {
        self.callback = callback
        super.init()
    }

    /// 将写入流的数据包装成 Data 并分发给回调函数
    override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        _ok = callback(.init(bytes: buffer, count: len))
        // 如果回调返回 false，则返回 -1 表示流写入失败/中断
        return _ok ? len : -1
    }

    override func open() {}
    override func close() {}

    /// 根据回调状态判断流是否还允许写入
    override var hasSpaceAvailable: Bool {
        _ok
    }
}
