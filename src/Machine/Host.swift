// FoxTerm | Host.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension Machine {
    func getHostPlatform() async -> HostPlatform? {
        // 脚本逻辑：只读取 ID 和 VERSION_ID，并利用 sed 去掉所有双引号
        let gatherCmd = """
        grep -E '^(ID|VERSION_ID)=' /etc/os-release 2>/dev/null | sed 's/"//g'
        """

        guard let lines = await channel.exec(gatherCmd)?.string?.lines else { return nil }

        var platform = ""
        var version = ""

        for line in lines {
            let field = line.components(separatedBy: "=")
            guard field.count == 2 else { continue }

            let key = field[0].trimmingCharacters(in: .whitespaces)
            let value = field[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "ID":
                platform = value
            case "VERSION_ID":
                version = value
            default: break
            }
        }

        guard !platform.isEmpty, !version.isEmpty else { return nil }
        return .init(platform: platform, version: version)
    }

    /// 检查远程主机是否为 Linux 系统
    /// 逻辑依据：若能成功解析到 Linux 标准的 release 文件则判定为 Linux
    func isLinux() async -> Bool {
        await getHostPlatform() != nil
    }

    /// 检查远程主机是否为 Windows 系统
    /// 逻辑依据：通过 SSH 握手时服务器返回的 Banner 字符串进行特征匹配
    /// 例如：SSH-2.0-OpenSSH_for_Windows_8.1
    var isWindows: Bool {
        channel.ssh.serverbanner?.lowercased().contains("windows") ?? false
    }
}
