// FoxTerm | Random.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import OpenSSL

public extension Crypto {
    func generateRandomHex(length: Int = 32) -> Data? {
        let buff: Buffer<CChar> = .init(length)
        guard RAND_bytes(buff.buffer, Int32(buff.count)) == 1 else {
            return nil
        }
        return buff.data(length)
    }
}
