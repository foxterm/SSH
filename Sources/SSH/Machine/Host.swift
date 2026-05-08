// FoxTerm | Host.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getHostPlatform() async -> HostPlatform? {
        let gatherCmd = "grep -E '^(ID|VERSION_ID|DISTRIB_ID|DISTRIB_RELEASE)=' /etc/*-release 2>/dev/null"

        guard let output = await ssh.exec(gatherCmd)?.string, !output.isEmpty else { return nil }

        let lines = output.lines.filter { !$0.isEmpty }

        var platform = ""
        var version = ""

        // 引号和空格处理集
        let trimSet = CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines)

        for line in lines {
            // 注意：grep 会带上文件名（如 /etc/os-release:ID=ubuntu），所以要切分
            // 如果你的 grep 没带文件名，split 会处理等号后的部分
            let content = line.components(separatedBy: ":").last ?? line
            let parts = content.split(separator: "=", maxSplits: 1)

            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: trimSet)

            if key == "ID" || key == "DISTRIB_ID" {
                platform = value.lowercased()
            } else if key == "VERSION_ID" || key == "DISTRIB_RELEASE" {
                version = value
            }
        }

        guard !platform.isEmpty else { return nil }
        return .init(platform: platform, version: version)
    }

    func uname() async -> String {
        await ssh.exec("uname")?.string?.lowercased() ?? ""
    }

    /// 修复：更鲁棒的 Linux 判断逻辑
    func isLinux() async -> Bool {
        let uname = await uname()
        return uname.contains("linux")
    }

    /// 检查是否为 macOS
    func isMacOS() async -> Bool {
        let uname = await uname()
        return uname.contains("darwin")
    }

    var isWindows: Bool {
        guard let version = ssh.serverBanner?.lowercased() else {
            return false
        }
        return version.contains("windows") || version.contains("mssh")
    }
}
