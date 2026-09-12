// FoxTerm | Color+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import SwiftUI

#if os(iOS)
    import UIKit
#endif

public extension Color {
    /// 判断当前颜色是否为浅色（Light Color），常用于决定文本应显示为黑色还是白色。
    var isLightColor: Bool {
        let (red, green, blue) = getRGB()
        // 使用 ITU-R BT.601 心理学感知亮度公式计算相对亮度
        let brightness = (0.299 * red + 0.587 * green + 0.114 * blue)
        // 亮度阈值（大于 0.5 视作浅色）
        let brightnessThreshold: CGFloat = 0.5
        return brightness > brightnessThreshold
    }

    /// 获取颜色的 sRGB 三原色分量（0.0 ~ 1.0）。
    /// - Returns: 包含 (red, green, blue) 的元组。
    func getRGB() -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        #if os(macOS)
            // 转换为 NSColor 后并保证转为 sRGB 色彩空间，避免崩溃
            guard let srgbColor = NSColor(self).usingColorSpace(.sRGB) else {
                return (0, 0, 0)
            }
            return (srgbColor.redComponent, srgbColor.greenComponent, srgbColor.blueComponent)
        #elseif os(iOS)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else {
                return (0, 0, 0)
            }
            return (r, g, b)
        #else
            return (0, 0, 0)
        #endif
    }

    /// 提高当前颜色的亮度。
    /// - Parameter brightnessFactor: 增加的亮度增量（例如 `0.1` 表示调亮 10%）。
    /// - Returns: 调整亮度后的新 `Color`。
    func brighter(_ brightnessFactor: CGFloat) -> Color {
        let (red, green, blue) = getRGB()
        let newRed = min(1.0, max(0.0, red + brightnessFactor))
        let newGreen = min(1.0, max(0.0, green + brightnessFactor))
        let newBlue = min(1.0, max(0.0, blue + brightnessFactor))
        return Color(red: Double(newRed), green: Double(newGreen), blue: Double(newBlue))
    }
}

#if os(macOS)
    public extension NSColor {
        /// 判断当前 `NSColor` 是否为浅色。
        var isLightColor: Bool {
            let (red, green, blue) = getRGB()
            let brightness = (0.299 * red + 0.587 * green + 0.114 * blue)
            let brightnessThreshold: CGFloat = 0.5
            return brightness > brightnessThreshold
        }

        /// 安全地获取 `NSColor` 的 RGB 三原色分量（自动转换为 sRGB 色彩空间，防止因非 RGB 色彩空间导致的运行时崩溃）。
        /// - Returns: 包含 (red, green, blue) 的元组。
        func getRGB() -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
            guard let srgbColor = usingColorSpace(.sRGB) else {
                return (0, 0, 0)
            }
            return (srgbColor.redComponent, srgbColor.greenComponent, srgbColor.blueComponent)
        }

        /// 提高当前 `NSColor` 的亮度。
        /// - Parameter brightnessFactor: 增加的亮度增量。
        /// - Returns: 调整亮度后的新 `NSColor`，并保持原始不透明度（Alpha）。
        func brighter(_ brightnessFactor: CGFloat) -> NSColor {
            let (red, green, blue) = getRGB()
            let newRed = min(1.0, max(0.0, red + brightnessFactor))
            let newGreen = min(1.0, max(0.0, green + brightnessFactor))
            let newBlue = min(1.0, max(0.0, blue + brightnessFactor))
            return NSColor(srgbRed: newRed, green: newGreen, blue: newBlue, alpha: alphaComponent)
        }
    }
#endif
