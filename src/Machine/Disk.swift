// FoxTerm | Disk.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getDiskIOCountersStat() async -> [DiskIOCountersStat]? {
        let gatherCmd = "cat /proc/diskstats; echo \"---\"; sleep 1; cat /proc/diskstats"

        guard let output = await channel.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: "---")
        guard sections.count >= 2 else { return nil }

        func parseDiskStats(_ section: String) -> [String: [String]] {
            var dict: [String: [String]] = [:]
            for line in section.lines {
                let f = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard f.count >= 14 else { continue }
                let name = f[2]

                // 建议：过滤常见的非物理/虚拟块设备
                // zram: 内存压缩交换区, dm-: LVM/加密卷
                if name.hasPrefix("loop") || name.hasPrefix("ram") || name.hasPrefix("fd") ||
                    name.hasPrefix("zram") || name.hasPrefix("dm-") { continue }

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

            // 内核 2.6+ 固定索引：
            // 3:读次数, 5:读扇区, 6:读耗时, 7:写次数, 9:写扇区, 10:写耗时, 11:在途IO, 12:总IO耗时
            let rs1 = Int64(f1[5]) ?? 0, rs2 = Int64(f2[5]) ?? 0
            let ws1 = Int64(f1[9]) ?? 0, ws2 = Int64(f2[9]) ?? 0

            io.readBytes = (rs2 - rs1) * 512
            io.writeBytes = (ws2 - ws1) * 512
            io.readBytesTotal = rs2 * 512
            io.writeBytesTotal = ws2 * 512

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

    func getDiskUsageStat() async -> [DiskUsageStat]? {
        // 使用 POSIX 标准参数 -k (KB) 和 -P (不换行)
        let gatherCmd = "df -kP 2>/dev/null | awk 'NR>1 {print $1\"|\"$2\"|\"$3\"|\"$4\"|\"$6}'"

        guard let lines = await channel.exec(gatherCmd)?.string?.lines else { return nil }

        var ret: [DiskUsageStat] = []
        for line in lines {
            let p = line.components(separatedBy: "|")
            guard p.count >= 5 else { continue }

            var d = DiskUsageStat()
            d.device = p[0]
            // 转换为 Bytes (KB * 1024)
            d.total = (Int64(p[1]) ?? 0) * 1024
            d.used = (Int64(p[2]) ?? 0) * 1024
            d.free = (Int64(p[3]) ?? 0) * 1024
            d.mountPoint = p[4]

            if d.total > 0 {
                d.usedPercent = Double(d.used) / Double(d.total)
            }

            // 过滤虚拟文件系统（只保留 /dev 开头的或网络挂载）
            if !d.device.hasPrefix("/"), !d.device.contains(":") { continue }
            ret.append(d)
        }
        return ret
    }
}
