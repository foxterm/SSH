// FoxTerm | Call.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public final class Call: Sendable {
    public static let shared: Call = .init()

    public init() {}
}

public extension Call {
    func callback<T: Sendable>(_ callback: @escaping @Sendable () -> T) async -> T {
        await withUnsafeContinuation { continuation in
            DispatchQueue.main.async {
                let ret = callback()
                continuation.resume(returning: ret)
            }
        }
    }

    func callback<T: Sendable>(_ callback: @escaping @Sendable () async -> T) async -> T {
        let task = Task {
            await callback()
        }
        return await task.value
    }

    func callback<T>(_ callback: @escaping () -> T) -> T {
        callback()
    }
}
