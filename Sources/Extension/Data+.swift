// FoxTerm | Data+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension Data {
    /// 安全地将 Data 转为指向 Int8 的 C 字符串指针（用于兼容 OpenSSL 等 C 接口）。
    func withCPointer<R>(_ body: (UnsafePointer<Int8>?, Int) -> R) -> R {
        withUnsafeBytes { bufPtr in
            let ptr = bufPtr.baseAddress?.assumingMemoryBound(to: Int8.self)
            return body(ptr, self.count)
        }
    }

    /// 转换为 UTF-8 编码的 String。
    var string: String? {
        string(encoding: .utf8)
    }

    /// 使用指定的编码方式将 Data 转换为 String。
    /// - Parameter encoding: 字符编码格式。
    /// - Returns: 转换成功返回 String，失败返回 nil。
    func string(encoding: String.Encoding) -> String? {
        String(data: self, encoding: encoding)
    }

    /// 将 Data 转换为 Bool 值。假设 Data 包含单字节，1 表示 true，0 表示 false。
    var bool: Bool {
        guard !isEmpty else { return false }
        let bool: UInt8 = load()
        return bool == 1
    }

    /// 从 Data 中加载并解析指定整型 `T`。
    /// - Returns: 解析出的 `T` 类型数值。
    func load<T: FixedWidthInteger>() -> T {
        guard count >= MemoryLayout<T>.size else { return 0 }
        return withUnsafeBytes { ptr in
            // 使用 loadUnaligned 确保非对齐内存读取的安全，防止崩溃
            ptr.loadUnaligned(fromByteOffset: 0, as: T.self)
        }
    }

    /// 从指定的数值 `T` 创建二进制 Data。
    /// - Parameter v: 需要转换的数值。
    /// - Returns: 包含该数值内存布局的 Data 实例。
    static func from(_ v: inout some FixedWidthInteger) -> Data {
        Swift.withUnsafeBytes(of: &v) { Data($0) }
    }

    /// 从 String 创建 UTF-8 Data。
    static func from(_ value: String) -> Data {
        Data(value.utf8)
    }

    /// 从 Bool 创建 Data（1 字节：1 为 true，0 为 false）。
    static func from(_ value: Bool) -> Data {
        var bool: UInt8 = value ? 1 : 0
        return .from(&bool)
    }

    /// 检查是否为常见的图片格式。
    var isImage: Bool {
        guard count >= 12 else { return false }
        return isJPEG || isPNG || isGIF || isWebP || isBMP || isTIFF || isHEIC
    }

    /// JPEG 格式检测。
    var isJPEG: Bool {
        starts(with: [0xFF, 0xD8, 0xFF]) // JPEG 文件起始标记
    }

    /// PNG 格式检测。
    var isPNG: Bool {
        prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// GIF 格式检测（GIF87a / GIF89a）。
    var isGIF: Bool {
        prefix(6) == Data("GIF89a".utf8) || prefix(6) == Data("GIF87a".utf8)
    }

    /// WebP 格式检测。
    var isWebP: Bool {
        // 使用相对位移操作，防止二进制 Slice 导致的下标偏移越界问题
        count >= 12 && prefix(4) == Data("RIFF".utf8) && dropFirst(8).prefix(4) == Data("WEBP".utf8)
    }

    /// BMP 格式检测。
    var isBMP: Bool {
        prefix(2) == Data("BM".utf8)
    }

    /// TIFF 格式检测（支持 Little-Endian 与 Big-Endian）。
    var isTIFF: Bool {
        prefix(4) == Data([0x49, 0x49, 0x2A, 0x00])
            || prefix(4) == Data([0x4D, 0x4D, 0x00, 0x2A])
    }

    /// HEIC / HEIF 格式检测。
    var isHEIC: Bool {
        guard count >= 12 else { return false }
        // 检查偏移量 4 开始的 'ftyp' 盒
        if dropFirst(4).prefix(4) == Data("ftyp".utf8) {
            let brand = dropFirst(8).prefix(4)
            let validBrands = [
                Data("heic".utf8),
                Data("heix".utf8),
                Data("hevc".utf8),
                Data("hevx".utf8),
            ]
            return validBrands.contains(brand)
        }
        return false
    }

    /// 从指定索引开始查找目标字节的位置。
    func firstIndex(of element: UInt8, startingAt startIndex: Int) -> Int? {
        guard startIndex < count else { return nil }
        let searchIndex = index(self.startIndex, offsetBy: startIndex)
        if let idx = self[searchIndex...].firstIndex(of: element) {
            return distance(from: self.startIndex, to: idx)
        }
        return nil
    }

    /// 将每个字节转为 Hex 字符串数组（注意：大 Data 消耗较高，推荐直接使用 hexString）。
    var hex: [String] {
        map { String(format: "%02X", $0) }
    }

    /// 高性能转化为大写十六进制字符串（避免大量的中间内存分配）。
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    /// 获取数据指纹（长度大于 16 字节使用 Base64，否则使用冒号分隔的十六进制）。
    var fingerprint: String {
        count > 16 ? base64WithoutPadding : hex.joined(separator: ":")
    }

    /// 标准 Base64 字符串。
    var base64String: String {
        base64EncodedString()
    }

    /// 移除等号填充符（Padding '='）的 Base64 字符串。
    var base64WithoutPadding: String {
        base64String.replacingOccurrences(of: "=", with: "")
    }
}
