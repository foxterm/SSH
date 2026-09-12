// FoxTerm | OutputStream+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension OutputStream {
    /// 获取已写入到内存输出流（Memory Output Stream）中的数据。
    ///
    /// - Returns: 包含已写入数据的 `Data` 对象；若该流不是内存流或未写入任何内容，则返回 `nil`。
    /// - Note: 本属性仅适用于通过 `OutputStream.toMemory()` 创建的内存流实例。
    var data: Data? {
        // 从流属性中读取内存写入的数据并转为 Data
        guard let data = property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            return nil
        }
        return data
    }
}
