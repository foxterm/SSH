// FoxTerm | Algorithm.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import OpenSSL

/// 表示支持的摘要/哈希（Digest/Hash）算法的枚举。
/// 遵循 `String` 原始值协议和 `CaseIterable` 可遍历协议。
public enum ShaAlgorithm: String, CaseIterable {
    case md5, sha1, sha256, sha512, md5_sha1, sha224, sha384, sha512_224, sha512_256, sha3_224, sha3_256, sha3_384, sha3_512

    /// 获取对应算法在 OpenSSL 中对应的 EVP_MD 摘要算法指针。
    public var EVP: OpaquePointer? {
        switch self {
        case .md5:
            EVP_md5()
        case .md5_sha1:
            EVP_md5_sha1()
        case .sha1:
            EVP_sha1()
        case .sha224:
            EVP_sha224()
        case .sha256:
            EVP_sha256()
        case .sha384:
            EVP_sha384()
        case .sha512:
            EVP_sha512()
        case .sha512_224:
            EVP_sha512_224()
        case .sha512_256:
            EVP_sha512_256()
        case .sha3_224:
            EVP_sha3_224()
        case .sha3_256:
            EVP_sha3_256()
        case .sha3_384:
            EVP_sha3_384()
        case .sha3_512:
            EVP_sha3_512()
        }
    }

    /// 获取当前算法计算出的哈希摘要字节长度（例如 SHA256 返回 32）。
    public var digest: Int {
        guard let evp = EVP else { return 0 }
        return Int(EVP_MD_get_size(evp))
    }

    /// 获取 OpenSSL 中注册的算法标准名称（例如 "SHA2-256"）。
    public var name: String {
        guard let evp = EVP, let cName = EVP_MD_get0_name(evp) else {
            return rawValue.uppercased()
        }
        return cName.string
    }

    /// 获取 OpenSSL 中该算法的详细文本描述。
    public var description: String {
        guard let evp = EVP, let cDesc = EVP_MD_get0_description(evp) else {
            return name
        }
        return cDesc.string
    }
}
