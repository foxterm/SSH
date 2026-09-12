// FoxTerm | HMAC.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import OpenSSL

public extension Crypto {
    /// 使用指定的密钥和算法计算字符串的 HMAC（基于哈希的消息认证码）。
    ///
    /// - Parameters:
    ///   - message: 需要计算 HMAC 的输入字符串。
    ///   - key: 用于哈希计算的密钥字符串。
    ///   - algorithm: 使用的 SHA 哈希算法类型（如 SHA-1、SHA-256）。
    /// - Returns: 计算得到的 HMAC 结果数据（`Data` 对象）。
    func hmac(_ message: String, key: String, algorithm: ShaAlgorithm) -> Data {
        message.withCPointer { mPtr, mCount in
            key.withCPointer { kPtr, kCount in
                hmac(mPtr, message_len: mCount, key: kPtr, key_len: kCount.int32, algorithm: algorithm)
            }
        }
    }

    /// 使用指定的密钥和算法计算二进制 Data 的 HMAC。
    ///
    /// - Parameters:
    ///   - message: 需要计算 HMAC 的输入二进制数据。
    ///   - key: 用于哈希计算的密钥二进制数据。
    ///   - algorithm: 使用的 SHA 哈希算法类型。
    /// - Returns: 计算得到的 HMAC 结果数据（`Data` 对象）。
    func hmac(_ message: Data, key: Data, algorithm: ShaAlgorithm) -> Data {
        // 获取消息和密钥的内存指针与字节长度，并传给底层指针重载函数
        message.withCPointer { mPtr, mCount in
            key.withCPointer { kPtr, kCount in
                hmac(mPtr, message_len: mCount, key: kPtr, key_len: kCount.int32, algorithm: algorithm)
            }
        }
    }

    /// 根据指定的指针和长度计算 HMAC。
    ///
    /// - Parameters:
    ///   - message: 指向待计算消息数据的内存指针。
    ///   - message_len: 消息数据的字节长度。
    ///   - key: 指向密钥数据的内存指针。
    ///   - key_len: 密钥数据的字节长度（Int32 类型以适配 OpenSSL API）。
    ///   - algorithm: 使用的 SHA 哈希算法类型。
    /// - Returns: 包含计算结果 HMAC 的 `Data` 对象。
    ///
    /// 本函数直接调用 OpenSSL 的 `HMAC()` 一步式 API 完成计算并导出字节数据。
    func hmac(
        _ message: UnsafeRawPointer?,
        message_len: Int,
        key: UnsafeRawPointer?,
        key_len: Int32,
        algorithm: ShaAlgorithm
    ) -> Data {
        let evp = algorithm.EVP
        let digest = algorithm.digest
        let buf: BufferData<Int8, UInt32> = .init(digest)

        // 调用 OpenSSL C API 计算 HMAC
        HMAC(evp, key, key_len, message, message_len, buf.buf.buffer, buf.len.buffer)

        return buf.data(count: digest)
    }
}
