// FoxTerm | SFTPFile.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

// MARK: - SFTP 远程文件属性模型

/// SFTP 远程文件或目录的属性数据模型
public struct SFTPFile: Identifiable, Equatable, Hashable, Sendable {
    public var id = UUID()

    /// 文件名
    public let name: String
    /// 详细名称 listing 格式字符串
    public let longname: String
    /// 标志位
    public let flags: Int
    /// SFTP 文件类型标识
    public let type: SFTPFileType
    /// 文件字节大小
    public let size: Int64
    /// 所有者 User ID
    public let uid: Int
    /// 组 Group ID
    public let gid: Int
    /// 所有者用户名
    public let owner: String
    /// 组名称
    public let group: String
    /// POSIX 权限掩码
    public let permissions: Int

    /// 时间属性转换成 Swift 的 Date
    /// 最后访问时间
    public let accessTime: Date
    /// 创建时间
    public let creationTime: Date
    /// 最后修改时间
    public let modificationTime: Date

    /// 从 C 的 sftp_attributes 结构体初始化
    public init(attr: sftp_attributes_struct) {
        // C 字符串转换(可能为 nil)
        name = attr.name.flatMap { String(cString: $0) } ?? ""
        longname = attr.longname.flatMap { String(cString: $0) } ?? ""

        flags = attr.flags.int
        type = SFTPFileType(rawValue: attr.type)
        size = attr.size.int64
        uid = attr.uid.int
        gid = attr.gid.int

        owner = attr.owner.flatMap { String(cString: $0) } ?? ""
        group = attr.group.flatMap { String(cString: $0) } ?? ""
        permissions = attr.permissions.int

        // 优先使用 64 位时间戳，结合纳秒计算精准 Date
        accessTime = SFTPFile.parseDate(
            seconds: attr.atime.uint64,
            nanoseconds: attr.atime_nseconds
        )
        creationTime = SFTPFile.parseDate(
            seconds: attr.createtime,
            nanoseconds: attr.createtime_nseconds
        )
        modificationTime = SFTPFile.parseDate(
            seconds: attr.mtime64,
            nanoseconds: attr.mtime_nseconds
        )
    }

    /// 辅助计算函数：将 秒+纳秒 转为 Date
    private static func parseDate(seconds: UInt64, nanoseconds: UInt32) -> Date {
        let timeInterval = TimeInterval(seconds) + (TimeInterval(nanoseconds) / 1_000_000_000.0)
        return Date(timeIntervalSince1970: timeInterval)
    }
}

// MARK: - 文件属性便捷扩展

public extension SFTPFile {
    /// 提取文件的 POSIX Mode 类型
    var modeType: SFTPFileMode {
        SFTPFileMode.extractType(from: permissions.int32)
    }

    /// 是否为文件夹
    var isDirectory: Bool {
        type == .directory || modeType == .directory
    }

    /// 是否为符号链接
    var isSymlink: Bool {
        type == .symlink || modeType == .symlink
    }

    /// 是否为普通文件
    var isRegular: Bool {
        type == .regular || modeType == .regular
    }

    /// 是否为 Socket 文件
    var isSocket: Bool {
        modeType == .socket
    }

    /// 是否为块设备
    var isBlockDevice: Bool {
        modeType == .blockDevice
    }

    /// 是否为字符设备
    var isCharDevice: Bool {
        modeType == .charDevice
    }

    /// 是否为 FIFO / 命名管道
    var isFIFO: Bool {
        modeType == .fifo
    }

    /// 结构化的 POSIX 文件权限对象（所有者/属组/其他用户的读/写/执行权限）
    var filePermissions: FilePermissions {
        .init(rawValue: permissions.uint16)
    }

    /// POSIX 权限转为常见的 4 位 8 进制字符串(如 "0755")
    var permissionsOctalString: String {
        String(format: "%04o", permissions & 0o7777)
    }

    /// 获取完整的符号化权限字符串(如 "drwxr-xr-x")
    var symbolicFull: String {
        fileTypeSymbol + symbolic
    }

    /// 获取权限部分的符号化字符串(如 "rwxr-xr-x")
    var symbolic: String {
        filePermissions.symbolic
    }

    /// 获取代表文件类型的单个字符符号(精准映射八进制 mode 掩码)
    var fileTypeSymbol: String {
        switch modeType {
        case .regular: "-"
        case .directory: "d"
        case .symlink: "l"
        case .blockDevice: "b"
        case .charDevice: "c"
        case .fifo: "p"
        case .socket: "s"
        default: "?"
        }
    }
}
