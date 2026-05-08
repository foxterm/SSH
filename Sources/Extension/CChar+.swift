// FoxTerm | CChar+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension UnsafePointer<CChar> {
    /// Converts an `UnsafePointer<CChar>` to a `String`.
    var string: String {
        String(cString: self)
    }
}

public extension UnsafeMutablePointer<CChar> {
    /// Converts an `UnsafeMutablePointer<CChar>` to a `String`.
    var string: String {
        String(cString: self)
    }
}

public extension [CChar] {
    /// Converts an array of `CChar` to a `String`.
    var string: String {
        String(cString: self)
    }
}
