// FoxTerm | File.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh2

/// 远程文件的完整状态信息
/// 对应 `stat` 命令获取的元数据
public struct FileStat: Identifiable, Equatable {
    public static func == (lhs: FileStat, rhs: FileStat) -> Bool {
        lhs.id == rhs.id
    }

    public let id = UUID()

    /// 文件类型（目录、常规文件、链接等）
    public let fileType: FileType

    /// 文件字节大小
    public let size: UInt64

    /// 所有者用户 ID (UID)
    public let userId: UInt

    /// 所属组 ID (GID)
    public let groupId: UInt

    /// 解析后的权限对象（rwx 结构）
    public let permissions: FilePermissions

    /// 最后访问时间
    public let lastAccessed: Date

    /// 最后修改时间
    public let lastModified: Date

    /// 使用 libssh2 原始属性结构体进行初始化
    init(attributes: LIBSSH2_SFTP_ATTRIBUTES) {
        fileType = FileType(rawValue: Int32(attributes.permissions))
        size = attributes.filesize
        userId = attributes.uid
        groupId = attributes.gid
        permissions = FilePermissions(rawValue: Int32(attributes.permissions))
        lastAccessed = Date(timeIntervalSince1970: Double(attributes.atime))
        lastModified = Date(timeIntervalSince1970: Double(attributes.mtime))
    }
}

/// 文件列表项属性
/// 包含文件名及通过解析长格式字符串（Longname）获得的扩展信息
public struct FileAttributes: Identifiable, Equatable {
    public static func == (lhs: FileAttributes, rhs: FileAttributes) -> Bool {
        lhs.id == rhs.id
    }

    public let id = UUID()

    /// 文件名
    public let name: String

    /// 标准 ls -l 格式的长名称字符串
    public let longname: String

    /// 文件字节大小
    public let size: Int64

    /// 所有者用户名（从 longname 解析）
    public let user: String

    /// 所属组名（从 longname 解析）
    public let group: String

    /// 用户 ID
    public let userId: UInt

    /// 组 ID
    public let groupId: UInt

    /// 文件权限位模式
    public let mode: FileMode

    /// 最后访问时间
    public let lastAccessed: Date

    /// 最后修改时间
    public let lastModified: Date

    /// 内部初始化方法
    init(attributes: LIBSSH2_SFTP_ATTRIBUTES) {
        name = ""
        longname = ""
        size = Int64(attributes.filesize)
        userId = attributes.uid
        groupId = attributes.gid
        mode = FileMode(attributes.permissions)
        lastAccessed = Date(timeIntervalSince1970: Double(attributes.atime))
        lastModified = Date(timeIntervalSince1970: Double(attributes.mtime))
        user = ""
        group = ""
    }

    /// 用于快速构建“返回上一级 (..)”的虚拟目录对象
    public init() {
        name = ".."
        longname = ""
        size = 0
        userId = 0
        groupId = 0
        mode = 0
        lastAccessed = .now
        lastModified = .now
        user = ""
        group = ""
    }

    /// 使用文件名、长名称和原始属性进行完整初始化
    init(name: String, longname: String, attributes: LIBSSH2_SFTP_ATTRIBUTES) {
        self.name = name
        self.longname = longname
        size = Int64(attributes.filesize)
        userId = attributes.uid
        groupId = attributes.gid
        mode = FileMode(attributes.permissions)
        lastAccessed = Date(timeIntervalSince1970: Double(attributes.atime))
        lastModified = Date(timeIntervalSince1970: Double(attributes.mtime))

        // 尝试从长名称中提取所有者和组名
        user = sftpParseLongname(longname, .owner) ?? ""
        group = sftpParseLongname(longname, .group) ?? ""
    }
}

/// SFTP 长名称字段索引（基于标准 ls -l 格式）
enum SFTPField: Int {
    case perm = 0 // 权限位字符串
    case fixme // 通常是链接数
    case owner // 用户名
    case group // 组名
    case size // 大小
    case moon // 月份
    case day // 日期
    case time // 时间/年份
}

/// 解析 SFTP 长名称中的特定字段
/// - Parameters:
///   - longname: 原始长格式字符串
///   - field: 目标字段枚举
/// - Returns: 解析后的字符串片段
func sftpParseLongname(_ longname: String, _ field: SFTPField) -> String? {
    // 按空格拆分，过滤掉多余的空格
    let components = longname.split(separator: " ").filter { !$0.isEmpty }
    // 确保组件数量足够，且索引不越界
    guard components.count >= 8, field.rawValue < components.count else { return nil }
    return String(components[field.rawValue])
}

/// 权限位选项集
/// 使用 Bitmask (1<<1, 1<<2, 1<<3) 对应 r、w、x
public struct Permissions: OptionSet {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let read = Permissions(rawValue: 1 << 1)
    public static let write = Permissions(rawValue: 1 << 2)
    public static let execute = Permissions(rawValue: 1 << 3)
}

// FoxTerm | File.swift (FilePermissions 扩展)

/// 文件权限结构体，遵循 RawRepresentable 协议以便与 libssh2 的 Int32 权限位互转
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

    /**
     通过原始整数值（Bitmask）初始化权限对象
     解析 POSIX 标准的权限位并映射到 owner/group/others 三个维度
     - Parameter rawValue: 包含文件类型和权限信息的 32 位整数
     */
    public init(rawValue: Int32) {
        var owner: Permissions = []
        var group: Permissions = []
        var others: Permissions = []

        // 检查并设置所有者权限 (User)
        if rawValue & LIBSSH2_SFTP_S_IRUSR == LIBSSH2_SFTP_S_IRUSR { owner.insert(.read) }
        if rawValue & LIBSSH2_SFTP_S_IWUSR == LIBSSH2_SFTP_S_IWUSR { owner.insert(.write) }
        if rawValue & LIBSSH2_SFTP_S_IXUSR == LIBSSH2_SFTP_S_IXUSR { owner.insert(.execute) }

        // 检查并设置属组权限 (Group)
        if rawValue & LIBSSH2_SFTP_S_IRGRP == LIBSSH2_SFTP_S_IRGRP { group.insert(.read) }
        if rawValue & LIBSSH2_SFTP_S_IWGRP == LIBSSH2_SFTP_S_IWGRP { group.insert(.write) }
        if rawValue & LIBSSH2_SFTP_S_IXGRP == LIBSSH2_SFTP_S_IXGRP { group.insert(.execute) }

        // 检查并设置其他用户权限 (Others)
        if rawValue & LIBSSH2_SFTP_S_IROTH == LIBSSH2_SFTP_S_IROTH { others.insert(.read) }
        if rawValue & LIBSSH2_SFTP_S_IWOTH == LIBSSH2_SFTP_S_IWOTH { others.insert(.write) }
        if rawValue & LIBSSH2_SFTP_S_IXOTH == LIBSSH2_SFTP_S_IXOTH { others.insert(.execute) }

        self.init(owner: owner, group: group, others: others)
    }

    /// 获取权限的无符号整数表示，常用于 libssh2 内部 API
    public var rawUInt: UInt {
        UInt(rawValue)
    }

    /// 获取权限的整数表示
    public var rawInt: Int {
        Int(rawValue)
    }

    /**
     计算并返回 SFTP 权限的原始位掩码
     将结构化权限对象重新编码为 POSIX 标准的模式位 (Mode bits)
     */
    public var rawValue: Int32 {
        var flag: Int32 = 0

        // 组合所有者权限位
        if owner.contains(.read) { flag |= LIBSSH2_SFTP_S_IRUSR }
        if owner.contains(.write) { flag |= LIBSSH2_SFTP_S_IWUSR }
        if owner.contains(.execute) { flag |= LIBSSH2_SFTP_S_IXUSR }

        // 组合属组权限位
        if group.contains(.read) { flag |= LIBSSH2_SFTP_S_IRGRP }
        if group.contains(.write) { flag |= LIBSSH2_SFTP_S_IWGRP }
        if group.contains(.execute) { flag |= LIBSSH2_SFTP_S_IXGRP }

        // 组合其他用户权限位
        if others.contains(.read) { flag |= LIBSSH2_SFTP_S_IROTH }
        if others.contains(.write) { flag |= LIBSSH2_SFTP_S_IWOTH }
        if others.contains(.execute) { flag |= LIBSSH2_SFTP_S_IXOTH }

        return flag
    }

    /**
     将权限转换为三位八进制字符串表示（如 "755", "644"）
     仅保留最后 9 位权限信息（0o777）
     */
    public var mode: String {
        String(format: "%03o", rawValue & 0o777)
    }

    /**
     默认文件权限
     通常为 0644（所有者读写，组只读，其他只读）
     */
    public static let `default` = FilePermissions(
        owner: [.read, .write], group: [.read], others: [.read]
    )
}

/// 文件系统统计信息结构体 (statvfs)
/// 用于展示磁盘配额、块大小及节点可用性
public struct Statvfs: Identifiable, Equatable {
    public let id = UUID()

    /// 文件系统块大小 (Block size)
    public let bsize: UInt64
    /// 基本文件分片大小 (Fundamental fragment size)
    public let frsize: UInt64
    /// 文件系统中的总数据块数
    public let blocks: UInt64
    /// 可用数据块总数
    public let bfree: UInt64
    /// 非特权用户可用的数据块数 (可用空间)
    public let bavail: UInt64
    /// 文件系统中的总节点 (Inodes) 数
    public let files: UInt64
    /// 可用节点总数
    public let ffree: UInt64
    /// 非特权用户可用的节点数
    public let favail: UInt64
    /// 文件系统 ID
    public let fsid: UInt64
    /// 挂载标志（如只读、禁止执行等）
    public let flag: UInt64
    /// 文件名最大允许长度
    public let namemax: UInt64

    /// 使用 libssh2 原始结构体初始化
    init(statvfs: LIBSSH2_SFTP_STATVFS) {
        bsize = statvfs.f_bsize
        frsize = statvfs.f_frsize
        blocks = statvfs.f_blocks
        bfree = statvfs.f_bfree
        bavail = statvfs.f_bavail
        files = statvfs.f_files
        ffree = statvfs.f_ffree
        favail = statvfs.f_favail
        fsid = statvfs.f_fsid
        flag = statvfs.f_flag
        namemax = statvfs.f_namemax
    }

    /// 计算总容量（字节 Bytes）
    public var totalSpace: UInt64 {
        frsize * blocks
    }

    /// 计算可用空间（字节 Bytes）
    public var freeSpace: UInt64 {
        frsize * bfree
    }
}

/// 远程文件类型枚举
public enum FileType: String, CaseIterable {
    case link // 符号链接
    case regularFile // 常规文件
    case directory // 目录
    case characterSpecialFile // 字符设备文件
    case blockSpecialFile // 块设备文件
    case fifo // 命名管道 (FIFO)
    case socket // 套接字文件
    case unknown // 未知类型

    /// 根据 st_mode 位掩码初始化
    public init(rawValue: Int32) {
        switch rawValue & LIBSSH2_SFTP_S_IFMT {
        case LIBSSH2_SFTP_S_IFLNK: self = .link
        case LIBSSH2_SFTP_S_IFREG: self = .regularFile
        case LIBSSH2_SFTP_S_IFDIR: self = .directory
        case LIBSSH2_SFTP_S_IFCHR: self = .characterSpecialFile
        case LIBSSH2_SFTP_S_IFBLK: self = .blockSpecialFile
        case LIBSSH2_SFTP_S_IFIFO: self = .fifo
        case LIBSSH2_SFTP_S_IFSOCK: self = .socket
        default: self = .unknown
        }
    }

    /// 获取对应的 POSIX 宏名称字符串
    public var name: String {
        switch self {
        case .link: "S_IFLNK"
        case .regularFile: "S_IFREG"
        case .directory: "S_IFDIR"
        case .characterSpecialFile: "S_IFCHR"
        case .blockSpecialFile: "S_IFBLK"
        case .fifo: "S_IFIFO"
        case .socket: "S_IFSOCK"
        case .unknown: "S_UNKNOWN"
        }
    }

    /// 获取 Nerd Fonts 图标类名，用于 UI 显示
    public var icon: String {
        switch self {
        case .link: "nf-md-link"
        case .regularFile: "nf-md-file"
        case .directory: "nf-md-folder"
        case .characterSpecialFile: "nf-md-collage"
        case .blockSpecialFile: "nf-md-integrated_circuit_chip"
        case .fifo: "nf-md-pipe_valve"
        case .socket: "nf-md-ev_plug_type2"
        case .unknown: "nf-md-help"
        }
    }
}

/// 文件模式位 (st_mode) 的类型别名
public typealias FileMode = Int32

public extension FileMode {
    /// 获取完整的符号化权限字符串（如 "drwxr-xr-x"）
    var symbolicFull: String {
        fileTypeSymbol + symbolic
    }

    /// 获取权限部分的符号化字符串（如 "rwxr-xr-x"）
    var symbolic: String {
        let masks = [
            (LIBSSH2_SFTP_S_IRUSR, LIBSSH2_SFTP_S_IWUSR, LIBSSH2_SFTP_S_IXUSR), // 所有者
            (LIBSSH2_SFTP_S_IRGRP, LIBSSH2_SFTP_S_IWGRP, LIBSSH2_SFTP_S_IXGRP), // 属组
            (LIBSSH2_SFTP_S_IROTH, LIBSSH2_SFTP_S_IWOTH, LIBSSH2_SFTP_S_IXOTH), // 其他人
        ]
        return masks.map { modeToSymbol(mask: $0) }.joined()
    }

    /// 获取代表文件类型的单个字符符号
    var fileTypeSymbol: String {
        switch self & LIBSSH2_SFTP_S_IFMT {
        case LIBSSH2_SFTP_S_IFREG: "-"
        case LIBSSH2_SFTP_S_IFDIR: "d"
        case LIBSSH2_SFTP_S_IFLNK: "l"
        case LIBSSH2_SFTP_S_IFBLK: "b"
        case LIBSSH2_SFTP_S_IFCHR: "c"
        case LIBSSH2_SFTP_S_IFIFO: "p"
        case LIBSSH2_SFTP_S_IFSOCK: "s"
        default: "?"
        }
    }

    /// 将给定的读、写、执行掩码转换为 "rwx" 符号
    func modeToSymbol(mask: (r: Int32, w: Int32, x: Int32)) -> String {
        var result = ""
        result += (self & mask.r) != 0 ? "r" : "-"
        result += (self & mask.w) != 0 ? "w" : "-"
        result += (self & mask.x) != 0 ? "x" : "-"
        return result
    }

    /// 转换为对应的 FileType 枚举
    var fileType: FileType {
        .init(rawValue: self)
    }

    /// 转换为对应的 FilePermissions 结构体
    var permissions: FilePermissions {
        .init(rawValue: self)
    }

    /// 获取权限的八进制字符串表示（如 "755"）
    var str: String {
        String(format: "%03O", self & 0o777)
    }
}
