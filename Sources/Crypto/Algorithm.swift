// FoxTerm | Algorithm.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import OpenSSL

/// An enumeration representing the SHA (Secure Hash Algorithm) algorithms.
/// Conforms to `String` and `CaseIterable` protocols.
public enum ShaAlgorithm: String, CaseIterable {
    case md5, sha1, sha256, sha512, md5_sha1, sha224, sha384, sha512_224, sha512_256, sha3_224, sha3_256, sha3_384, sha3_512

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

    public var digest: Int {
        Int(EVP_MD_get_size(EVP))
    }

    public var name: String {
        EVP_MD_get0_name(EVP).string
    }

    public var description: String {
        EVP_MD_get0_description(EVP).string
    }
}
