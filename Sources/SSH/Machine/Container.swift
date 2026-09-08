// FoxTerm | Container.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

// MARK: - Machine 容器扩展

public extension Machine {
    // MARK: - 环境检测与初始化

    /// 初始化容器引擎环境
    ///
    /// 自动检测宿主机上可用的容器工具（优先检测 `docker`，其次检测 `podman`），
    /// 并将检测结果同步更新至 `container` 属性。
    ///
    /// - Returns: 检测并设置成功返回 `true`；若两者均未安装或路径异常则返回 `false`
    func initDocker() async -> Bool {
        guard
            let bin = await ssh.exec("which docker || which podman")?.string?.trim,
            !bin.isEmpty
        else {
            return false
        }

        if bin.hasSuffix("docker") {
            container = .docker
        } else if bin.hasSuffix("podman") {
            container = .podman
        } else {
            return false
        }
        return true
    }

    // MARK: - 容器列表与实时监控

    /// 获取所有容器的列表及基本状态
    ///
    /// 通过命令行执行 JSON 格式化输出，并将其解码为结构化 DTO 数组。
    ///
    /// - Returns: 包含所有容器状态的 `DockerPSOutputDTO` 数组；解析失败或 SSH 执行异常时返回 `nil`
    func getDockerStat() async -> [DockerPSOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([
                container.command, "ps", "-a", "--no-trunc", "--format", format,
            ]),
            let text = data.string
        else { return nil }

        let decoder = JSONDecoder()
        var results: [DockerPSOutputDTO] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            if let dto = try? decoder.decode(DockerPSOutputDTO.self, from: lineData) {
                results.append(dto)
            }
        }
        return results
    }

    /// 获取容器实时资源占用快照
    ///
    /// 获取当前运行中容器的 CPU、内存、网络 IO 和磁盘 Block IO 占用情况（单次采样，不阻塞流）。
    ///
    /// - Returns: 包含实时监控数据的 `DockerStatsOutputDTO` 数组；失败返回 `nil`
    func getDockerStats() async -> [DockerStatsOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([
                container.command, "stats", "--no-trunc", "--no-stream", "--format", format,
            ]),
            let text = data.string
        else { return nil }

        let decoder = JSONDecoder()
        var results: [DockerStatsOutputDTO] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            if let dto = try? decoder.decode(DockerStatsOutputDTO.self, from: lineData) {
                results.append(dto)
            }
        }
        return results
    }

    // MARK: - 容器生命周期管理

    /// 启动指定的容器
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 操作成功返回 `true`
    func dockerStart(_ id: String) async -> Bool {
        await ssh.exec([container.command, "start", id]) != nil
    }

    /// 停止指定的容器
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 操作成功返回 `true`
    func dockerStop(_ id: String) async -> Bool {
        await ssh.exec([container.command, "stop", id]) != nil
    }

    /// 重启指定的容器
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 操作成功返回 `true`
    func dockerRestart(_ id: String) async -> Bool {
        await ssh.exec([container.command, "restart", id]) != nil
    }

    /// 暂停指定的容器内所有进程
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 操作成功返回 `true`
    func dockerPause(_ id: String) async -> Bool {
        await ssh.exec([container.command, "pause", id]) != nil
    }

    /// 恢复指定的容器内已暂停的进程
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 操作成功返回 `true`
    func dockerUnpause(_ id: String) async -> Bool {
        await ssh.exec([container.command, "unpause", id]) != nil
    }

    /// 强制终止（Kill）指定的容器
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 操作成功返回 `true`
    func dockerKill(_ id: String) async -> Bool {
        await ssh.exec([container.command, "kill", id]) != nil
    }

    /// 删除指定的容器
    /// - Parameters:
    ///   - id: 容器 ID 或容器名称
    ///   - force: 是否强制删除 (相当于追加 `-f` 参数)
    /// - Returns: 删除成功返回 `true`
    func dockerRemove(_ id: String, force: Bool = false) async -> Bool {
        var cmd = [container.command, "rm"]
        if force {
            cmd.append("-f")
        }
        cmd.append(id)
        return await ssh.exec(cmd) != nil
    }

    /// 清理所有处于停止（Exited）状态的容器
    /// - Returns: 清理成功返回 `true`
    func dockerPrune() async -> Bool {
        await ssh.exec([container.command, "container", "prune", "-f"]) != nil
    }

    // MARK: - 运维诊断与日志

    /// 获取容器的详细 JSON 元数据配置 (Inspect)
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 原始 JSON 格式字符串；执行失败返回 `nil`
    func dockerInspect(_ id: String) async -> String? {
        guard let data = await ssh.exec([container.command, "inspect", id]) else { return nil }
        return data.string?.trim
    }

    /// 获取容器终端输出日志
    /// - Parameters:
    ///   - id: 容器 ID 或容器名称
    ///   - tail: 获取最新的日志行数，默认 1000 行
    /// - Returns: 日志文本内容；执行失败返回 `nil`
    func dockerLogs(_ id: String, tail: Int = 1000) async -> String? {
        let cmd = [container.command, "logs", "--tail", "\(tail)", id]
        return await ssh.exec(cmd)?.string?.trim
    }

    /// 查看容器内运行的进程列表 (Top)
    /// - Parameter id: 容器 ID 或容器名称
    /// - Returns: 进程列表打印文本；执行失败返回 `nil`
    func dockerTop(_ id: String) async -> String? {
        await ssh.exec([container.command, "top", id])?.string?.trim
    }

    // MARK: - 文件传输与交互指令

    /// 在容器与宿主机之间复制文件/目录 (CP)
    /// - Parameters:
    ///   - source: 源路径 (如: `container_id:/path/in/container` 或 `/path/on/host`)
    ///   - destination: 目标路径 (如: `/path/on/host` 或 `container_id:/path/in/container`)
    /// - Returns: 复制成功返回 `true`
    func dockerCopy(from source: String, to destination: String) async -> Bool {
        await ssh.exec([container.command, "cp", source, destination]) != nil
    }

    /// 构建进入容器交互式终端 (Exec) 的 Shell 命令字符串
    /// - Parameters:
    ///   - id: 容器 ID 或容器名称
    ///   - shell: 容器内部使用的 Shell 环境，默认为 `/bin/sh`
    /// - Returns: 可直接交付 SSH 终端执行的命令行字符串 (如: `docker exec -it <id> /bin/sh`)
    func buildExecCommand(id: String, shell: String = "/bin/sh") -> String {
        "\(container.command) exec -it \(id) \(shell)"
    }

    // MARK: - 镜像管理

    /// 获取宿主机本地镜像列表
    /// - Returns: 包含镜像信息的 `DockerImageOutputDTO` 数组；失败返回 `nil`
    func getDockerImages() async -> [DockerImageOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([container.command, "images", "--format", format]),
            let text = data.string
        else { return nil }

        let decoder = JSONDecoder()
        var results: [DockerImageOutputDTO] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            if let dto = try? decoder.decode(DockerImageOutputDTO.self, from: lineData) {
                results.append(dto)
            }
        }
        return results
    }

    /// 删除指定的本地镜像
    /// - Parameters:
    ///   - imageID: 镜像 ID 或镜像名称:TAG
    ///   - force: 是否强制删除 (相当于追加 `-f` 参数)
    /// - Returns: 删除成功返回 `true`
    func dockerRemoveImage(_ imageID: String, force: Bool = false) async -> Bool {
        var cmd = [container.command, "rmi"]
        if force {
            cmd.append("-f")
        }
        cmd.append(imageID)
        return await ssh.exec(cmd) != nil
    }

    /// 清理宿主机上未使用的镜像
    /// - Parameter all: 若为 `true`，不仅清理悬空（dangling）镜像，还将清理所有未被现有容器占用的镜像 (`-a`)
    /// - Returns: 清理成功返回 `true`
    func dockerImagePrune(all: Bool = false) async -> Bool {
        var cmd = [container.command, "image", "prune", "-f"]
        if all {
            cmd.append("-a")
        }
        return await ssh.exec(cmd) != nil
    }

    // MARK: - Docker / Podman Compose 支持

    /// 在指定工作目录下执行 Docker Compose 子命令
    /// - Parameters:
    ///   - workingDir: 包含 `docker-compose.yml` 的远程工作目录
    ///   - subCommand: Compose 子命令参数数组 (例如: `["up", "-d"]`, `["down"]`, `["ps"]`)
    /// - Note: 根据环境自动切换 `docker compose` 与 `podman-compose`
    /// - Returns: 命令执行成功返回 `true`
    func dockerCompose(workingDir: String, subCommand: [String]) async -> Bool {
        let cdCmd = "cd \(workingDir)"
        let composeBin = (container == .podman) ? "podman-compose" : "docker compose"
        let fullCmd = "\(cdCmd) && \(composeBin) \(subCommand.joined(separator: " "))"

        return await ssh.exec(fullCmd) != nil
    }
}
