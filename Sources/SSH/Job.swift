// FoxTerm | Job.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 管理任务队列的类，确保任务按顺序执行。
public class Job {
    let queue: OperationQueue

    /// 初始化一个新的 `Job` 实例，并可选地指定名称。
    /// - 参数 name：作业队列的名称，默认为 "app.foxterm.ssh.job"。
    public init(name: String = "app.foxterm.ssh.job") {
        let q = OperationQueue()
        q.name = name
        q.maxConcurrentOperationCount = 1 // 确保操作按顺序执行。
        q.qualityOfService = .userInteractive
        queue = q
    }
}

public extension Job {
    /// 将新操作添加到作业队列中。
    /// - 参数 callback：包含要执行的操作的闭包。
    func addOperation(_ callback: @escaping () -> Void) {
        queue.addOperation {
            callback()
        }
    }

    /// 取消作业队列中所有当前操作。
    func cancelAllOperations() {
        queue.cancelAllOperations()
    }
}
