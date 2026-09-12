// FoxTerm | Random.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import OpenSSL

public extension Crypto {
    /// 生成指定字节长度的密码学安全随机数据（Raw Random Bytes）。
    ///
    /// - Parameter length: 要生成的随机数据字节长度，默认为 32 字节。
    /// - Returns: 生成的随机二进制 Data；若 OpenSSL 伪随机数生成器未准备就绪或失败，则返回 nil。
    func generateRandomBytes(length: Int = 32) -> Data? {
        // 使用 UInt8 替代 CChar，确保无符号二进制数据的正确表示与类型安全
        let buff: Buffer<UInt8> = .init(length)

        // RAND_bytes 是 OpenSSL 提供的强密码学随机数生成函数，成功时返回 1
        guard RAND_bytes(buff.buffer, Int32(buff.count)) == 1 else {
            return nil
        }

        // 导出生成的随机字节 Data
        return buff.data(length)
    }
}
