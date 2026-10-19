// FoxTerm | StreamStats.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

public extension Machine {
    /// 以异步流（AsyncStream）的方式持续轮询容器实时资源消耗指标
    ///
    /// 用于前端 UI 面板（如 SwiftUI 实时监控界面）持续订阅容器的性能指标变化。
    /// 首帧优化：先快速推送静态容器列表，再异步拉取动态 stats 数据填充。
    ///
    /// - Parameter intervalNanoseconds: 轮询间隔（纳秒），默认 2 秒
    /// - Returns: 持续产生 `[DockerStats]` 数据帧的异步流对象
    func streamDockerStats(intervalNanoseconds: UInt64 = 2_000_000_000) -> AsyncStream<[DockerStats]> {
        AsyncStream { continuation in
            let task = Task {
                // 首帧优化：先快速拉取静态容器列表推送给 UI，不等耗时的动态 stats
                if let psList = await getDockerStat() {
                    let dockerStats = psList.map { DockerStats(container: $0) }
                    continuation.yield(dockerStats)
                }

                while !Task.isCancelled {
                    // 1. 获取静态容器列表并初始化模型数组
                    guard let psList = await getDockerStat() else {
                        do {
                            try await Task.sleep(nanoseconds: intervalNanoseconds)
                            continue
                        } catch {
                            break
                        }
                    }

                    var dockerStats = psList.map { DockerStats(container: $0) }

                    // 2. 获取动态 stats 数据并建立字典映射 (O(1) 查找)
                    if let statsList = await getDockerStats() {
                        // 使用 uniquingKeysWith 规避因容器 ID 或名称重复导致的崩溃
                        let statsMap = Dictionary(statsList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        let statsNameMap = Dictionary(statsList.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

                        // 3. 匹配并填充 stats
                        for i in 0 ..< dockerStats.count {
                            let containerId = dockerStats[i].container.id
                            let containerName = dockerStats[i].container.names

                            // 优先通过 ID 匹配，匹配不上再退化用 Name 匹配
                            if let matchedStats = statsMap[containerId] ?? statsNameMap[containerName] {
                                dockerStats[i].stats = matchedStats
                            }
                        }
                    }

                    continuation.yield(dockerStats)

                    do {
                        try await Task.sleep(nanoseconds: intervalNanoseconds)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 以异步流（AsyncStream）的方式按指定类型和时间间隔持续轮询 Linux 系统性能指标
    ///
    /// 通过传入所需的指标集合，分批并行拉取 CPU、内存、GPU、磁盘等各类系统硬件与运行状态信息。
    /// 每组最多 2 个并发采集任务，避免对 SSH 通道造成过大压力。
    ///
    /// - Parameters:
    ///   - type: 需要轮询监控的指标类型数组（如 `.cpu`、`.mem`、`.net` 等）
    ///   - intervalNanoseconds: 轮询间隔（纳秒），默认 2 秒
    /// - Returns: 包含对应时间节点系统指标的 `LinuxStats` 异步流对象
    func streamLinuxStats(_ type: [LinuxStatsType], intervalNanoseconds: UInt64 = 2_000_000_000) -> AsyncStream<LinuxStats> {
        AsyncStream { continuation in
            let task = Task {
                let typeSet = Set(type) // 转为 Set 提速查找 (O(1))

                while !Task.isCancelled {
                    var linuxStats = LinuxStats()

                    // 将所有可能的抓取任务封装为闭包，按最多 2 个一组进行并发执行
                    // 组 1：CPU 与内存
                    if typeSet.contains(.cpu) || typeSet.contains(.mem) {
                        async let cpus = typeSet.contains(.cpu) ? getCPUTimesStat() : nil
                        async let mem = typeSet.contains(.mem) ? getMemoryStat() : nil
                        linuxStats.cpus = await cpus ?? []
                        linuxStats.mem = await mem
                    }

                    // 组 2：平均负载与 GPU
                    if typeSet.contains(.avg) || typeSet.contains(.gpu) {
                        async let avg = typeSet.contains(.avg) ? getAvgStat() : nil
                        async let gpus = typeSet.contains(.gpu) ? getGPUTimesStat() : nil
                        linuxStats.avg = await avg
                        linuxStats.gpus = await gpus ?? []
                    }

                    // 组 3：温度与系统状态
                    if typeSet.contains(.temp) || typeSet.contains(.sys) {
                        async let temps = typeSet.contains(.temp) ? getTemp() : nil
                        async let sys = typeSet.contains(.sys) ? getSystemStat() : nil
                        linuxStats.temps = await temps ?? []
                        linuxStats.sys = await sys
                    }

                    // 组 4：网络与磁盘 IO
                    if typeSet.contains(.net) || typeSet.contains(.disk) {
                        async let nets = typeSet.contains(.net) ? getNetIOCountersStat() : nil
                        async let disks = typeSet.contains(.disk) ? getDiskIOCountersStat() : nil
                        linuxStats.nets = await nets ?? []
                        linuxStats.disks = await disks ?? []
                    }

                    // 组 5：磁盘空间占用
                    if typeSet.contains(.diskUsage) {
                        linuxStats.diskUsageStats = await getDiskUsageStat() ?? []
                    }

                    continuation.yield(linuxStats)

                    do {
                        try await Task.sleep(nanoseconds: intervalNanoseconds)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
