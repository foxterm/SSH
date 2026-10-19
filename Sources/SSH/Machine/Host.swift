// FoxTerm | Host.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 探测远程主机的操作系统平台信息（发行版 ID 与版本号）
    ///
    /// 通过读取 `/etc/*-release`、`/etc/os-release`、`/etc/lsb-release` 等文件，
    /// 兼容老式 Debian（无 os-release 时回退到 `/etc/debian_version`）。
    ///
    /// - Returns: 包含平台名称和版本号的 `HostPlatform` 模型；探测失败返回 `nil`
    func getHostPlatform() async -> HostPlatform? {
        // 关键点：
        // 1. `</dev/null` 防止 glob 无匹配且无 os-release 时 grep 挂起读 stdin
        // 2. `-h` 去掉文件名前缀，避免解析时被路径污染(值内含冒号也不会被误切)
        // 3. 老式 Debian 没有 os-release，仅在完全找不到 ID 时才用 /etc/debian_version 兜底
        //    (Ubuntu 等发行版也带 /etc/debian_version，若直接 echo 会误判平台)
        let gatherCmd =
            #"ids=$(grep -shE '^(ID|VERSION_ID|DISTRIB_ID|DISTRIB_RELEASE)=' /etc/*-release /etc/os-release /etc/lsb-release 2>/dev/null </dev/null); if [ -z "$ids" ] && [ -f /etc/debian_version ]; then echo 'ID=debian'; else printf '%s\n' "$ids"; fi"#
        guard let output = await ssh.exec(gatherCmd)?.string, !output.isEmpty else { return nil }

        let lines = output.lines.filter { !$0.isEmpty }

        var platform = ""
        var version = ""

        // 引号和空格处理集
        let trimSet = CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines)

        for line in lines {
            // 兼容个别发行版 grep 仍带文件名前缀的情况：仅在冒号前是路径时才剥离
            var content = line
            if line.hasPrefix("/"), let colon = line.firstIndex(of: ":") {
                content = String(line[line.index(after: colon)...])
            }

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

    /// 执行 `uname` 命令获取远程主机的系统标识字符串（小写）
    /// - Returns: 系统标识字符串（如 `"linux"`、`"darwin"`）；执行失败返回空字符串
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
}
