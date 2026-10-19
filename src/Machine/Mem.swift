// FoxTerm | Mem.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 采集远程主机的虚拟内存使用统计信息
    ///
    /// 解析 `/proc/meminfo` 获取总内存、可用内存、缓存、交换空间等详细指标。
    /// 对于内核 < 3.14 无 `MemAvailable` 的情况，使用 `free + buffers + cached` 近似计算。
    ///
    /// - Returns: `VirtualMemoryStat` 内存统计模型；采集失败返回 `nil`
    func getMemoryStat() async -> VirtualMemoryStat? {
        let gatherCmd = #"awk '{print $1"|"$2}' /proc/meminfo | tr -d ':'"#

        guard let lines = await ssh.exec(gatherCmd)?.string?.lines else { return nil }

        var ret = VirtualMemoryStat()
        var memavailFound = false

        for line in lines {
            let parts = line.components(separatedBy: "|")
            guard parts.count == 2 else { continue }

            let key = parts[0]
            let val = Int64(parts[1]) ?? 0
            let bytes = val * 1024

            switch key {
            case "MemTotal": ret.total = bytes
            case "MemFree": ret.free = bytes
            case "MemAvailable":
                ret.available = bytes
                memavailFound = true
            case "Buffers": ret.buffers = bytes
            case "Cached": ret.cached = bytes
            case "Active": ret.active = bytes
            case "Inactive": ret.inactive = bytes
            case "Active(anon)": ret.activeAnon = bytes
            case "Inactive(anon)": ret.inactiveAnon = bytes
            case "Active(file)": ret.activeFile = bytes
            case "Inactive(file)": ret.inactiveFile = bytes
            case "Unevictable": ret.unevictable = bytes
            case "Writeback": ret.writeBack = bytes
            case "WritebackTmp": ret.writeBackTmp = bytes
            case "Dirty": ret.dirty = bytes
            case "Shmem": ret.shared = bytes
            case "Slab": ret.slab = bytes
            case "SReclaimable": ret.sreclaimable = bytes
            case "SUnreclaim": ret.sunreclaim = bytes
            case "PageTables": ret.pageTables = bytes
            case "SwapCached": ret.swapCached = bytes
            case "CommitLimit": ret.commitLimit = bytes
            case "Committed_AS": ret.committedAS = bytes
            case "HighTotal": ret.highTotal = bytes
            case "HighFree": ret.highFree = bytes
            case "LowTotal": ret.lowTotal = bytes
            case "LowFree": ret.lowFree = bytes
            case "SwapTotal": ret.swapTotal = bytes
            case "SwapFree": ret.swapFree = bytes
            case "Mapped": ret.mapped = bytes
            case "VmallocTotal": ret.vmallocTotal = bytes
            case "VmallocUsed": ret.vmallocUsed = bytes
            case "VmallocChunk": ret.vmallocChunk = bytes
            case "HugePages_Total": ret.hugePagesTotal = val
            case "HugePages_Free": ret.hugePagesFree = val
            case "HugePages_Rsvd": ret.hugePagesRsvd = val
            case "HugePages_Surp": ret.hugePagesSurp = val
            case "Hugepagesize": ret.hugePageSize = bytes
            case "AnonHugePages": ret.anonHugePages = bytes
            default: break
            }
        }

        // 后处理计算逻辑
        if !memavailFound {
            // 内核 < 3.14 没有 MemAvailable：用 free + buffers + cached 近似可用内存
            ret.available = ret.free + ret.buffers + ret.cached
            // 已用内存 = Total - Free - Buffers - Cached
            ret.used = max(0, ret.total - ret.free - ret.buffers - ret.cached)
        } else {
            // 现代内核：已用 = 总量 - 可用(更贴近 free 命令口径)
            ret.used = max(0, ret.total - ret.available)
        }

        if ret.total > 0 {
            ret.usedPercent = min(1.0, max(0.0, Double(ret.used) / Double(ret.total)))
        }

        return ret
    }
}
