// FoxTerm | Sha.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Extension
import Foundation
import OpenSSL

public extension Crypto {
    /// 计算指定字符串的 SHA 哈希值。
    ///
    /// - Parameters:
    ///   - message: 需要计算哈希的输入字符串。
    ///   - algorithm: 使用的 SHA 哈希算法类型。
    /// - Returns: 计算得到的哈希结果数据（`Data` 对象）。
    func sha(_ message: String, algorithm: ShaAlgorithm) -> Data {
        message.withCPointer { mPtr, mCount in
            sha(mPtr, message_len: mCount, algorithm: algorithm)
        }
    }

    /// 计算指定二进制数据的 SHA 哈希值。
    ///
    /// - Parameters:
    ///   - message: 需要计算哈希的输入 Data。
    ///   - algorithm: 使用的 SHA 哈希算法类型。
    /// - Returns: 计算得到的哈希结果数据（`Data` 对象）。
    func sha(_ message: Data, algorithm: ShaAlgorithm) -> Data {
        message.withCPointer { mPtr, mCount in
            sha(mPtr, message_len: mCount, algorithm: algorithm)
        }
    }

    /// 根据指定的指针和长度计算 SHA 哈希值。
    ///
    /// - Parameters:
    ///   - message: 指向需要计算哈希数据的原始内存指针（UnsafeRawPointer）。
    ///   - message_len: 数据在内存中的字节长度。
    ///   - algorithm: 使用的 SHA 哈希算法类型。
    /// - Returns: 计算得到的哈希结果数据（`Data` 对象）。
    ///
    /// 本函数调用 OpenSSL 底层 API 进行哈希计算：初始化摘要上下文（EVP_MD_CTX）、
    /// 注入数据（EVP_DigestUpdate）并导出计算结果（EVP_DigestFinal_ex）。
    func sha(_ message: UnsafeRawPointer?, message_len: Int, algorithm: ShaAlgorithm) -> Data {
        let evp = algorithm.EVP
        let digest = algorithm.digest
        let buf: BufferData<Int8, UInt32> = .init(digest)
        let mdctx = EVP_MD_CTX_new()

        // 初始化算法上下文
        EVP_DigestInit(mdctx, evp)
        // 写入待哈希数据
        EVP_DigestUpdate(mdctx, message, message_len)
        // 完成计算并输出摘要结果
        EVP_DigestFinal_ex(mdctx, buf.buf.buffer, buf.len.buffer)
        // 释放 OpenSSL 上下文内存，防止内存泄漏
        EVP_MD_CTX_free(mdctx)

        return buf.data(count: digest)
    }

    /// 异步计算指定路径文件的 SHA 哈希值（适用于大文件分块读取）。
    ///
    /// - Parameters:
    ///   - file: 文件的绝对路径或相对路径。
    ///   - algorithm: 使用的 SHA 哈希算法类型。
    /// - Returns: 计算得到的哈希结果数据，若文件读取失败或路径无效则返回 `nil`。
    func sha(file: String, algorithm: ShaAlgorithm) async -> Data? {
        await Call.shared.callback {
            // 以二进制只读模式打开文件
            guard let fp = Darwin.fopen(file.bytesArray, "rb") else {
                return nil
            }
            // 保证作用域结束时自动关闭文件句柄
            defer {
                Darwin.fclose(fp)
            }

            let digest = algorithm.digest
            let evp = algorithm.EVP
            let buf: BufferData<Int8, UInt32> = .init(digest)
            let buff: Buffer<CChar> = .init(0x10000) // 缓冲区大小设置为 64KB (0x10000)
            var len: Int
            let mdctx = EVP_MD_CTX_new()

            EVP_DigestInit(mdctx, evp)

            // 循环按块读取文件内容并更新哈希上下文
            while true {
                len = Darwin.fread(buff.buffer, 1, buff.count, fp)
                guard len > 0 else {
                    break
                }
                EVP_DigestUpdate(mdctx, buff.buffer, len)
            }

            // 导出计算结果
            EVP_DigestFinal_ex(mdctx, buf.buf.buffer, buf.len.buffer)
            // 释放内存
            EVP_MD_CTX_free(mdctx)

            return buf.data(count: digest)
        }
    }
}
