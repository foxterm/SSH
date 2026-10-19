// FoxTerm | Types.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh

// MARK: - 身份认证类型

/// SSH 身份验证类型
public enum AuthType: String, CaseIterable {
    case none
    case password
    case publickey
    case keyboard
    // case gssapi

    /// 对应的可读显示名称
    public var name: String {
        switch self {
        case .none: "None"
        case .password: "Password"
        case .publickey: "Public Key"
        case .keyboard: "Keyboard Interactive"
//        case .gssapi: "GSSAPI"
        }
    }
}

// MARK: - 公钥指纹算法

/// 主机密钥指纹哈希算法
public enum HostkeyHash: String, CaseIterable {
    case md5
    case sha1
    case sha256

    /// 对应的 libssh C API 映射枚举值
    var value: ssh_publickey_hash_type {
        switch self {
        case .md5: SSH_PUBLICKEY_HASH_MD5
        case .sha1: SSH_PUBLICKEY_HASH_SHA1
        case .sha256: SSH_PUBLICKEY_HASH_SHA256
        }
    }

    /// 哈希算法的大写名称标识(如 "SHA256")
    public func string() -> String {
        String(describing: self).uppercased()
    }
}

// MARK: - 套接字关闭类型

/// POSIX Socket Shutdown 操作类型
public enum Shout: Sendable {
    /// 仅关闭读取通道 (SHUT_RD)
    case r
    /// 仅关闭写入通道 (SHUT_WR)
    case w
    /// 同时关闭读取与写入通道 (SHUT_RDWR)
    case rw

    /// 映射对应的 POSIX shutdown 常量
    var raw: Int32 {
        switch self {
        case .r:
            SHUT_RD
        case .w:
            SHUT_WR
        case .rw:
            SHUT_RDWR
        }
    }
}

// MARK: - 主机密钥算法支持度

/// 服务端与客户端支持的主机密钥算法汇总信息
public struct HostKeySupport {
    /// 安全且推荐使用的算法列表(已按优先级排序)
    public let supported: [String]
    /// 存在安全风险/已被弃用的算法列表(如 ssh-rsa, ssh-dss)
    public let insecure: [String]
}

// MARK: - 主机元数据模型

/// 当前 SSH 连接的主机结构化信息模型
public struct HostInfo {
    /// 远程套接字地址字符串(例如 "192.168.1.1:22")
    public let remoteAddr: String
    /// 远程主机 IP 地址
    public let remoteIP: String
    /// 本地绑定的套接字地址字符串
    public let localAddr: String
    /// 服务端返回的 SSH Banner
    public let serverBanner: String
    /// 客户端发送的 SSH Banner
    public let clientbanner: String
    /// 导出的服务端公钥文本
    public let publickey: String
    /// 服务端公钥生成的指纹列表
    public let fingerprints: [String]
}

/// 远程压缩/解压操作支持的文件格式
public enum ArchiveFormat: String, Sendable, CaseIterable {
    case tarGz = "tar.gz"
    case tarBz2 = "tar.bz2"
    case tarXz = "tar.xz"
    case tar
    case zip
    case sevenZip = "7z"

    /// 根据文件名或路径智能推断扩展名(支持双重后缀)
    public static func infer(from path: String) -> ArchiveFormat? {
        let lower = path.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            return .tarGz
        }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz2") {
            return .tarBz2
        }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") {
            return .tarXz
        }
        if lower.hasSuffix(".tar") {
            return .tar
        }
        if lower.hasSuffix(".zip") {
            return .zip
        }
        if lower.hasSuffix(".7z") {
            return .sevenZip
        }
        return nil
    }
}
