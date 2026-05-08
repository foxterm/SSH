// FoxTerm | Task+.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: UInt64) async {
        try? await sleep(nanoseconds: 1_000_000_000 * seconds)
    }
}
