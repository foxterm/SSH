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

    var int16: Int16 {
        Int16(self)
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

    var double: Double {
        Double(self)
    }

    var formatNetworkSpeed: String {
        Bytes.formatRate(int64)
    }

    var formatBinary: String {
        Bytes.formatBinary(int64)
    }

    var byteFormatterDecimal: String {
        Bytes.formatDecimal(int64)
    }

    var formatBytes: String {
        Bytes.formatBytes(int64)
    }
}
