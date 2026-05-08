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
        let boundary = "DISK_STATS_BOUNDARY"
        // 提取：1.name, 2.readCount, 3.mergedRead, 4.readSectors, 5.readTime, 6.writeCount, 7.mergedWrite, 8.writeSectors, 9.writeTime, 10.inProgress, 11.ioTime, 12.weightedIO
        let gatherCmd = """
        /bin/sh -c "awk '{print \\$3\\"|\\"\\$4\\"|\\"\\$5\\"|\\"\\$6\\"|\\"\\$7\\"|\\"\\$8\\"|\\"\\$9\\"|\\"\\$10\\"|\\"\\$11\\"|\\"\\$12\\"|\\"\\$13\\"|\\"\\$14}' /proc/diskstats; echo '\(boundary)'; sleep 1; awk '{print \\$3\\"|\\"\\$4\\"|\\"\\$5\\"|\\"\\$6\\"|\\"\\$7\\"|\\"\\$8\\"|\\"\\$9\\"|\\"\\$10\\"|\\"\\$11\\"|\\"\\$12\\"|\\"\\$13\\"|\\"\\$14}' /proc/diskstats"
        """

        guard let output = await ssh.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: boundary)
        guard sections.count >= 2 else { return nil }

        func parse(_ section: String) -> [String: [Int64]] {
            var dict: [String: [Int64]] = [:]
            for line in section.components(separatedBy: .newlines) {
                let p = line.components(separatedBy: "|")
                guard p.count >= 12 else { continue }
                let devName = p[0]
                // 过滤无意义设备
                if devName.hasPrefix("loop") || devName.hasPrefix("ram") || devName.hasPrefix("zram") { continue }
                dict[devName] = p.dropFirst().map { Int64($0) ?? 0 }
            }
            return dict
        }

        let s1 = parse(sections[0]), s2 = parse(sections[1])

        return s2.compactMap { name, f2 in
            guard let f1 = s1[name], f1.count >= 11, f2.count >= 11 else { return nil }

            var io = DiskIOCountersStat()
            io.name = name

            // 索引说明: 0:rCount, 1:mRCount, 2:rSect, 3:rTime, 4:wCount, 5:mWCount, 6:wSect, 7:wTime, 8:progress, 9:ioTime, 10:weightedIO

            // 1. 实时速率计算 (差值)
            io.readCount = f2[0] - f1[0]
            io.mergedReadCount = f2[1] - f1[1]
            io.readBytes = (f2[2] - f1[2]) * 512 // 扇区转字节
            io.readTime = f2[3] - f1[3]

            io.writeCount = f2[4] - f1[4]
            io.mergedWriteCount = f2[5] - f1[5]
            io.writeBytes = (f2[6] - f1[6]) * 512 // 扇区转字节
            io.writeTime = f2[7] - f1[7]

            io.ioTime = f2[9] - f1[9]

            // 2. 累计值与即时状态
            io.readBytesTotal = f2[2] * 512
            io.writeBytesTotal = f2[6] * 512
            io.iopsInProgress = f2[8]
            io.weightedIO = f2[10]

            return io
        }
    }

    /// 获取磁盘使用量统计（挂载点空间）
    /// - Returns: 包含挂载路径、总量、已用及剩余空间的数组。
    func getDiskUsageStat() async -> [DiskUsageStat]? {
        // 参数说明：
        // -k: 以 KB 为单位输出
        // -P: 使用 POSIX 标准输出格式，避免设备名过长导致换行
        // awk: 过滤表头并提取 Device|Total|Used|Free|MountPath
        let gatherCmd = "df -kP 2>/dev/null | awk 'NR>1 {print $1\"|\"$2\"|\"$3\"|\"$4\"|\"$6}'"

        guard let output = await ssh.exec(gatherCmd)?.string?.lines else { return nil }

        return output.compactMap { line in
            let p = line.components(separatedBy: "|")
            guard p.count >= 5 else { return nil }

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
            if !d.device.hasPrefix("/"), !d.device.contains(":") { return nil }
            return d
        }
    }
}
