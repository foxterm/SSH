// FoxTerm | FilePermissions.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh

/// 权限位选项集
/// 使用标准的二进制掩码: r=4 (1<<2), w=2 (1<<1), x=1 (1<<0)
public struct Permissions: OptionSet {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let read = Permissions(rawValue: 1 << 2) // 4 (二进制 100)
    public static let write = Permissions(rawValue: 1 << 1) // 2 (二进制 010)
    public static let execute = Permissions(rawValue: 1 << 0) // 1 (二进制 001)
}

public struct FilePermissions: RawRepresentable {
    /// 文件所有者 (Owner) 的权限集
    public var owner: Permissions

    /// 属组 (Group) 的权限集
    public var group: Permissions

    /// 其他用户 (Others) 的权限集
    public var others: Permissions

    /**
     初始化 FilePermissions 对象
     - Parameters:
     - owner: 文件所有者的权限
     - group: 属组用户的权限
     - others: 其他用户的权限
     */
    public init(owner: Permissions, group: Permissions, others: Permissions) {
        self.owner = owner
        self.group = group
        self.others = others
    }

    public init(rawValue: UInt16) {
        var owner: Permissions = []
        var group: Permissions = []
        var others: Permissions = []

        // 检查并设置所有者权限 (User)
        if rawValue & S_IRUSR == S_IRUSR {
            owner.insert(.read)
        }
        if rawValue & S_IWUSR == S_IWUSR {
            owner.insert(.write)
        }
        if rawValue & S_IXUSR == S_IXUSR {
            owner.insert(.execute)
        }

        // 检查并设置属组权限 (Group)
        if rawValue & S_IRGRP == S_IRGRP {
            group.insert(.read)
        }
        if rawValue & S_IWGRP == S_IWGRP {
            group.insert(.write)
        }
        if rawValue & S_IXGRP == S_IXGRP {
            group.insert(.execute)
        }

        // 检查并设置其他用户权限 (Others)
        if rawValue & S_IROTH == S_IROTH {
            others.insert(.read)
        }
        if rawValue & S_IWOTH == S_IWOTH {
            others.insert(.write)
        }
        if rawValue & S_IXOTH == S_IXOTH {
            others.insert(.execute)
        }

        self.init(owner: owner, group: group, others: others)
    }
}

public extension FilePermissions {
    /**
     计算并返回 SFTP 权限的原始位掩码
     将结构化权限对象重新编码为 POSIX 标准的模式位 (Mode bits)
     */
    var rawValue: UInt16 {
        var flag: UInt16 = 0

        // 组合所有者权限位
        if owner.contains(.read) {
            flag |= S_IRUSR
        }
        if owner.contains(.write) {
            flag |= S_IWUSR
        }
        if owner.contains(.execute) {
            flag |= S_IXUSR
        }

        // 组合属组权限位
        if group.contains(.read) {
            flag |= S_IRGRP
        }
        if group.contains(.write) {
            flag |= S_IWGRP
        }
        if group.contains(.execute) {
            flag |= S_IXGRP
        }

        // 组合其他用户权限位
        if others.contains(.read) {
            flag |= S_IROTH
        }
        if others.contains(.write) {
            flag |= S_IWOTH
        }
        if others.contains(.execute) {
            flag |= S_IXOTH
        }

        return flag
    }

    /// POSIX 权限转为常见的 8 进制字符串(如 "755")
    var permissionsOctalString: String {
        String(format: "%03o", rawValue & 0o777)
    }

    /// 获取权限部分的符号化字符串(如 "rwxr-xr-x")
    var symbolic: String {
        let masks: [(UInt16, UInt16, UInt16)] = [
            (S_IRUSR, S_IWUSR, S_IXUSR), // 所有者 (User)
            (S_IRGRP, S_IWGRP, S_IXGRP), // 属组 (Group)
            (S_IROTH, S_IWOTH, S_IXOTH), // 其他人 (Other)
        ]
        return masks.map { modeToSymbol(mask: $0) }.joined()
    }

    /// 将给定的读、写、执行掩码转换为 "rwx" 符号
    func modeToSymbol(mask: (r: UInt16, w: UInt16, x: UInt16)) -> String {
        var result = ""
        result += (rawValue & mask.r) != 0 ? "r" : "-"
        result += (rawValue & mask.w) != 0 ? "w" : "-"
        result += (rawValue & mask.x) != 0 ? "x" : "-"
        return result
    }

    /**
     默认文件权限
     通常为 0644(所有者读写，组只读，其他只读)
     */
    static let `default` = FilePermissions(
        owner: [.read, .write], group: [.read], others: [.read]
    )
}

/// POSIX 文件模式掩码封装(基于八进制定义)
public struct SFTPFileMode: OptionSet, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// 文件类型掩码 (00170000)
    public static let mask = SFTPFileMode(rawValue: SSH_S_IFMT)

    // 文件类型定义
    public static let socket = SFTPFileMode(rawValue: SSH_S_IFSOCK) // 0140000
    public static let symlink = SFTPFileMode(rawValue: SSH_S_IFLNK) // 0120000
    public static let regular = SFTPFileMode(rawValue: SSH_S_IFREG) // 0100000
    public static let blockDevice = SFTPFileMode(rawValue: SSH_S_IFBLK) // 0060000
    public static let directory = SFTPFileMode(rawValue: SSH_S_IFDIR) // 0040000
    public static let charDevice = SFTPFileMode(rawValue: SSH_S_IFCHR) // 0020000
    public static let fifo = SFTPFileMode(rawValue: SSH_S_IFIFO) // 0010000

    /// 从原始 permissions(mode) 中提取文件类型
    public static func extractType(from mode: Int32) -> SFTPFileMode {
        SFTPFileMode(rawValue: mode & SSH_S_IFMT)
    }
}

/// 匹配 C 结构体中的 SFTP 属性文件类型标识
public enum SFTPFileType: UInt8, Hashable, Sendable {
    case regular
    case directory
    case symlink
    case special
    case unknown

    public init(rawValue: UInt8) {
        switch rawValue.int32 {
        case SSH_FILEXFER_TYPE_REGULAR: self = .regular
        case SSH_FILEXFER_TYPE_DIRECTORY: self = .directory
        case SSH_FILEXFER_TYPE_SYMLINK: self = .symlink
        case SSH_FILEXFER_TYPE_SPECIAL: self = .special
        case SSH_FILEXFER_TYPE_UNKNOWN: self = .unknown
        default: self = .unknown
        }
    }
}
