// FoxTerm | Color+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import SwiftUI

public extension Color {
    var isLightColor: Bool {
        let (red, green, blue) = getRGB()
        let brightness = (0.299 * red + 0.587 * green + 0.114 * blue)
        // 亮度阈值，可以根据需要调整
        let brightnessThreshold = 0.5
        // 判断亮度是否大于阈值
        return brightness > brightnessThreshold
    }

    func getRGB() -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let cgColor else { return (0, 0, 0) }

        let components = cgColor.components

        guard let red = components?[0],
              let green = components?[1],
              let blue = components?[2]
        else {
            return (0, 0, 0)
        }

        return (red, green, blue)
    }

    func brighter(_ brightnessFactor: CGFloat) -> Color {
        let (red, green, blue) = getRGB()
        let newRed = min(1.0, max(0.0, red + brightnessFactor))
        let newGreen = min(1.0, max(0.0, green + brightnessFactor))
        let newBlue = min(1.0, max(0.0, blue + brightnessFactor))
        return Color(red: newRed, green: newGreen, blue: newBlue)
    }
}

#if os(macOS)
    public extension NSColor {
        var isLightColor: Bool {
            let (red, green, blue) = getRGB()
            let brightness = (0.299 * red + 0.587 * green + 0.114 * blue)
            // 亮度阈值，可以根据需要调整
            let brightnessThreshold = 0.5
            // 判断亮度是否大于阈值
            return brightness > brightnessThreshold
        }

        func getRGB() -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
            let red = redComponent
            let green = greenComponent
            let blue = blueComponent
            return (red, green, blue)
        }

        func brighter(_ brightnessFactor: CGFloat) -> NSColor {
            let red = redComponent
            let green = greenComponent
            let blue = blueComponent
            let newRed = min(1.0, max(0.0, red + brightnessFactor))
            let newGreen = min(1.0, max(0.0, green + brightnessFactor))
            let newBlue = min(1.0, max(0.0, blue + brightnessFactor))
            return NSColor(red: newRed, green: newGreen, blue: newBlue, alpha: alphaComponent)
        }
    }
#endif
