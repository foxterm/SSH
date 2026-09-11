// FoxTerm | Call.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 线程切换与回调执行的单例工具类，支持 Swift 并发（Sendable）
public final class Call: Sendable {
    /// 全局共享单例实例
    public static let shared: Call = .init()

    public init() {}
}

public extension Call {
    /// 在主线程异步执行同步闭包，并等待其返回结果
    ///
    /// 利用 `UnsafeContinuation` 将主线程 `DispatchQueue.main.async` 的异步回调转换为 `async` 异步等待
    /// - Parameter callback: 需要在主线程执行的同步闭包（须满足 `Sendable` 协议）
    /// - Returns: 闭包执行后的返回值
    func callback<T: Sendable>(_ callback: @escaping @Sendable () -> T) async -> T {
        await withUnsafeContinuation { continuation in
            DispatchQueue.main.async {
                let ret = callback()
                continuation.resume(returning: ret)
            }
        }
    }

    /// 在独立 Task 中并发执行异步闭包，并等待其返回结果
    ///
    /// - Parameter callback: 需要执行的异步闭包（须满足 `Sendable` 协议）
    /// - Returns: 闭包执行后的返回值
    func callback<T: Sendable>(_ callback: @escaping @Sendable () async -> T) async -> T {
        let task = Task {
            await callback()
        }
        return await task.value
    }

    /// 在当前线程直接同步执行闭包并返回结果
    ///
    /// - Parameter callback: 需要执行的普通同步闭包
    /// - Returns: 闭包执行后的返回值
    func callback<T>(_ callback: @escaping () -> T) -> T {
        callback()
    }
}
