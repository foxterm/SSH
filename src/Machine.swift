// FoxTerm | Machine.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

/// 远程主机/机器类，封装了基于 SSH 渠道的系统监控与信息采集功能
public class Machine {
    /// 容器类型（例如 Docker、Podman 等），用于在采集数据时适配不同的路径或逻辑
    public var container: ContainerType = .docker

    let ssh: SSH

    init(ssh: SSH) {
        self.ssh = ssh
    }

    deinit {
        #if DEBUG
            print("♻️", "Machine 监控实例已释放")
        #endif
    }
}
