// FoxTerm | Types.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Foundation

///// SSH 主机密钥类型
///// 映射 libssh2 中的主机密钥算法标识
// public enum HostkeyType: String, CaseIterable {
//    case unknown, rsa, dss, ecdsa_256, ecdsa_384, ecdsa_521, ed25519
//
//    /// 使用 libssh2 的原始 Int32 标识进行初始化
//    public init(rawValue: Int32) {
//        switch rawValue {
//        case LIBSSH2_HOSTKEY_TYPE_RSA: self = .rsa
//        case LIBSSH2_HOSTKEY_TYPE_DSS: self = .dss
//        case LIBSSH2_HOSTKEY_TYPE_ECDSA_256: self = .ecdsa_256
//        case LIBSSH2_HOSTKEY_TYPE_ECDSA_384: self = .ecdsa_384
//        case LIBSSH2_HOSTKEY_TYPE_ECDSA_521: self = .ecdsa_521
//        case LIBSSH2_HOSTKEY_TYPE_ED25519: self = .ed25519
//        default: self = .unknown
//        }
//    }
// }
//
///// SSH 主机密钥结构体
///// 用于在握手阶段存储服务器发来的原始密钥及其算法类型
// public struct Hostkey {
//    /// 原始密钥二进制数据
//    public let data: Data
//    /// 密钥算法类型
//    public let type: HostkeyType
// }

/// 主机密钥指纹哈希算法
public enum HostkeyHash: String, CaseIterable {
    case md5, sha1, sha256

    /// 映射 libssh2 内部的哈希类型标识
    var value: Int32 {
        switch self {
        case .md5: LIBSSH2_HOSTKEY_HASH_MD5
        case .sha1: LIBSSH2_HOSTKEY_HASH_SHA1
        case .sha256: LIBSSH2_HOSTKEY_HASH_SHA256
        }
    }

    /// 哈希结果的字节长度（MD5: 16, SHA1: 20, SHA256: 32）
    var length: Int {
        switch self {
        case .md5: 16
        case .sha1: 20
        case .sha256: 32
        }
    }

    public func string() -> String {
        String(describing: self).uppercased()
    }
}

/// SSH 会话方法类型
/// 用于在会话初始化阶段配置或获取具体的交换、加密、压缩等算法
public enum SessionMethodType: String, CaseIterable {
    case kex // 密钥交换
    case hostkey // 主机密钥
    case crypt_cs // 加密 (客户端 -> 服务端)
    case crypt_sc // 加密 (服务端 -> 客户端)
    case mac_cs // 消息认证码 (客户端 -> 服务端)
    case mac_sc // 消息认证码 (服务端 -> 客户端)
    case comp_cs // 压缩 (客户端 -> 服务端)
    case comp_sc // 压缩 (服务端 -> 客户端)
    // case lang_cs // 语言 (客户端 -> 服务端)
    // case lang_sc // 语言 (服务端 -> 客户端)
    // case sign_algo0 // 签名算法

    /// 映射 libssh2 内部的方法类型标识
    var value: Int32 {
        switch self {
        case .kex: LIBSSH2_METHOD_KEX
        case .hostkey: LIBSSH2_METHOD_HOSTKEY
        case .crypt_cs: LIBSSH2_METHOD_CRYPT_CS
        case .crypt_sc: LIBSSH2_METHOD_CRYPT_SC
        case .mac_cs: LIBSSH2_METHOD_MAC_CS
        case .mac_sc: LIBSSH2_METHOD_MAC_SC
        case .comp_cs: LIBSSH2_METHOD_COMP_CS
        case .comp_sc: LIBSSH2_METHOD_COMP_SC
//        case .lang_cs: LIBSSH2_METHOD_LANG_CS
//        case .lang_sc: LIBSSH2_METHOD_LANG_SC
            // case .sign_algo0: LIBSSH2_METHOD_SIGN_ALGO
        }
    }
}

/// SSH 身份验证类型
public enum AuthType: String, CaseIterable {
    case none, password, publickey, keyboard

    /// 对应的可读名称
    public var name: String {
        switch self {
        case .none: "None"
        case .password: "Password"
        case .publickey: "Public Key"
        case .keyboard: "Keyboard Interactive"
        }
    }
}

/// 数据流类型标识
/// 用于区分标准输出、标准错误以及 SFTP 专用流
public enum StreamType: String, CaseIterable {
    case stdout, stderr, sftp

    /// 映射 libssh2 渠道读取时的 stream_id
    var value: Int32 {
        switch self {
        case .stdout: 0 // 渠道标准流
        case .stderr: 1 // 渠道扩展流（标准错误）
        case .sftp: -1 // SFTP 逻辑流标识
        }
    }
}

/// Socket 关闭方向控制（半关闭）
public enum Shout: Int32, CustomStringConvertible {
    case read = 0
    case write = 1
    case readWrite = 2

    public var description: String {
        switch self {
        case .read: "Read Only"
        case .write: "Write Only"
        case .readWrite: "Read and Write"
        }
    }
}

public enum ContainerType: String, CaseIterable {
    case docker, podman

    public var command: String {
        rawValue
    }
}

public struct HostKeySupport {
    /// 安全且推荐使用的算法列表（已按权重排序）
    public let supported: [String]
    /// 存在安全风险/已被弃用的算法列表（如 ssh-rsa, ssh-dss，已按权重排序）
    public let insecure: [String]
}
