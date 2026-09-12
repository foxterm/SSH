// FoxTerm | Color+HEX.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import SwiftUI

#if os(iOS)
    import UIKit
#endif

public extension Color {
    /// 从 Hex 十六进制字符串构造 `Color`。支持 `#RGB`、`#RRGGBB`、`#AARRGGBB` 或 `#RRGGBBAA` 格式。
    /// - Parameters:
    ///   - hex: 颜色 HEX 字符串（例如：`"#1D2E3F"` 或 `"FFF"`）。
    ///   - alpha: 强制指定的透明度（0.0 ~ 1.0），若不指定则自动解析字符串中的透明度。
    init(hex: String, alpha: Double? = nil) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        let finalAlpha = alpha ?? (Double(a) / 255.0)
        self.init(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: finalAlpha)
    }

    /// 从数值（例如：`0x1D2E3F`）构造 `Color`。
    /// - Parameters:
    ///   - hex: HEX 格式的整数。
    ///   - alpha: 不透明度（0.0 ~ 1.0）。
    init(hex: Int, alpha: Double = 1.0) {
        let red = (hex >> 16) & 0xFF
        let green = (hex >> 8) & 0xFF
        let blue = hex & 0xFF
        self.init(.sRGB, red: Double(red) / 255.0, green: Double(green) / 255.0, blue: Double(blue) / 255.0, opacity: alpha)
    }

    /// 获取 `Color` 的 Hex 整数值（例如：`0x112233`）。
    var hex: Int {
        #if os(macOS)
            guard let convertedColor = NSColor(self).usingColorSpace(.sRGB) else { return 0 }
            let red = lround(Double(convertedColor.redComponent) * 255.0) << 16
            let green = lround(Double(convertedColor.greenComponent) * 255.0) << 8
            let blue = lround(Double(convertedColor.blueComponent) * 255.0)
            return red | green | blue
        #elseif os(iOS)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
            let r = lround(Double(red) * 255.0) << 16
            let g = lround(Double(green) * 255.0) << 8
            let b = lround(Double(blue) * 255.0)
            return r | g | b
        #else
            return 0
        #endif
    }

    /// 获取 `Color` 的 Hex 格式字符串（例如：`"#112233"`）。
    var hexString: String {
        String(format: "#%06X", hex)
    }

    #if os(macOS)
        /// 获取当前颜色的不透明度 Alpha 通道值（0.0 - 1.0）。
        var alphaComponent: Double {
            NSColor(self).alphaComponent
        }
    #endif
}

#if os(macOS)
    public extension NSColor {
        /// 从 Hex 字符串构造 `NSColor`。
        convenience init(hex: String, alpha: Double = 1.0) {
            let cleanHex = hex.trimmingCharacters(in: .alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: cleanHex).scanHexInt64(&int)
            self.init(hex: Int(int), alpha: alpha)
        }

        /// 从整型 Hex 构造 `NSColor`。
        convenience init(hex: Int, alpha: Double = 1.0) {
            let red = (hex >> 16) & 0xFF
            let green = (hex >> 8) & 0xFF
            let blue = hex & 0xFF
            self.init(srgbRed: Double(red) / 255.0, green: Double(green) / 255.0, blue: Double(blue) / 255.0, alpha: alpha)
        }

        /// 获取 `NSColor` 的 Hex 整数表示（先强制转至 sRGB 色彩空间，防止灰度空间导致的数组越界崩溃）。
        var hex: Int {
            guard let srgbColor = usingColorSpace(.sRGB) else { return 0 }
            let red = lround(Double(srgbColor.redComponent) * 255.0) << 16
            let green = lround(Double(srgbColor.greenComponent) * 255.0) << 8
            let blue = lround(Double(srgbColor.blueComponent) * 255.0)
            return red | green | blue
        }

        /// 获取 `NSColor` 的 Hex 格式字符串（例如：`"#112233"`）。
        var hexString: String {
            String(format: "#%06X", hex)
        }
    }
#endif
