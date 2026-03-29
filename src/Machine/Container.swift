// FoxTerm | Container.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension Machine {
    /// 获取所有容器的列表及基本状态
    /// - Returns: 容器状态数组，失败返回 nil
    func getDockerStat() async -> [DockerStat]? {
        let format = "\"{{.ID}}|{{.Image}}|{{.Names}}|{{.Status}}|{{.CreatedAt}}|{{.Ports}}\""
        guard
            let data = await ssh.channel.exec([
                container.command, "ps", "-a", "--no-trunc", "--format", format,
            ]),
            let text = data.string
        else { return nil }

        return parseDockerOutput(text, count: 4).map { cols in
            DockerStat(
                containerID: cols[0],
                name: cols[2].components(separatedBy: ",").first ?? "",
                image: cols[1],
                status: cols[3],
                running: cols[3].lowercased().contains("up"),
                createdAt: cols.indices.contains(4) ? cols[4] : "",
                ports: cols.indices.contains(5) ? cols[5] : ""
            )
        }
    }

    /// 删除指定容器
    /// - Parameters:
    ///   - id: 容器 ID 或名称
    ///   - force: 是否强制删除 (相当于 -f)
    func dockerRemove(_ id: String, force: Bool = false) async -> Bool {
        var cmd = [container.command, "rm"]
        if force { cmd.append("-f") }
        cmd.append(id)
        return await ssh.channel.exec(cmd) != nil
    }

    /// 启动容器
    func dockerStart(_ id: String) async -> Bool {
        await ssh.channel.exec([container.command, "start", id]) != nil
    }

    /// 停止容器
    func dockerStop(_ id: String) async -> Bool {
        await ssh.channel.exec([container.command, "stop", id]) != nil
    }

    /// 重启容器
    func dockerRestart(_ id: String) async -> Bool {
        await ssh.channel.exec([container.command, "restart", id]) != nil
    }

    /// 获取容器详细配置信息 (JSON 格式)
    func dockerInspect(_ id: String) async -> String? {
        guard let data = await ssh.channel.exec([container.command, "inspect", id]) else {
            return nil
        }
        return data.string?.trim
    }

    /// 获取容器终端日志
    /// - Parameters:
    ///   - id: 容器 ID
    ///   - tail: 获取最后的行数，默认 1000
    func dockerLogs(_ id: String, tail: Int = 1000) async -> String? {
        let cmd = [container.command, "logs", "--tail", "\(tail)", id]
        return await ssh.channel.exec(cmd)?.string?.trim
    }

    /// 清理所有处于停止状态的容器
    func dockerPrune() async -> Bool {
        await ssh.channel.exec([container.command, "container", "prune", "-f"]) != nil
    }

    /// 获取容器实时资源占用情况 (CPU、内存、网络 IO 等)
    func getDockerStats() async -> [DockerStats]? {
        let format = "\"{{.ID}}|{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}\""
        guard
            let data = await ssh.channel.exec(
                [container.command, "stats", "--no-trunc", "--no-stream", "--format", format]
            ),
            let text = data.string
        else { return nil }

        return parseDockerOutput(text, count: 6).map { cols in
            DockerStats(
                containerID: cols[0],
                name: cols[1].components(separatedBy: ",").first ?? "",
                CPUPerc: cols[2],
                memPerc: cols[3],
                netIO: cols[4],
                blockIO: cols[5]
            )
        }
    }

    /// 解析 Docker 命令行输出的工具函数
    /// - Parameters:
    ///   - text: 待解析的字符串
    ///   - count: 期望的最小列数
    private func parseDockerOutput(_ text: String, count: Int) -> [[String]] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t")) }
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: "|") }
            .filter { $0.count >= count }
    }
}
