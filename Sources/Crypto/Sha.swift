// FoxTerm | Sha.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Extension
import Foundation
import OpenSSL

public extension Crypto {
    /// Computes the SHA hash of the given message using the specified algorithm.
    ///
    /// - Parameters:
    ///   - message: The input string to be hashed.
    ///   - algorithm: The SHA algorithm to use for hashing.
    /// - Returns: The computed hash as a `Data` object.
    func sha(_ message: String, algorithm: ShaAlgorithm) -> Data {
        sha(message.bytes, message_len: message.count, algorithm: algorithm)
    }

    /// Computes the SHA hash of the given message using the specified algorithm.
    ///
    /// - Parameters:
    ///   - message: The input data to be hashed.
    ///   - algorithm: The SHA algorithm to use for hashing.
    /// - Returns: The computed hash as a `Data` object.
    func sha(_ message: Data, algorithm: ShaAlgorithm) -> Data {
        message.withCPointer { mPtr, mCount in
            sha(mPtr, message_len: mCount, algorithm: algorithm)
        }
    }

    /// Computes the SHA hash of a given message using the specified algorithm.
    ///
    /// - Parameters:
    ///   - message: A pointer to the message data to be hashed.
    ///   - message_len: The length of the message data.
    ///   - algorithm: The SHA algorithm to use for hashing.
    ///
    /// - Returns: A `Data` object containing the computed hash.
    ///
    /// This function uses the OpenSSL library to perform the hashing. It initializes
    /// the digest context, updates it with the message data, and finalizes the digest
    /// to produce the hash. The resulting hash is returned as a `Data` object.
    func sha(_ message: UnsafeRawPointer?, message_len: Int, algorithm: ShaAlgorithm) -> Data {
        let evp = algorithm.EVP
        let digest = algorithm.digest
        let buf: BufferData<Int8, UInt32> = .init(digest)
        let mdctx = EVP_MD_CTX_new()
        EVP_DigestInit(mdctx, evp)
        EVP_DigestUpdate(mdctx, message, message_len)
        EVP_DigestFinal_ex(mdctx, buf.buf.buffer, buf.len.buffer)
        EVP_MD_CTX_free(mdctx)
        return buf.data(count: digest)
    }

    func sha(file: String, algorithm: ShaAlgorithm) async -> Data? {
        await Call.shared.callback {
            guard let fp = Darwin.fopen(file, "rb") else {
                return nil
            }
            defer {
                Darwin.fclose(fp)
            }
            let digest = algorithm.digest
            let evp = algorithm.EVP
            let buf: BufferData<Int8, UInt32> = .init(digest)
            let buff: Buffer<CChar> = .init(0x10000)
            var len: Int
            let mdctx = EVP_MD_CTX_new()
            EVP_DigestInit(mdctx, evp)
            while true {
                len = Darwin.fread(buff.buffer, 1, buff.count, fp)
                guard len > 0 else {
                    break
                }
                EVP_DigestUpdate(mdctx, buff.buffer, len)
            }
            EVP_DigestFinal_ex(mdctx, buf.buf.buffer, buf.len.buffer)
            EVP_MD_CTX_free(mdctx)
            return buf.data(count: digest)
        }
    }
}
