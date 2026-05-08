// FoxTerm | Mem.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getMemoryStat() async -> VirtualMemoryStat? {
        // 强制使用 /bin/sh，通过 awk 格式化输出，确保 Zsh 下也不会解析错位
        let gatherCmd = """
        /bin/sh -c "awk '{print \\$1\\"|\\"\\$2}' /proc/meminfo | tr -d ':'"
        """

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
            ret.available = ret.cached + ret.free
        }

        // 计算已用内存：Total - Free - Buffers - Cached
        ret.used = ret.total - ret.free - ret.buffers - ret.cached

        if ret.total > 0 {
            ret.usedPercent = Double(ret.used) / Double(ret.total)
        }

        return ret
    }
}
