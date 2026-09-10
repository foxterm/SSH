// FoxTerm | Bytes.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public final class Bytes {
    public static let shared = Bytes()

    // 二进制单位（IEC 60027 标准）
    public static let KiB: Int64 = 1 << 10
    public static let MiB: Int64 = 1 << 20
    public static let GiB: Int64 = 1 << 30
    public static let TiB: Int64 = 1 << 40
    public static let PiB: Int64 = 1 << 50
    public static let EiB: Int64 = 1 << 60

    // 十进制单位（SI 国际单位制）
    public static let KB: Int64 = 1000
    public static let MB: Int64 = 1_000_000
    public static let GB: Int64 = 1_000_000_000
    public static let TB: Int64 = 1_000_000_000_000
    public static let PB: Int64 = 1_000_000_000_000_000
    public static let EB: Int64 = 1_000_000_000_000_000_000

    public static var defaultBinary = true

    // 正则表达式匹配模式
    private static let patternBinary = try? NSRegularExpression(pattern: "^(-?\\d+(?:\\.\\d+)?)\\s?([KMGTPE]iB?)$", options: .caseInsensitive)
    private static let patternDecimal = try? NSRegularExpression(pattern: "^(-?\\d+(?:\\.\\d+)?)\\s?([KMGTPE]B?|B?)$", options: .caseInsensitive)

    public init() {}

    // MARK: - 格式化方法

    /// 将字节整数格式化为易读的字符串（默认遵循 IEC 60027 二进制标准）。
    /// 例如：`31323` 字节将返回 `"30.59KiB"`。
    public func format(_ value: Int64) -> String {
        formatBinary(value)
    }

    /// 将字节整数格式化为遵循 IEC 60027 标准的二进制单位字符串。
    /// 例如：`31323` 字节将返回 `"30.59KiB"`。
    public func formatBinary(_ value: Int64) -> String {
        var multiple = ""
        var val = Double(value)

        switch value {
        case Bytes.EiB...:
            val /= Double(Bytes.EiB)
            multiple = "EiB"
        case Bytes.PiB...:
            val /= Double(Bytes.PiB)
            multiple = "PiB"
        case Bytes.TiB...:
            val /= Double(Bytes.TiB)
            multiple = "TiB"
        case Bytes.GiB...:
            val /= Double(Bytes.GiB)
            multiple = "GiB"
        case Bytes.MiB...:
            val /= Double(Bytes.MiB)
            multiple = "MiB"
        case Bytes.KiB...:
            val /= Double(Bytes.KiB)
            multiple = "KiB"
        case 0:
            return "0"
        default:
            return "\(value)B"
        }

        return String(format: "%.2f%@", val, multiple)
    }

    /// 将字节整数格式化为遵循 SI 国际单位制的十进制单位字符串。
    /// 例如：`31323` 字节将返回 `"31.32KB"`。
    public func formatDecimal(_ value: Int64) -> String {
        var multiple = ""
        var val = Double(value)

        switch value {
        case Bytes.EB...:
            val /= Double(Bytes.EB)
            multiple = "EB"
        case Bytes.PB...:
            val /= Double(Bytes.PB)
            multiple = "PB"
        case Bytes.TB...:
            val /= Double(Bytes.TB)
            multiple = "TB"
        case Bytes.GB...:
            val /= Double(Bytes.GB)
            multiple = "GB"
        case Bytes.MB...:
            val /= Double(Bytes.MB)
            multiple = "MB"
        case Bytes.KB...:
            val /= Double(Bytes.KB)
            multiple = "KB"
        case 0:
            return "0"
        default:
            return "\(value)B"
        }

        return String(format: "%.2f%@", val, multiple)
    }

    // MARK: - 解析方法

    /// 解析易读的容量字符串并转换为字节整数。
    /// 支持二进制与十进制表示法（优先解析二进制）。
    /// 例如：`"6GiB"` (或 `"6Gi"`) 返回 `6442450944`，`"6GB"` (或 `"6G"`) 返回 `6000000000`。
    public func parse(_ value: String) throws -> Int64 {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = try? parseBinary(trimmed) {
            return result
        }
        return try parseDecimal(trimmed)
    }

    /// 解析二进制格式的容量字符串（IEC 60027 标准）并转换为字节整数。
    /// 例如：`"6GiB"` (或 `"6Gi"`) 将返回 `6442450944`。
    public func parseBinary(_ value: String) throws -> Int64 {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = Bytes.patternBinary,
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
              match.numberOfRanges >= 3,
              let numRange = Range(match.range(at: 1), in: trimmed),
              let unitRange = Range(match.range(at: 2), in: trimmed),
              let bytesValue = Double(trimmed[numRange])
        else {
            throw NSError(domain: "BytesError", code: 1, userInfo: [NSLocalizedDescriptionKey: "解析数值失败: value=\(value)"])
        }

        let unit = trimmed[unitRange].uppercased()

        switch unit {
        case "KI", "KIB": return Int64(bytesValue * Double(Bytes.KiB))
        case "MI", "MIB": return Int64(bytesValue * Double(Bytes.MiB))
        case "GI", "GIB": return Int64(bytesValue * Double(Bytes.GiB))
        case "TI", "TIB": return Int64(bytesValue * Double(Bytes.TiB))
        case "PI", "PIB": return Int64(bytesValue * Double(Bytes.PiB))
        case "EI", "EIB": return Int64(bytesValue * Double(Bytes.EiB))
        default: return Int64(bytesValue)
        }
    }

    /// 解析十进制格式的容量字符串（SI 标准）并转换为字节整数。
    /// 例如：`"6GB"` (或 `"6G"`) 将返回 `6000000000`。
    public func parseDecimal(_ value: String) throws -> Int64 {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = Bytes.patternDecimal,
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
              match.numberOfRanges >= 3,
              let numRange = Range(match.range(at: 1), in: trimmed),
              let unitRange = Range(match.range(at: 2), in: trimmed),
              let bytesValue = Double(trimmed[numRange])
        else {
            throw NSError(domain: "BytesError", code: 1, userInfo: [NSLocalizedDescriptionKey: "解析数值失败: value=\(value)"])
        }

        let unit = trimmed[unitRange].uppercased()

        switch unit {
        case "K", "KB": return Int64(bytesValue * Double(Bytes.KB))
        case "M", "MB": return Int64(bytesValue * Double(Bytes.MB))
        case "G", "GB": return Int64(bytesValue * Double(Bytes.GB))
        case "T", "TB": return Int64(bytesValue * Double(Bytes.TB))
        case "P", "PB": return Int64(bytesValue * Double(Bytes.PB))
        case "E", "EB": return Int64(bytesValue * Double(Bytes.EB))
        default: return Int64(bytesValue)
        }
    }

    // MARK: - 静态全局便捷封装

    /// 便捷静态方法：使用默认规则（二进制）格式化字节数。
    public static func format(_ value: Int64) -> String {
        shared.format(value)
    }

    /// 便捷静态方法：使用二进制标准格式化字节数。
    public static func formatBinary(_ value: Int64) -> String {
        shared.formatBinary(value)
    }

    /// 便捷静态方法：使用十进制标准格式化字节数。
    public static func formatDecimal(_ value: Int64) -> String {
        shared.formatDecimal(value)
    }

    /// 便捷静态方法：解析容量字符串。
    public static func parse(_ value: String) throws -> Int64 {
        try shared.parse(value)
    }

    public static func formatBytes(_ value: Int64) -> String {
        defaultBinary ? formatBinary(value) : formatDecimal(value)
    }
}
