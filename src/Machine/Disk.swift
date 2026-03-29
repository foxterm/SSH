// FoxTerm | Disk.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 获取磁盘 I/O 计数统计信息
    /// - Returns: 包含各磁盘读写速率、IOPS 等信息的数组。若执行失败则返回 nil。
    /// - Note: 通过采样 `/proc/diskstats` 两次（间隔 1 秒）计算差值来获取实时速率。
    func getDiskIOCountersStat() async -> [DiskIOCountersStat]? {
        // 两次读取 diskstats，中间通过 sleep 构造时间差以计算速率
        let gatherCmd = "cat /proc/diskstats; echo \"---\"; sleep 1; cat /proc/diskstats"

        guard let output = await ssh.channel.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: "---")
        guard sections.count >= 2 else { return nil }

        /// 解析 /proc/diskstats 的单次快照内容
        /// 数据结构参考 Linux Kernel 文档 (Documentation/admin-guide/iostats.rst)
        func parseDiskStats(_ section: String) -> [String: [String]] {
            var dict: [String: [String]] = [:]
            for line in section.lines {
                let f = line.trimmingCharacters(in: .whitespaces).components(
                    separatedBy: .whitespaces
                ).filter { !$0.isEmpty }

                // 标准 diskstats 至少包含 14 个字段
                guard f.count >= 14 else { continue }
                let name = f[2]

                // 过滤常见的非物理/虚拟块设备，减少数据冗余
                // loop: 回环设备, ram: 内存盘, fd: 软驱, zram: 压缩交换区, dm-: LVM/加密卷
                if name.hasPrefix("loop") || name.hasPrefix("ram") || name.hasPrefix("fd")
                    || name.hasPrefix("zram") || name.hasPrefix("dm-")
                {
                    continue
                }

                dict[name] = f
            }
            return dict
        }

        let s1 = parseDiskStats(sections[0])
        let s2 = parseDiskStats(sections[1])
        var ret: [DiskIOCountersStat] = []

        for (name, f2) in s2 {
            guard let f1 = s1[name] else { continue }

            var io = DiskIOCountersStat()
            io.name = name

            // 内核 2.6+ 固定索引说明：
            // [3]: 读成功次数, [5]: 读扇区数, [6]: 读耗时(ms)
            // [7]: 写成功次数, [9]: 写扇区数, [10]: 写耗时(ms)
            // [11]: 当前在途 I/O 数, [12]: 总 I/O 耗时(ms)

            // 扇区数据转换：Linux 内核统计的扇区大小固定为 512 Bytes
            let rs1 = Int64(f1[5]) ?? 0
            let rs2 = Int64(f2[5]) ?? 0
            let ws1 = Int64(f1[9]) ?? 0
            let ws2 = Int64(f2[9]) ?? 0

            // 计算增量（因采样间隔为 1s，此增量即为 Bytes/s）
            io.readBytes = (rs2 - rs1) * 512
            io.writeBytes = (ws2 - ws1) * 512

            // 累计数据
            io.readBytesTotal = rs2 * 512
            io.writeBytesTotal = ws2 * 512

            // 其他指标差值计算
            io.readCount = (Int64(f2[3]) ?? 0) - (Int64(f1[3]) ?? 0)
            io.writeCount = (Int64(f2[7]) ?? 0) - (Int64(f1[7]) ?? 0)
            io.readTime = (Int64(f2[6]) ?? 0) - (Int64(f1[6]) ?? 0)
            io.writeTime = (Int64(f2[10]) ?? 0) - (Int64(f1[10]) ?? 0)
            io.ioTime = (Int64(f2[12]) ?? 0) - (Int64(f1[12]) ?? 0)
            io.iopsInProgress = Int64(f2[11]) ?? 0

            ret.append(io)
        }

        return ret.isEmpty ? nil : ret
    }

    /// 获取磁盘使用量统计（挂载点空间）
    /// - Returns: 包含挂载路径、总量、已用及剩余空间的数组。
    func getDiskUsageStat() async -> [DiskUsageStat]? {
        // 参数说明：
        // -k: 以 KB 为单位输出
        // -P: 使用 POSIX 标准输出格式，避免设备名过长导致换行
        // awk: 过滤表头并提取 Device|Total|Used|Free|MountPath
        let gatherCmd = "df -kP 2>/dev/null | awk 'NR>1 {print $1\"|\"$2\"|\"$3\"|\"$4\"|\"$6}'"

        guard let lines = await ssh.channel.exec(gatherCmd)?.string?.lines else { return nil }

        var ret: [DiskUsageStat] = []
        for line in lines {
            let p = line.components(separatedBy: "|")
            guard p.count >= 5 else { continue }

            var d = DiskUsageStat()
            d.device = p[0]

            // 单位转换：从 KB 转换为 Bytes 以匹配标准的存储单位处理
            d.total = (Int64(p[1]) ?? 0) * 1024
            d.used = (Int64(p[2]) ?? 0) * 1024
            d.free = (Int64(p[3]) ?? 0) * 1024
            d.mountPoint = p[4]

            if d.total > 0 {
                d.usedPercent = Double(d.used) / Double(d.total)
            }

            // 过滤虚拟文件系统：只保留路径形式的设备（如 /dev/sda1）或远程挂载（如 NFS/SMB 的 IP:Path）
            if !d.device.hasPrefix("/"), !d.device.contains(":") { continue }
            ret.append(d)
        }
        return ret
    }
}
