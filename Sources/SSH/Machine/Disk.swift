// FoxTerm | Disk.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 获取磁盘 I/O 计数统计信息
    func getDiskIOCountersStat() async -> [DiskIOCountersStat]? {
        let boundary = "DISK_STATS_BOUNDARY"

        let gatherCmd = #"awk '{print $3"|"$4"|"$5"|"$6"|"$7"|"$8"|"$9"|"$10"|"$11"|"$12"|"$13"|"$14}' /proc/diskstats; echo "\#(boundary)"; sleep 1; awk '{print $3"|"$4"|"$5"|"$6"|"$7"|"$8"|"$9"|"$10"|"$11"|"$12"|"$13"|"$14}' /proc/diskstats"#

        guard let output = await ssh.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: boundary)
        guard sections.count >= 2 else { return nil }

        func parse(_ section: String) -> [String: [Int64]] {
            var dict: [String: [Int64]] = [:]
            for line in section.components(separatedBy: .newlines) {
                let p = line.components(separatedBy: "|")
                guard p.count >= 12 else { continue }
                let devName = p[0]
                if devName.hasPrefix("loop") || devName.hasPrefix("ram") || devName.hasPrefix("zram") {
                    continue
                }
                dict[devName] = p.dropFirst().map { Int64($0) ?? 0 }
            }
            return dict
        }

        let s1 = parse(sections[0]), s2 = parse(sections[1])

        return s2.compactMap { name, f2 in
            guard let f1 = s1[name], f1.count >= 11, f2.count >= 11 else { return nil }

            var io = DiskIOCountersStat()
            io.name = name

            io.readCount = f2[0] - f1[0]
            io.mergedReadCount = f2[1] - f1[1]
            io.readBytes = (f2[2] - f1[2]) * 512
            io.readTime = f2[3] - f1[3]

            io.writeCount = f2[4] - f1[4]
            io.mergedWriteCount = f2[5] - f1[5]
            io.writeBytes = (f2[6] - f1[6]) * 512
            io.writeTime = f2[7] - f1[7]

            io.ioTime = f2[9] - f1[9]

            io.readBytesTotal = f2[2] * 512
            io.writeBytesTotal = f2[6] * 512
            io.iopsInProgress = f2[8]
            io.weightedIO = f2[10]

            return io
        }
    }

    /// 获取磁盘使用量统计（挂载点空间）
    func getDiskUsageStat() async -> [DiskUsageStat]? {
        let gatherCmd = #"df -kP 2>/dev/null | awk 'NR>1 {print $1"|"$2"|"$3"|"$4"|"$6}'"#

        guard let output = await ssh.exec(gatherCmd)?.string?.lines else { return nil }

        return output.compactMap { line in
            let p = line.components(separatedBy: "|")
            guard p.count >= 5 else { return nil }

            var d = DiskUsageStat()
            d.device = p[0]

            d.total = (Int64(p[1]) ?? 0) * 1024
            d.used = (Int64(p[2]) ?? 0) * 1024
            d.free = (Int64(p[3]) ?? 0) * 1024
            d.mountPoint = p[4]

            if d.total > 0 {
                d.usedPercent = Double(d.used) / Double(d.total)
            }

            if !d.device.hasPrefix("/"), !d.device.contains(":") {
                return nil
            }
            return d
        }
    }
}
