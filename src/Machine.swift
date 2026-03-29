// FoxTerm | Machine.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 远程主机/机器类，封装了基于 SSH 渠道的系统监控与信息采集功能
public class Machine {
    /// 容器类型（例如 Docker、Podman 等），用于在采集数据时适配不同的路径或逻辑
    public var container: ContainerType = .docker

    /// 关联的底层 SSH 通信渠道，用于执行采集命令或读取 /proc 文件
    let channel: Channel

    /// 初始化方法
    /// - Parameter channel: 已经建立连接的 SSH 渠道实例
    init(channel: Channel) {
        self.channel = channel
    }

    deinit {
        #if DEBUG
            print("♻️", "Machine 监控实例已释放")
        #endif
    }
}
