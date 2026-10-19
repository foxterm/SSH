// FoxTerm | ContainerDTO.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public struct DockerStats: Identifiable {
    public var id: String {
        container.id
    }

    public let container: DockerPSOutputDTO
    public var stats: DockerStatsOutputDTO?
}

/// 容器引擎(Docker / Podman)全局系统信息数据传输对象 (DTO)
///
/// 对应 `docker info --format '{{json .}}'` 或 `podman info --format '{{json .}}'` 返回的底层数据。
public struct DockerInfoDTO: Codable, Sendable {
    /// 宿主机引擎的唯一标识符(UUID/ID)
    public let id: String?

    /// 宿主机的主机名 (Node Name / Hostname)
    public let name: String?

    /// 容器引擎服务端版本号 (如 `"26.1.3"` 或 `"5.0.2"`)
    public let serverVersion: String?

    /// 宿主机操作系统类型 (如 `"linux"`, `"windows"`)
    public let osType: String?

    /// 宿主机操作系统的发行版详细名称 (如 `"Ubuntu 24.04 LTS"`, `"Debian GNU/Linux 12"`)
    public let operatingSystem: String?

    /// 宿主机的 CPU 硬件架构 (如 `"x86_64"`, `"aarch64"`)
    public let architecture: String?

    /// 宿主机可用逻辑 CPU 核心数
    public let ncpu: Int?

    /// 宿主机总物理内存大小 (单位：字节 Byte)
    public let memTotal: Int64?

    /// 宿主机上现存的所有容器总数(包含运行中、暂停与已停止的容器)
    public let containers: Int?

    /// 当前处于运行中 (Running) 状态的容器数量
    public let containersRunning: Int?

    /// 当前处于暂停 (Paused) 状态的容器数量
    public let containersPaused: Int?

    /// 当前处于已停止 (Exited/Stopped) 状态的容器数量
    public let containersStopped: Int?

    /// 宿主机上存储的镜像 (Images) 总数
    public let images: Int?

    /// 容器引擎使用的存储驱动名称 (如 `"overlay2"`, `"btrfs"`, `"zfs"`)
    public let driver: String?

    /// 容器引擎的数据存储根目录路径 (默认如 `"/var/lib/docker"`)
    public let dockerRootDir: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case serverVersion = "ServerVersion"
        case osType = "OSType"
        case operatingSystem = "OperatingSystem"
        case architecture = "Architecture"
        case ncpu = "NCPU"
        case memTotal = "MemTotal"
        case containers = "Containers"
        case containersRunning = "ContainersRunning"
        case containersPaused = "ContainersPaused"
        case containersStopped = "ContainersStopped"
        case images = "Images"
        case driver = "Driver"
        case dockerRootDir = "DockerRootDir"
    }
}

// MARK: - 端口映射解析模型

public struct DockerPortMapping: Sendable, Hashable {
    public let hostIP: String
    public let hostPort: String
    public let containerPort: String
    public let protocolType: String

    public var displayString: String {
        if hostPort.isEmpty {
            return "\(containerPort)/\(protocolType)"
        }
        return "\(hostIP.isEmpty ? "0.0.0.0" : hostIP):\(hostPort) -> \(containerPort)/\(protocolType)"
    }
}

// MARK: - 容器列表模型

public struct DockerPSOutputDTO: Identifiable, Decodable, Sendable {
    public let id: String
    public let names: String
    public let image: String
    public let status: String
    public let state: String
    public let created: String
    public let portsRaw: String
    public let command: String
    public let labelsRaw: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case image = "Image"
        case status = "Status"
        case state = "State"
        case created = "CreatedAt"
        case portsRaw = "Ports"
        case command = "Command"
        case labelsRaw = "Labels"
    }

    /// 容器主名称
    public var name: String {
        names.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? names
    }

    /// 是否正在运行
    public var isRunning: Bool {
        state.lowercased() == "running"
    }

    /// 解析后的结构化端口映射列表
    public var portMappings: [DockerPortMapping] {
        guard !portsRaw.isEmpty else { return [] }
        var result: [DockerPortMapping] = []
        let entries = portsRaw.components(separatedBy: ",")

        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // 格式解析如: 0.0.0.0:8080->80/tcp, :::8080->80/tcp 或 80/tcp
            if trimmed.contains("->") {
                let parts = trimmed.components(separatedBy: "->")
                let hostPart = parts[0]
                let containerPart = parts.count > 1 ? parts[1] : ""

                let containerSub = containerPart.components(separatedBy: "/")
                let cPort = containerSub[0]
                let proto = containerSub.count > 1 ? containerSub[1] : "tcp"

                var hIP = ""
                var hPort = ""
                if let lastColon = hostPart.lastIndex(of: ":") {
                    hIP = String(hostPart[..<lastColon])
                    hPort = String(hostPart[hostPart.index(after: lastColon)...])
                } else {
                    hPort = hostPart
                }
                result.append(DockerPortMapping(hostIP: hIP, hostPort: hPort, containerPort: cPort, protocolType: proto))
            } else {
                let sub = trimmed.components(separatedBy: "/")
                let cPort = sub[0]
                let proto = sub.count > 1 ? sub[1] : "tcp"
                result.append(DockerPortMapping(hostIP: "", hostPort: "", containerPort: cPort, protocolType: proto))
            }
        }
        return result
    }

    /// 所属 Compose 项目名称 (自动解析 Label: com.docker.compose.project)
    public var composeProject: String? {
        extractLabel("com.docker.compose.project")
    }

    /// Compose 工作目录 (自动解析 Label: com.docker.compose.project.working_dir)
    public var composeWorkingDir: String? {
        extractLabel("com.docker.compose.project.working_dir")
    }

    private func extractLabel(_ key: String) -> String? {
        guard let labelsRaw, !labelsRaw.isEmpty else { return nil }
        let pairs = labelsRaw.components(separatedBy: ",")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count >= 2, kv[0].trimmingCharacters(in: .whitespaces) == key {
                return kv[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

// MARK: - 容器实时监控模型

public struct DockerStatsOutputDTO: Identifiable, Decodable, Sendable {
    public let id: String
    public let name: String
    public let cpuPerc: String
    public let memUsage: String
    public let memPerc: String
    public let netIO: String
    public let blockIO: String
    public let pids: String

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case cpuPerc = "CPUPerc"
        case memUsage = "MemUsage"
        case memPerc = "MemPerc"
        case netIO = "NetIO"
        case blockIO = "BlockIO"
        case pids = "PIDs"
    }

    // MARK: - 便携字段提取

    /// 网络接收 (Recv)，如 `"1.23MB"`
    public var recv: String {
        parsePair(netIO).first
    }

    /// 网络发送 (Sent)，如 `"456kB"`
    public var sent: String {
        parsePair(netIO).second
    }

    /// 硬盘读取 (Read)，如 `"12.5MB"`
    public var read: String {
        parsePair(blockIO).first
    }

    /// 硬盘写入 (Write)，如 `"1.02GB"`
    public var write: String {
        parsePair(blockIO).second
    }

    /// CPU 数值化浮点数百分比 (如 12.5，值域 0~100)
    public var cpuValue: Double {
        Double(cpuPerc.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    /// 内存数值化浮点数百分比 (如 45.2，值域 0~100)
    public var memValue: Double {
        Double(memPerc.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    private func parsePair(_ raw: String) -> (first: String, second: String) {
        let parts = raw.components(separatedBy: "/")
        guard parts.count >= 2 else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.isEmpty ? "0B" : trimmed, "0B")
        }
        let first = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let second = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return (first.isEmpty ? "0B" : first, second.isEmpty ? "0B" : second)
    }
}

// MARK: - 镜像列表模型

public struct DockerImageOutputDTO: Identifiable, Decodable, Sendable {
    public let id = UUID()
    public let imageID: String
    public let repository: String
    public let tag: String
    public let size: String
    public let created: String

    enum CodingKeys: String, CodingKey {
        case imageID = "ID"
        case repository = "Repository"
        case tag = "Tag"
        case size = "Size"
        case created = "CreatedAt"
    }

    public var fullName: String {
        "\(repository):\(tag)"
    }

    public var createdAt: Date? {
        Date(detectFromString: created)
    }
}

/// 包含关联容器计数的 UI / 视图增强模型
public struct DockerImageItem: Identifiable, Sendable {
    public var id: UUID {
        dto.id
    }

    public let dto: DockerImageOutputDTO
    /// 引用/使用该镜像的容器数量(包含已停止的容器)
    public let containerCount: Int
    /// 是否有容器正在使用(如果为 0 则表示该镜像可以安全删除/属于未使用的镜像)
    public var isInUse: Bool {
        containerCount > 0
    }
}

// MARK: - Compose 项目列表模型

public struct DockerComposeProjectDTO: Identifiable, Decodable, Sendable {
    public let id = UUID()
    public let name: String
    public let status: String
    public let configFiles: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case status = "Status"
        case configFiles = "ConfigFiles"
    }

    /// 主配置文件所在目录
    public var workingDir: String? {
        let firstFile = configFiles.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        guard let path = firstFile, !path.isEmpty else { return nil }
        return (path as NSString).deletingLastPathComponent
    }
}

// MARK: - Volume 数据卷模型

public struct DockerVolumeOutputDTO: Identifiable, Decodable, Sendable {
    public var id: String {
        name
    }

    public let name: String
    public let driver: String
    public let scope: String?
    public let mountpoint: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
        case scope = "Scope"
        case mountpoint = "Mountpoint"
    }
}

// MARK: - Network 网络模型

public struct DockerNetworkOutputDTO: Identifiable, Decodable, Sendable {
    public let id: String
    public let name: String
    public let driver: String
    public let scope: String
    public let ipv6: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case driver = "Driver"
        case scope = "Scope"
        case ipv6 = "IPv6"
    }
}

// MARK: - 容器挂载信息（用于统计数据卷使用数）

/// 从 `docker ps --format '{{json .}}'` 中解析的容器挂载信息
///
/// 注意：docker ps 的 JSON 模板中 `Mounts` 字段是逗号分隔的字符串
/// (命名卷显示卷名，绑定挂载显示绝对路径)，并非对象数组。
struct DockerPSMountsDTO: Decodable, Sendable {
    let mounts: String?

    enum CodingKeys: String, CodingKey {
        case mounts = "Mounts"
    }
}

// MARK: - 容器事件流模型

public struct DockerEventDTO: Decodable, Sendable {
    public let type: String?
    public let action: String?
    public let actor: Actor?
    public let time: Int64?

    public struct Actor: Decodable, Sendable {
        public let id: String?
        public let attributes: [String: String]?

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case attributes = "Attributes"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case action = "Action"
        case actor = "Actor"
        case time
    }
}
