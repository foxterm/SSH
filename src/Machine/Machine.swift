// FoxTerm | Machine.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 远程主机/机器类，封装了基于 SSH 渠道的系统监控与信息采集功能
///
/// 线程安全说明：`Machine` 是普通 class（非 actor），其可变属性（`container`、`gpu` 等）
/// 未做并发保护。调用方应确保在单一 Task 或串行上下文中使用，避免多线程并发读写。
public class Machine {
    /// 容器引擎类型（Docker 或 Podman），通过 `initDocker()` 自动探测
    public var container: ContainerType = .docker

    /// 已探测到的 GPU 类型（nil 表示无 GPU 或尚未探测）
    public internal(set) var gpu: GPU?
    /// GPU 管理工具的完整路径（如 `/usr/bin/nvidia-smi`）
    public internal(set) var smibin: String = ""

    /// 是否已完成 GPU 探测（避免无 GPU 的机器每轮轮询都重复执行 `which` 造成网络往返）
    var gpuProbeDone = false

    /// 底层 SSH 连接实例
    let ssh: SSH

    /// 通过 SSH 连接实例创建 Machine 监控对象
    init(ssh: SSH) {
        self.ssh = ssh
    }

    deinit {
        #if DEBUG
            print("♻️", "Machine 监控实例已释放")
        #endif
    }
}
