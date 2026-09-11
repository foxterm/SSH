// FoxTerm | CChar+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension UnsafePointer<CChar> {
    /// 将不可变的 `UnsafePointer<CChar>` (C 字符串指针) 转为 Swift `String`
    var string: String {
        String(cString: self)
    }
}

public extension UnsafeMutablePointer<CChar> {
    /// 将可变的 `UnsafeMutablePointer<CChar>` (C 字符串指针) 转为 Swift `String`
    var string: String {
        String(cString: self)
    }
}

public extension [CChar] {
    /// 将 `CChar` 数组 (C 字符数组) 转为 Swift `String`
    var string: String {
        String(cString: self)
    }
}
