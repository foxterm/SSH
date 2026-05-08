// FoxTerm | Integer+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension FixedWidthInteger {
    /// A computed property that returns the raw byte representation of the integer.
    ///
    /// This property uses `withUnsafeBytes` to access the underlying memory of the integer and converts it into an array of `UInt8` values.
    /// The resulting array represents the integer in its binary form, which can be useful for low-level network operations, serialization, or other byte-wise manipulations.
    ///
    /// - Returns: An array of `UInt8` values representing the raw bytes of the integer.
    var bytes: [UInt8] {
        withUnsafeBytes(of: self) { Array($0) }
    }

    /// A computed property that returns the memory address of the current instance as an `UnsafeRawPointer`.
    ///
    /// This property uses the `withUnsafePointer(to:)` function to obtain a pointer to the current instance,
    /// and then converts it to an `UnsafeRawPointer`.
    ///
    /// - Returns: An `UnsafeRawPointer` pointing to the memory address of the current instance.
    var address: UnsafeRawPointer {
        withUnsafePointer(to: self) {
            UnsafeRawPointer($0)
        }
    }

    var int32: Int32 {
        Int32(self)
    }

    var uint32: UInt32 {
        UInt32(self)
    }

    var int: Int {
        Int(self)
    }

    var uint: UInt {
        UInt(self)
    }

    var uint8: UInt8 {
        UInt8(self)
    }

    var uint16: UInt16 {
        UInt16(self)
    }

    var int64: Int64 {
        Int64(self)
    }

    var uint64: UInt64 {
        UInt64(self)
    }
}

public extension Int64 {
    var formatNetworkSpeed: String {
        let units = ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]
        var speed = Double(self)
        var unitIndex = 0

        while speed >= 1000, unitIndex < units.count - 1 {
            speed /= 1000
            unitIndex += 1
        }
        return String(format: "%.1f %@", speed, units[unitIndex])
    }

    var byteFormatterBinary: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .binary)
    }

    var byteFormatterFile: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }

    var byteFormatterMemory: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .memory)
    }

    var byteFormatterDecimal: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .decimal)
    }
    
}
