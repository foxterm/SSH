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

    /// 同步将操作添加到队列中，阻塞当前调用线程直到操作完成
    /// - 参数 callback：包含要执行的操作的闭包。 
    func addSyncOperation(_ callback: @escaping () -> Void) {
        let operation = BlockOperation {
            callback()
        }
        queue.addOperations([operation], waitUntilFinished: true)
    }

    /// 获取或设置队列的暂停状态
    var isSuspended: Bool {
        get { queue.isSuspended }
        set { queue.isSuspended = newValue }
    }

    /// 获取当前队列中正在执行和等待执行的操作总数
    var operationCount: Int {
        queue.operationCount
    }

    /// 取消作业队列中所有当前操作。
    func cancelAllOperations() {
        queue.cancelAllOperations()
    }
}
