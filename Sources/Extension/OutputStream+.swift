// FoxTerm | OutputStream+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension OutputStream {
    /// Retrieves the data written to a memory stream.
    var data: Data? {
        guard let data = property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            return nil
        }
        return data
    }
}
