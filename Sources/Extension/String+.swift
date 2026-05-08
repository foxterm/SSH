// FoxTerm | String+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Darwin
import Foundation
import SwiftUI

public extension String {
    #if os(iOS) || os(macOS)
        /// SwifterSwift: Copy string to global pasteboard.
        ///
        ///        "SomeText".copyToPasteboard() // copies "SomeText" to pasteboard
        ///
        func copyToPasteboard() {
            #if os(iOS)
                UIPasteboard.general.string = self
            #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self, forType: .string)
            #endif
        }
    #endif

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

    var `extension`: String {
        let string = self
        // FIXME: efficiency
        switch true {
        case string.hasSuffix(".tar.gz"):
            return "tar.gz"
        case string.hasSuffix(".tar.bz"):
            return "tar.bz"
        case string.hasSuffix(".tar.bz2"):
            return "tar.bz2"
        case string.hasSuffix(".tar.xz"):
            return "tar.xz"
        default:
            if let dot = string.lastIndex(of: ".") {
                let foo = string.index(after: dot)
                return String(string[foo...])
            } else {
                return ""
            }
        }
    }

    var bytes: UnsafeMutablePointer<CChar> {
        Darwin.strdup(self)
    }

    /// Returns the number of UTF-8 encoded bytes in the String.
    var count: Int {
        utf8.count
    }

    /// Trims whitespace and newline characters from both ends of the String.
    var trim: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimQuotes: String {
        if count >= 2, first == "\"", last == "\"" {
            return String(dropFirst().dropLast())
        }
        return self
    }

    /// Splits the String into an array of substrings at each newline character.
    var lines: [String] {
        components(separatedBy: .newlines).map(\.trim)
    }

    /// Adds a specified prefix to the current string if it doesn't already have that prefix.
    ///
    /// - Parameter prefix: The prefix to add to the string.
    /// - Returns: A new string with the prefix added, or the original string if it already starts with the prefix.
    ///
    /// This function checks whether the current string starts with the specified prefix. If it does, the original string is returned
    /// unchanged. Otherwise, the prefix is concatenated with the current string, and the resulting string is returned.
    func withPrefix(_ prefix: String) -> String {
        guard !hasPrefix(prefix) else { return self }
        return prefix + self
    }

    func appendingPathComponent(_ str: String) -> String {
        (self as NSString).appendingPathComponent(str)
    }

    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }

    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }

    var fields: [String] {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    subscript(bounds: CountableClosedRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start ... end])
    }

    subscript(bounds: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start ..< end])
    }

    var int32: Int32? {
        Int32(self)
    }

    var int: Int? {
        Int(self)
    }

    var swiftColor: Color {
        get {
            Color(hex: self)
        }
        set {
            self = newValue.hexString
        }
    }

    #if os(macOS)
        /// The `NSColor` of ``color``
        var nsColor: NSColor {
            get {
                NSColor(hex: self)
            }
            set {
                self = newValue.hexString
            }
        }

    #endif
}
