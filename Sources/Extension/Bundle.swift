// FoxTerm | Bundle.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension Bundle {
    static var appName: String {
        let info = Bundle.main.infoDictionary
        if let displayName = info?["CFBundleDisplayName"] as? String {
            return displayName
        }
        if let bundleName = info?[kCFBundleNameKey as String] as? String {
            return bundleName
        }
        return ""
    }

    static var currentAppVersion: String {
        #if os(macOS)
            let infoDictionaryKey = "CFBundleShortVersionString"
        #else
            let infoDictionaryKey = "CFBundleVersion"
        #endif
        return Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String ?? ""
    }
}
