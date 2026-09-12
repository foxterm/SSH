// FoxTerm | String+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Foundation
import SwiftUI

public extension String {
    /// 安全获取字符串的 UTF-8 字节 Data 表示（Swift 原生内存管理，无泄露）
    var bytesData: Data {
        Data(utf8)
    }

    /// 安全获取字符串的 UInt8 字节数组（无泄露）
    var bytesArray: [UInt8] {
        Array(utf8)
    }

    /// 将字符串拷贝为 C 语言风格的 UnsafeMutablePointer<CChar> 字符串指针。
    ///
    /// - Warning: **注意内存安全**！该属性内部使用了 `strdup` 动态分配 C 堆内存，
    ///   调用方**必须**在使用完成后手动调用 `free(pointer)` 释放内存，否则会导致严重的内存泄漏！
    ///
    /// ```swift
    /// let ptr = "hello".bytes
    /// defer { free(ptr) } // 必须在使用完后释放
    /// openSSL_function(ptr)
    /// ```
    var bytes: UnsafeMutablePointer<CChar> {
        Darwin.strdup(self)
    }

    /// 【推荐的 C 指针使用方式】在闭包作用域内安全地使用 C 字符串指针，系统会自动管理内存，绝不泄漏。
    ///
    /// ```swift
    /// "hello".withCStringPointer { ptr in
    ///     openSSL_function(ptr)
    /// }
    /// ```
    func withCStringPointer<R>(_ body: (UnsafePointer<CChar>) throws -> R) rethrows -> R {
        try withCString { cStringPtr in
            try body(cStringPtr)
        }
    }

    #if os(iOS) || os(macOS)
        /// 将当前字符串复制到系统的全局剪贴板中。
        ///
        /// ```swift
        /// "SomeText".copyToPasteboard() // 复制 "SomeText" 到剪贴板
        /// ```
        func copyToPasteboard() {
            #if os(iOS)
                UIPasteboard.general.string = self
            #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self, forType: .string)
            #endif
        }
    #endif

    /// 将字符串转换为布尔值（支持 "true"/"false"、"yes"/"no"、"1"/"0"）。
    var bool: Bool {
        let selfLowercased = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch selfLowercased {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return false
        }
    }

    /// 获取文件的扩展名（支持 `.tar.gz` 等双重后缀扩展名）。
    var `extension`: String {
        let string = self
        // 匹配常见的双重归档文件后缀
        if string.hasSuffix(".tar.gz") {
            return "tar.gz"
        }
        if string.hasSuffix(".tar.bz") {
            return "tar.bz"
        }
        if string.hasSuffix(".tar.bz2") {
            return "tar.bz2"
        }
        if string.hasSuffix(".tar.xz") {
            return "tar.xz"
        }

        // 处理普通扩展名
        if let dot = string.lastIndex(of: ".") {
            let foo = string.index(after: dot)
            return String(string[foo...])
        } else {
            return ""
        }
    }

    // 注意：已移除原先会导致严重内存泄漏的 strdup 属性 bytes。
    // 如果需要 C 指针，应通过 withCString 或 utf8 视图处理，不建议暴露会分配未释放内存的属性。

    /// 返回字符串 UTF-8 编码的字节长度（修正：重命名属性以避免覆盖 Swift 标准库 `String.count`）。
    var utf8Count: Int {
        utf8.count
    }

    /// 清除字符串首尾的空白字符和换行符。
    var trim: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 若字符串前后均被双引号包裹，则去除首尾的双引号。
    var trimQuotes: String {
        if count >= 2, first == "\"", last == "\"" {
            return String(dropFirst().dropLast())
        }
        return self
    }

    /// 将字符串按换行符拆分为数组，并自动去除每行的首尾空格。
    var lines: [String] {
        components(separatedBy: .newlines).map(\.trim)
    }

    /// 若字符串不包含指定前缀，则在头部追加该前缀。
    ///
    /// - Parameter prefix: 期望包含的前缀字符串。
    /// - Returns: 追加前缀后的字符串或原字符串。
    func withPrefix(_ prefix: String) -> String {
        guard !hasPrefix(prefix) else { return self }
        return prefix + self
    }

    /// 拼接路径组件（封装 NSString 路径方法）。
    func appendingPathComponent(_ str: String) -> String {
        (self as NSString).appendingPathComponent(str)
    }

    /// 删除最后一个路径组件。
    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }

    /// 获取最后一个路径组件。
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }

    /// 将字符串按空白字符切分为词组数组（过滤空字符串）。
    var fields: [String] {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    /// 安全整型范围下标访问（闭区间）。
    subscript(bounds: CountableClosedRange<Int>) -> String {
        let lower = max(0, bounds.lowerBound)
        let upper = min(count - 1, bounds.upperBound)
        guard lower <= upper, lower < count else { return "" }

        let start = index(startIndex, offsetBy: lower)
        let end = index(startIndex, offsetBy: upper)
        return String(self[start ... end])
    }

    /// 安全整型范围下标访问（半开区间）。
    subscript(bounds: CountableRange<Int>) -> String {
        let lower = max(0, bounds.lowerBound)
        let upper = min(count, bounds.upperBound)
        guard lower < upper, lower < count else { return "" }

        let start = index(startIndex, offsetBy: lower)
        let end = index(startIndex, offsetBy: upper)
        return String(self[start ..< end])
    }

    /// 转换为 Int32 可选值。
    var int32: Int32? {
        Int32(self)
    }

    /// 转换为 Int 可选值。
    var int: Int? {
        Int(self)
    }

    /// 配合 Hex 构造 SwiftUI `Color` 的计算属性（需实现 Color(hex:) 构造函数）。
    var swiftColor: Color {
        get {
            Color(hex: self)
        }
        set {
            self = newValue.hexString
        }
    }

    #if os(macOS)
        /// 配合 Hex 构造 macOS `NSColor` 的计算属性。
        var nsColor: NSColor {
            get {
                NSColor(hex: self)
            }
            set {
                self = newValue.hexString
            }
        }
    #endif

    /// 移除字符串指定的头部前缀。
    ///
    /// - Parameter prefix: 待移除的前缀。
    /// - Returns: 移除前缀后的结果。
    func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }

    /// 移除字符串指定的尾部后缀。
    ///
    /// - Parameter suffix: 待移除的后缀。
    /// - Returns: 移除后缀后的结果。
    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}
