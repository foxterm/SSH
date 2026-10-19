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
    /// 检查宿主机上是否存在容器运行环境(自动检测并优先选择 `docker`，其次回退至 `podman`)，
    /// 并在检测成功后更新当前实例的 `container` 属性。
    ///
    /// - Returns: 若成功找到有效的容器二进制文件并设置成功则返回 `true`，否则返回 `false`。
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

    /// 获取所有容器的完整状态列表
    ///
    /// 执行命令提取当前宿主机上的所有容器(包含已停止的容器)，并解析为结构化的 DTO 数组。
    ///
    /// - Returns: 包含所有容器元数据的 `DockerPSOutputDTO` 数组；如果 SSH 执行失败或数据解析异常则返回 `nil`。
    func getDockerStat() async -> [DockerPSOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([
                container.command, "ps", "-a", "--no-trunc", "--format", format,
            ]),
            let text = data.string
        else { return nil }

        return parseJSONLines(text, type: DockerPSOutputDTO.self)
    }

    /// 获取当前运行中容器的单次资源消耗快照
    ///
    /// 采集各运行中容器的 CPU 使用率、内存量、网络收发总量及磁盘 I/O 读写量。
    ///
    /// - Returns: 包含当前所有运行中容器指标的 `DockerStatsOutputDTO` 数组；失败返回 `nil`。
    func getDockerStats() async -> [DockerStatsOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([
                container.command, "stats", "--no-trunc", "--no-stream", "--format", format,
            ]),
            let text = data.string
        else { return nil }

        return parseJSONLines(text, type: DockerStatsOutputDTO.self)
    }

    // MARK: - 容器生命周期管理

    /// 启动指定的容器
    /// - Parameter id: 容器的 ID 或名称
    /// - Returns: 命令是否执行成功
    func dockerStart(_ id: String) async -> Bool {
        await ssh.exec([container.command, "start", id])
    }

    /// 停止容器
    /// - Parameters:
    ///   - id: 容器 ID 或名称
    ///   - force: 是否强制停止 (设置为 true 会立刻 KILL 容器，不等待正常退出)
    ///   - timeout: 正常停止的等待超时时间(秒)，默认不传则使用 docker 默认的 10 秒
    /// - Returns: 是否执行成功
    func dockerStop(_ id: String, force: Bool = false, timeout: Int? = nil) async -> Bool {
        var command = [container.command, "stop"]

        if force {
            // 强制停止：等待 0 秒直接 Kill
            command.append(contentsOf: ["-t", "0"])
        } else if let timeout {
            command.append(contentsOf: ["-t", "\(timeout)"])
        }

        command.append(id)
        return await ssh.exec(command)
    }

    /// 重启指定的容器
    /// - Parameter id: 容器的 ID 或名称
    /// - Returns: 命令是否执行成功
    func dockerRestart(_ id: String) async -> Bool {
        await ssh.exec([container.command, "restart", id])
    }

    /// 暂停指定的容器内所有进程
    /// - Parameter id: 容器的 ID 或名称
    /// - Returns: 命令是否执行成功
    func dockerPause(_ id: String) async -> Bool {
        await ssh.exec([container.command, "pause", id])
    }

    /// 恢复指定的容器内已被暂停的进程
    /// - Parameter id: 容器的 ID 或名称
    /// - Returns: 命令是否执行成功
    func dockerUnpause(_ id: String) async -> Bool {
        await ssh.exec([container.command, "unpause", id])
    }

    /// 强制终止 (SIGKILL) 指定的容器
    /// - Parameter id: 容器的 ID 或名称
    /// - Returns: 命令是否执行成功
    func dockerKill(_ id: String) async -> Bool {
        await ssh.exec([container.command, "kill", id])
    }

    /// 删除指定的容器
    /// - Parameters:
    ///   - id: 容器的 ID 或名称
    ///   - force: 是否强制删除正在运行的容器(使用 `-f` 标识)
    /// - Returns: 命令是否执行成功
    func dockerRemove(_ id: String, force: Bool = false) async -> Bool {
        var cmd = [container.command, "rm"]
        if force {
            cmd.append("-f")
        }
        cmd.append(id)
        return await ssh.exec(cmd)
    }

    /// 清理宿主机上所有处于停止状态的容器 (`docker container prune -f`)
    /// - Returns: 命令是否执行成功
    func dockerPrune() async -> Bool {
        await ssh.exec([container.command, "container", "prune", "-f"])
    }

    // MARK: - 运维诊断与日志

    /// 获取容器的详细底层结构与配置 JSON 文本 (Inspect)
    /// - Parameter id: 容器的 ID 或名称
    /// - Returns: 返回解析后的原始 JSON 文本字符串；执行失败时返回 `nil`
    func dockerInspect(_ id: String) async -> String? {
        guard let data = await ssh.exec([container.command, "inspect", id]) else { return nil }
        return data.string?.trim
    }

    /// 读取容器的终端标准输出日志
    /// - Parameters:
    ///   - id: 容器的 ID 或名称
    ///   - tail: 读取日志的末尾行数，默认为 1000 行
    ///   - timestamps: 是否在日志中包含 ISO 时间戳
    /// - Returns: 日志文本内容字符串；失败返回 `nil`
    func dockerLogs(_ id: String, tail: Int = 1000, timestamps: Bool = true) async -> (String, String)? {
        var cmdList = [container.command, "logs", "--follow=false", "--tail", "\(tail)"]
        if timestamps {
            cmdList.append("-t")
        }
        cmdList.append(id)

        let command = cmdList.joined(separator: " ")
        let (stdoutData, stderrData) = await ssh.exec(command)

        var stdoutText = ""
        var stderrText = ""
        if let stdoutData, let stdoutStr = String(data: stdoutData, encoding: .utf8), !stdoutStr.isEmpty {
            stdoutText += stdoutStr
        }
        if let stderrData, let stderrStr = String(data: stderrData, encoding: .utf8), !stderrStr.isEmpty {
            stderrText += stderrStr
        }
        return (stdoutText, stderrText)
    }

    /// 查看容器内部正在运行的进程列表 (Top)
    /// - Parameter id: 容器的 ID 或名称
    /// - Returns: 进程信息文本输出；失败返回 `nil`
    func dockerTop(_ id: String) async -> String? {
        await ssh.exec([container.command, "top", id])?.string?.trim
    }

    // MARK: - 文件传输与交互指令

    /// 在容器与宿主机之间复制文件或目录 (CP)
    /// - Parameters:
    ///   - source: 源路径 (例如 "container_id:/app/log.txt" 或宿主机路径 "/tmp/file.txt")
    ///   - destination: 目标路径 (例如 "/tmp/log.txt" 或 "container_id:/app/")
    /// - Returns: 命令是否执行成功
    func dockerCopy(from source: String, to destination: String) async -> Bool {
        await ssh.exec([container.command, "cp", source, destination])
    }

    /// 生成用于终端连接容器 Shell 环境的 Bash/SSH 执行字符串
    /// - Parameters:
    ///   - id: 容器的 ID 或名称
    ///   - shell: 容器内部使用的 Shell 解释器路径 (默认 `/bin/sh`)
    /// - Returns: 构造好的完整的命令字符串 (例如 `"docker exec -it my-app /bin/sh"`)
    func buildExecCommand(id: String, shell: String = "/bin/sh") -> String {
        "\(container.command) exec -it \(id) \(shell)"
    }

    // MARK: - 镜像管理

    /// 获取宿主机本地存储的所有镜像列表
    /// - Returns: 包含镜像元数据的 `DockerImageOutputDTO` 数组；失败返回 `nil`
    func getDockerImages() async -> [DockerImageOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([container.command, "images", "--format", format]),
            let text = data.string
        else { return nil }

        return parseJSONLines(text, type: DockerImageOutputDTO.self)
    }

    /// 获取带有关联容器使用数量的镜像列表
    /// - Returns: 包含镜像元数据及使用该镜像的容器计数的 `DockerImageItem` 数组
    func getDockerImagesWithContainerCount() async -> [DockerImageItem]? {
        // 1. 并发获取镜像列表和所有容器列表 (-a)
        async let imagesTask = getDockerImages()
        async let psTask = getDockerStat()

        guard let images = await imagesTask else { return nil }
        let containers = await (psTask) ?? []

        // 2. 构建容器所使用镜像的计数映射表
        // 注意：docker ps 中的 Image 字段可能是 "repository:tag" 或 "sha256:xxx" 或短 ID
        var imageUsageMap: [String: Int] = [:]

        for container in containers {
            // 假定 DockerPSOutputDTO 中有 image 字段(如 "nginx:latest" 或 "a1b2c3d4e5f6")
            let imageRef = container.image
            imageUsageMap[imageRef, default: 0] += 1
        }

        // 3. 匹配并构造 DockerImageItem 数组
        return images.map { image in
            // 支持通过 "repository:tag"、"fullName" 或 "imageID" 匹配
            let countByFullName = imageUsageMap[image.fullName] ?? 0
            let countByID = imageUsageMap[image.imageID] ?? 0
            let totalCount = max(countByFullName, countByID)

            return DockerImageItem(dto: image, containerCount: totalCount)
        }
    }

    /// 从远程 Docker Registry 拉取指定镜像
    /// - Parameter imageName: 完整的镜像名称(例如 `"nginx:latest"` 或 `"redis:7-alpine"`)
    /// - Returns: 拉取命令是否成功执行
    func dockerPullImage(_ imageName: String) async -> Bool {
        await ssh.exec([container.command, "pull", imageName])
    }

    /// 从远程 Docker Registry 拉取指定镜像，并将拉取进度日志通过回调实时输出
    /// - Parameters:
    ///   - imageName: 完整的镜像名称(例如 `"nginx:latest"` 或 `"redis:7-alpine"`)
    ///   - onLog: 实时标准输出日志回调 (stdout)
    ///   - onError: 实时标准错误日志回调 (stderr)
    /// - Returns: 拉取命令是否成功执行
    func dockerPullImage(_ imageName: String, onLog: ((String) -> Void)? = nil, onError: ((String) -> Void)? = nil) async -> Bool {
        await execWithLog([container.command, "pull", imageName].joined(separator: " "), onLog: onLog, onError: onError)
    }

    /// 删除指定的本地镜像
    /// - Parameters:
    ///   - imageID: 镜像 ID 或完整镜像名称
    ///   - force: 是否强制删除关联的镜像
    /// - Returns: 命令是否成功执行
    func dockerRemoveImage(_ imageID: String, force: Bool = false) async -> Bool {
        var cmd = [container.command, "rmi"]
        if force {
            cmd.append("-f")
        }
        cmd.append(imageID)
        return await ssh.exec(cmd)
    }

    /// 清理宿主机上悬空 (Dangling) 或未使用的镜像
    /// - Parameter all: 若为 `true`，将清理所有没有容器使用的镜像，而不仅仅是悬空镜像
    /// - Returns: 清理命令是否成功执行
    func dockerImagePrune(all: Bool = false) async -> Bool {
        var cmd = [container.command, "image", "prune", "-f"]
        if all {
            cmd.append("-a")
        }
        return await ssh.exec(cmd)
    }

    // MARK: - Compose 项目部署与生命周期管理

    /// Compose 调用的基础可执行命令名 (根据容器引擎自动选择 `docker compose` 或 `podman-compose`)
    private var composeExecutable: String {
        container == .podman ? "podman-compose" : "docker compose"
    }

    /// 获取宿主机上所有存在的 Docker Compose 项目/栈列表
    /// - Returns: 包含 Compose 项目状态的 `DockerComposeProjectDTO` 数组；失败返回 `nil`
    func getComposeProjects() async -> [DockerComposeProjectDTO]? {
        let cmd = "\(composeExecutable) ls --all --format json"
        guard let data = await ssh.exec(cmd), let text = data.string else { return nil }

        let decoder = JSONDecoder()
        guard let jsonData = text.data(using: .utf8) else { return nil }

        if let list = try? decoder.decode([DockerComposeProjectDTO].self, from: jsonData) {
            return list
        }
        return parseJSONLines(text, type: DockerComposeProjectDTO.self)
    }

    /// 在给定的工作目录下切换路径并执行指定的 Compose 子命令
    /// - Parameters:
    ///   - workingDir: Compose 项目配置文件所在的目录路径
    ///   - subCommand: Compose 子命令及其参数数组 (例如 `["up", "-d"]`)
    ///   - onLog: 实时标准输出日志回调 (stdout)
    ///   - onError: 实时标准错误日志回调 (stderr)
    /// - Returns: 命令是否成功执行
    func dockerCompose(workingDir: String, subCommand: [String], onLog: ((String) -> Void)? = nil, onError: ((String) -> Void)? = nil) async -> Bool {
        let escapedDir = shellEscape(workingDir)
        let fullCmd = "cd \(escapedDir) && \(composeExecutable) \(subCommand.joined(separator: " "))"
        return await execWithLog(fullCmd, onLog: onLog, onError: onError)
    }

    /// 部署或更新 Compose 项目(1Panel 核心流程)
    ///
    /// 在宿主机指定的目录下自动创建文件夹，写入 `docker-compose.yml` 和 `.env` 环境变量文件，并拉取镜像启动容器栈。
    ///
    /// - Parameters:
    ///   - workingDir: 应用部署的目标文件夹路径 (例如 `/opt/foxterm/apps/wordpress`)
    ///   - composeContent: `docker-compose.yml` 文件的内容
    ///   - envContent: `.env` 环境变量配置文件内容 (可选)
    ///   - pullAlways: 是否强制拉取镜像 (`docker compose up --pull always`)
    ///   - onLog: 实时标准输出日志回调 (stdout)
    ///   - onError: 实时标准错误日志回调 (stderr)
    /// - Returns: 部署并启动服务栈是否完整成功
    func deployComposeStack(workingDir: String, composeContent: String, envContent: String? = nil, pullAlways: Bool = false, onLog: ((String) -> Void)? = nil, onError: ((String) -> Void)? = nil) async -> Bool {
        let escapedDir = shellEscape(workingDir)
        let mkdirCmd = "mkdir -p \(escapedDir)"
        onLog?("$ \(mkdirCmd)\n")
        guard await execWithLog(mkdirCmd, onLog: onLog, onError: onError) else { return false }

        // 写入 docker-compose.yml 内容
        let yamlPath = shellEscape("\(workingDir)/docker-compose.yml")
        let writeYamlCmd = "cat << 'EOF' > \(yamlPath)\n\(composeContent)\nEOF"
        onLog?("$ write \(workingDir)/docker-compose.yml\n")
        guard await execWithLog(writeYamlCmd, onLog: onLog, onError: onError) else { return false }

        // 如果提供了环境变量，则写入 .env 文件
        if let env = envContent, !env.isEmpty {
            let envPath = shellEscape("\(workingDir)/.env")
            let writeEnvCmd = "cat << 'EOF' > \(envPath)\n\(env)\nEOF"
            onLog?("$ write \(workingDir)/.env\n")
            let _: Bool = await execWithLog(writeEnvCmd, onLog: onLog, onError: onError)
        }

        // 启动 Compose 服务栈
        return await composeUp(workingDir: workingDir, build: true, pullAlways: pullAlways, onLog: onLog, onError: onError)
    }

    /// 启动指定的 Compose 项目 (`docker compose up -d`)
    /// - Parameters:
    ///   - workingDir: Compose 项目目录
    ///   - build: 是否在启动前自动重新构建镜像 (`--build`)
    ///   - pullAlways: 是否强制拉取镜像 (`--pull always`)
    ///   - onLog: 实时标准输出日志回调 (stdout)
    ///   - onError: 实时标准错误日志回调 (stderr)
    /// - Returns: 启动是否成功
    func composeUp(workingDir: String, build: Bool = false, pullAlways: Bool = false, onLog: ((String) -> Void)? = nil, onError: ((String) -> Void)? = nil) async -> Bool {
        var args = ["up", "-d"]
        if build {
            args.append("--build")
        }
        if pullAlways {
            args.append(contentsOf: ["--pull", "always"])
        }
        return await dockerCompose(workingDir: workingDir, subCommand: args, onLog: onLog, onError: onError)
    }

    /// 停止并销毁 Compose 项目中的容器与网络 (`docker compose down`)
    /// - Parameters:
    ///   - workingDir: Compose 项目目录
    ///   - removeVolumes: 是否同步删除项目绑定的匿名/命名数据卷 (`-v`)
    /// - Returns: 命令是否成功执行
    func composeDown(workingDir: String, removeVolumes: Bool = false) async -> Bool {
        var args = ["down"]
        if removeVolumes {
            args.append("-v")
        }
        return await dockerCompose(workingDir: workingDir, subCommand: args)
    }

    /// 暂停/停止 Compose 项目包含的所有服务容器 (`docker compose stop`)
    /// - Parameter workingDir: Compose 项目目录
    /// - Returns: 命令是否成功执行
    func composeStop(workingDir: String) async -> Bool {
        await dockerCompose(workingDir: workingDir, subCommand: ["stop"])
    }

    /// 重启 Compose 项目包含的所有服务容器 (`docker compose restart`)
    /// - Parameter workingDir: Compose 项目目录
    /// - Returns: 命令是否成功执行
    func composeRestart(workingDir: String) async -> Bool {
        await dockerCompose(workingDir: workingDir, subCommand: ["restart"])
    }

    /// 查看特定 Compose 项目包含的所有容器运行状态
    /// - Parameter workingDir: Compose 项目目录
    /// - Returns: 项目专属的容器信息 `DockerPSOutputDTO` 数组；失败返回 `nil`
    func composePS(workingDir: String) async -> [DockerPSOutputDTO]? {
        let escapedDir = shellEscape(workingDir)
        let format = "'{{json .}}'"
        let fullCmd = "cd \(escapedDir) && \(composeExecutable) ps -a --format \(format)"

        guard let data = await ssh.exec(fullCmd), let text = data.string else { return nil }
        return parseJSONLines(text, type: DockerPSOutputDTO.self)
    }

    /// 解析并预览 Compose 项目合并/渲染后的最终配置明细 (`docker compose config`)
    /// - Parameter workingDir: Compose 项目目录
    /// - Returns: 格式化后的 YAML 配置文本；失败返回 `nil`
    func composeConfig(workingDir: String) async -> String? {
        let escapedDir = shellEscape(workingDir)
        let fullCmd = "cd \(escapedDir) && \(composeExecutable) config"
        return await ssh.exec(fullCmd)?.string?.trim
    }

    /// 读取 Compose 服务栈下所有容器聚合的标准输出日志
    /// - Parameters:
    ///   - workingDir: Compose 项目目录
    ///   - tail: 读取末尾日志行数 (默认 500 行)
    /// - Returns: 日志合并文本；失败返回 `nil`
    func composeLogs(workingDir: String, tail: Int = 500) async -> String? {
        let escapedDir = shellEscape(workingDir)
        let fullCmd = "cd \(escapedDir) && \(composeExecutable) logs --tail \(tail)"
        return await ssh.exec(fullCmd)?.string?.trim
    }

    /// 读取 Compose 项目主配置文件 (`docker-compose.yml`) 内容，用于编辑/更新
    /// - Parameter workingDir: Compose 项目目录
    /// - Returns: 配置文件原文；读取失败返回 `nil`
    func getComposeFile(workingDir: String) async -> String? {
        let path = shellEscape("\(workingDir)/docker-compose.yml")
        return await ssh.exec("cat \(path)")?.string?.trim
    }

    /// 读取 Compose 项目的环境变量文件 (`.env`) 内容，用于编辑/更新
    /// - Parameter workingDir: Compose 项目目录
    /// - Returns: 环境变量文件原文；文件不存在或读取失败返回 `nil`
    func getComposeEnvFile(workingDir: String) async -> String? {
        let path = shellEscape("\(workingDir)/.env")
        return await ssh.exec("cat \(path)")?.string?.trim
    }

    // MARK: - Volume 数据卷管理

    /// 获取宿主机上所有 Docker Volume 数据卷列表
    /// - Returns: 包含数据卷元数据的 `DockerVolumeOutputDTO` 数组；失败返回 `nil`
    func getDockerVolumes() async -> [DockerVolumeOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([container.command, "volume", "ls", "--format", format]),
            let text = data.string
        else { return nil }

        return parseJSONLines(text, type: DockerVolumeOutputDTO.self)
    }

    /// 在宿主机上创建一个新的 Docker 数据卷
    /// - Parameter name: 数据卷名称
    /// - Returns: 创建是否成功
    func dockerCreateVolume(name: String) async -> Bool {
        await ssh.exec([container.command, "volume", "create", name])
    }

    /// 删除指定的数据卷
    /// - Parameters:
    ///   - name: 数据卷名称
    ///   - force: 是否强制删除数据卷 (`-f`)
    /// - Returns: 删除是否成功
    func dockerRemoveVolume(name: String, force: Bool = false) async -> Bool {
        var cmd = [container.command, "volume", "rm"]
        if force {
            cmd.append("-f")
        }
        cmd.append(name)
        return await ssh.exec(cmd)
    }

    /// 清理所有当前未被任何容器挂载使用的数据卷 (`docker volume prune -f`)
    /// - Returns: 清理是否成功
    func dockerVolumePrune() async -> Bool {
        await ssh.exec([container.command, "volume", "prune", "-f"])
    }

    // MARK: - Network 网络管理

    /// 获取宿主机上所有的 Docker 网络模式列表
    /// - Returns: 包含网络元数据的 `DockerNetworkOutputDTO` 数组；失败返回 `nil`
    func getDockerNetworks() async -> [DockerNetworkOutputDTO]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([container.command, "network", "ls", "--format", format]),
            let text = data.string
        else { return nil }

        return parseJSONLines(text, type: DockerNetworkOutputDTO.self)
    }

    /// 统计各网络被多少容器使用
    ///
    /// 执行 `docker network inspect $(docker network ls -q) -f '{{.Name}} {{len .Containers}}'`，
    /// 一次性获取所有网络及其关联容器数量。
    /// - Returns: 网络名 -> 使用容器数 的字典；失败返回 `nil`
    func getDockerNetworkUsage() async -> [String: Int]? {
        let cmd = "\(container.command) network inspect $(" +
            "\(container.command) network ls -q) -f '{{.Name}} {{len .Containers}}'"
        guard let data = await ssh.exec(cmd), let text = data.string else { return nil }

        var result: [String: Int] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lastSpace = trimmed.lastIndex(of: " "),
                  let count = Int(trimmed[trimmed.index(after: lastSpace)...])
            else { continue }
            result[String(trimmed[..<lastSpace])] = count
        }
        return result.isEmpty ? nil : result
    }

    /// 统计各数据卷被多少容器使用
    ///
    /// 解析 `docker ps -a --no-trunc --format '{{json .}}'` 每个容器的 `Mounts` 字符串字段，
    /// 统计命名卷的引用次数 (绑定挂载以 `/` 开头的绝对路径会被过滤)。
    /// - Returns: 卷名 -> 使用容器数 的字典；失败返回 `nil`
    func getDockerVolumeUsage() async -> [String: Int]? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([container.command, "ps", "-a", "--no-trunc", "--format", format]),
            let text = data.string
        else { return nil }

        var result: [String: Int] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8),
                  let dto = try? JSONDecoder().decode(DockerPSMountsDTO.self, from: lineData)
            else { continue }
            // Mounts 形如 "my_volume, /host/path"，命名卷名不以 "/" 开头
            for raw in (dto.mounts ?? "").components(separatedBy: ",") {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, !name.hasPrefix("/") {
                    result[name, default: 0] += 1
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    /// 创建一个指定驱动类型的 Docker 网络
    /// - Parameters:
    ///   - name: 网络名称
    ///   - driver: 网络驱动模式 (默认 `"bridge"`)
    /// - Returns: 创建是否成功
    func dockerCreateNetwork(name: String, driver: String = "bridge") async -> Bool {
        await ssh.exec([container.command, "network", "create", "--driver", driver, name])
    }

    /// 删除指定的 Docker 网络
    /// - Parameter name: 网络名称或 ID
    /// - Returns: 删除是否成功
    func dockerRemoveNetwork(name: String) async -> Bool {
        await ssh.exec([container.command, "network", "rm", name])
    }

    /// 清理所有当前未被任何容器使用的网络 (`docker network prune -f`)
    /// - Returns: 清理是否成功
    func dockerNetworkPrune() async -> Bool {
        await ssh.exec([container.command, "network", "prune", "-f"])
    }

    // MARK: - 系统级分析与全量清理

    /// 获取 Docker 引擎在宿主机上的系统级磁盘空间占用情况 (`docker system df`)
    /// - Returns: JSON 格式的占用描述；失败返回 `nil`
    func getDockerDiskUsage() async -> String? {
        let format = "'{{json .}}'"
        guard let data = await ssh.exec([container.command, "system", "df", "--format", format]) else {
            return nil
        }
        return data.string?.trim
    }

    /// 对 Docker 引擎进行全量深度垃圾清理 (`docker system prune`)
    /// - Parameter all: 若为 `true`，将一并删除所有未使用的镜像，而不仅是悬空镜像
    /// - Returns: 清理是否成功
    func dockerSystemPrune(all: Bool = false) async -> Bool {
        var cmd = [container.command, "system", "prune", "-f"]
        if all {
            cmd.append("-a")
        }
        return await ssh.exec(cmd)
    }

    // MARK: - 容器引擎系统信息

    /// 获取容器引擎(Docker / Podman)的结构化系统级详细信息 (Info)
    ///
    /// 执行 `docker info --format '{{json .}}'` 并解析为结构化 DTO 模型。
    /// - Returns: 包含版本、架构、资源限制及容器/镜像总数的 `DockerInfoDTO` 结构体；失败返回 `nil`。
    func getContainerInfo() async -> DockerInfoDTO? {
        let format = "'{{json .}}'"
        guard
            let data = await ssh.exec([container.command, "info", "--format", format]),
            let text = data.string?.trim,
            let jsonData = text.data(using: .utf8)
        else { return nil }

        let decoder = JSONDecoder()
        return try? decoder.decode(DockerInfoDTO.self, from: jsonData)
    }

    /// 获取容器引擎原始系统的详细信息文本 (Raw Info)
    ///
    /// 执行 `docker info` 返回未经格式化的原始控制台文本输出(常用于排查引擎故障或配置诊断)。
    /// - Returns: 引擎输出的原始文本内容；执行失败返回 `nil`
    func getContainerInfoRaw() async -> String? {
        await ssh.exec([container.command, "info"])?.string?.trim
    }
}

// MARK: - 私有辅助工具函数

private extension Machine {
    /// 通用 JSON 行文本解析器 (用于逐行解析 Docker 多行 JSON 输出格式)
    /// - Parameters:
    ///   - text: SSH 拿到的包含多行 JSON 的原始文本
    ///   - type: 期望解码的目标 Decodable 泛型类型
    /// - Returns: 解码成功的对象数组
    func parseJSONLines<T: Decodable>(_ text: String, type _: T.Type) -> [T] {
        let decoder = JSONDecoder()
        var results: [T] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            if let dto = try? decoder.decode(T.self, from: lineData) {
                results.append(dto)
            }
        }
        return results
    }

    /// 对 Shell 命令中的路径/参数进行安全单引号转义，防止空格或特殊字符破坏命令语法
    /// - Parameter string: 原始路径或参数字符串
    /// - Returns: 转义并包裹单引号后的安全字符串
    func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 执行远程命令并将 stdout / stderr 实时解码后通过回调输出 (1Panel 风格日志)
    /// - Parameters:
    ///   - command: 待执行的 Shell 命令字符串
    ///   - onLog: 实时标准输出日志回调 (stdout)
    ///   - onError: 实时标准错误日志回调 (stderr)
    /// - Returns: 命令是否成功执行
    func execWithLog(_ command: String, onLog: ((String) -> Void)?, onError: ((String) -> Void)?) async -> Bool {
        let stdoutStream = ClosureOutputStream { data in
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                onLog?(text)
            }
        }
        let stderrStream = ClosureOutputStream { data in
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                onError?(text)
            }
        }
        return await ssh.exec(command, output: stdoutStream, outerr: stderrStream)
    }
}
