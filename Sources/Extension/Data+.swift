// FoxTerm | Data+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension Data {
    func withCPointer<R>(_ body: (UnsafePointer<Int8>, Int) -> R) -> R {
        return withUnsafeBytes { bufPtr in
            let ptr = bufPtr.baseAddress!.assumingMemoryBound(to: Int8.self)
            return body(ptr, self.count)
        }
    }

    /// Converts the Data to a UTF-8 encoded String.
    var string: String? {
        string(encoding: .utf8)
    }

    /// Converts the Data to a String using the specified encoding.
    /// - Parameter encoding: The string encoding to use.
    /// - Returns: A String if the conversion is successful, otherwise nil.
    func string(encoding: String.Encoding) -> String? {
        String(data: self, encoding: encoding)
    }

    /// Converts the Data to a Bool. Assumes the Data contains a single byte where 1 represents true and 0 represents false.
    var bool: Bool {
        let bool: UInt8 = load()
        return bool == 1
    }

    /// Loads a value of type T from the Data.
    /// - Returns: A value of type T.
    func load<T: FixedWidthInteger>() -> T {
        withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: T.self)
        }
    }

    /// Creates a Data instance from a value of type T.
    /// - Parameter v: The value to convert to Data.
    /// - Returns: A Data instance containing the value.
    static func from<T: FixedWidthInteger>(_ v: inout T) -> Data {
        Data(bytes: &v, count: MemoryLayout<T>.size)
    }

    /// Creates a Data instance from a String.
    /// - Parameter value: The String to convert to Data.
    /// - Returns: A Data instance containing the UTF-8 encoded string.
    static func from(_ value: String) -> Data {
        Data(value.utf8)
    }

    /// Creates a Data instance from a Bool.
    /// - Parameter value: The Bool to convert to Data.
    /// - Returns: A Data instance containing a single byte where 1 represents true and 0 represents false.
    static func from(_ value: Bool) -> Data {
        var bool: UInt8 = value ? 1 : 0
        return .from(&bool)
    }

    /// 检查是否为常见的图片格式
    var isImage: Bool {
        guard count >= 12 else { return false }
        switch self {
        case _ where isJPEG:
            return true
        case _ where isPNG:
            return true
        case _ where isGIF:
            return true
        case _ where isWebP:
            return true
        case _ where isBMP:
            return true
        case _ where isTIFF:
            return true
        case _ where isHEIC:
            return true
        default:
            return false
        }
    }

    /// 常见图片格式检测
    var isJPEG: Bool {
        starts(with: [0xFF, 0xD8, 0xFF]) // JPEG/JFIF 文件起始标记
    }

    var isPNG: Bool {
        // PNG 固定的 8 字节签名
        prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    var isGIF: Bool {
        // GIF87a 或 GIF89a
        prefix(6) == Data("GIF89a".utf8) || prefix(6) == Data("GIF87a".utf8)
    }

    var isWebP: Bool {
        // 'RIFF' 后跟 'WEBP'
        count >= 12 && prefix(4) == Data("RIFF".utf8) && self[8 ... 11] == Data("WEBP".utf8)
    }

    var isBMP: Bool {
        // 'BM' 标记
        prefix(2) == Data("BM".utf8)
    }

    var isTIFF: Bool {
        // 支持小端序(II)和大端序(MM)
        prefix(4) == Data([0x49, 0x49, 0x2A, 0x00]) // II*
            || prefix(4) == Data([0x4D, 0x4D, 0x00, 0x2A]) // MM*
    }

    var isHEIC: Bool {
        // HEIF/HEIC 使用 'ftyp' 盒
        guard count >= 12 else { return false }

        // 检查是否有 'ftyp' 盒 (偏移量4字节开始)
        if self[4 ... 7] == Data("ftyp".utf8) {
            // 检查 HEIC 子类型
            let brands = [
                Data("heic".utf8), // HEVC 图像
                Data("heix".utf8), // 10-bit 图像
                Data("hevc".utf8), // HEVC 视频
                Data("hevx".utf8), // 10-bit 视频
            ]
            // 子类型从偏移量8字节开始
            return brands.contains { brand in
                self[8 ... 11] == brand
            }
        }
        return false
    }

    func firstIndex(of element: UInt8, startingAt startIndex: Int) -> Int? {
        for i in startIndex ..< count {
            if self[i] == element {
                return i
            }
        }
        return nil
    }

    var hex: [String] {
        map { String(format: "%02hhX", $0) }
    }

    var hexString: String {
        hex.joined()
    }

    var fingerprint: String {
        count > 16 ? base64WithoutPadding : hex.joined(separator: ":")
    }

    var base64String: String {
        base64EncodedString()
    }

    var base64WithoutPadding: String {
        base64String.replacingOccurrences(of: "=", with: "")
    }
}
