// FoxTerm | Process.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 获取系统进程列表及实时性能指标
    /// - Returns: 包含 PID、进程名、CPU 占用率、内存使用及启动时间等信息的数组，按 CPU 占用降序排列。
    /// - Note:
    ///   1. CPU 计算原理：(进程总 Ticks 差值 / 系统总 Ticks 差值) * 100%。
    ///   2. 内存原理：解析 `/proc/[pid]/status` 中的 VmRSS 字段。
    ///   3. 兼容性：直接读取 procfs，不依赖 `top` 或 `ps` 命令，效率更高。
    func getSystemProcess() async -> [SystemProcess]? {
        // 脚本逻辑：
        // 1. 获取系统启动时间 (btime) 用于计算进程绝对启动时间。
        // 2. 获取 CLK_TCK (通常为 100)，用于将内核 Ticks 转换为秒。
        // 3. 对系统总 CPU 和所有进程 CPU 采样两次（间隔 1 秒）以计算瞬时占用。
        let gatherCmd = """
        echo "base|$(grep '^btime' /proc/stat | awk '{print $2}')|$(getconf CLK_TCK 2>/dev/null || echo 100)"
        get_total() { grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8+$9+$10+$11}'; }
        t1=$(get_total); p1=$(cat /proc/[0-9]*/stat 2>/dev/null)
        sleep 1
        t2=$(get_total); p2=$(cat /proc/[0-9]*/stat 2>/dev/null)
        m=$(grep -H 'VmRSS:' /proc/[0-9]*/status 2>/dev/null)
        echo "total|$t1|$t2"
        echo "---"
        echo "$p1"
        echo "---"
        echo "$p2"
        echo "---"
        echo "$m"
        """

        guard let output = await ssh.channel.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: "---")
        guard sections.count >= 4 else { return nil }

        // --- 1. 解析基础参数与系统 CPU 增量 ---
        let headerLines = sections[0].lines
        var bootTime: Double = 0
        var clkTck: Double = 100
        var totalDelta: Double = 0 // 系统总 Ticks 差值（分母）

        for line in headerLines {
            let p = line.components(separatedBy: "|")
            if p[0] == "base" {
                bootTime = Double(p[1]) ?? 0
                clkTck = Double(p[2]) ?? 100
            } else if p[0] == "total" {
                totalDelta = (Double(p[2]) ?? 0) - (Double(p[1]) ?? 0)
            }
        }
        guard totalDelta > 0 else { return nil }

        /// 解析单次快照中的进程 Ticks
        /// 索引说明：13: utime (用户态 Ticks), 14: stime (核心态 Ticks)
        func parseProcStat(_ section: String) -> [Int: Double] {
            var dict: [Int: Double] = [:]
            for line in section.lines {
                let f = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if f.count > 14, let pid = Int(f[0]) {
                    dict[pid] = (Double(f[13]) ?? 0) + (Double(f[14]) ?? 0)
                }
            }
            return dict
        }
        let p1Dict = parseProcStat(sections[1])

        // --- 2. 解析内存数据 (PID -> Bytes) ---
        var memDict: [Int: Int64] = [:]
        for line in sections[3].lines {
            // 预期格式: /proc/123/status:VmRSS: 4560 kB
            let p = line.components(separatedBy: ":")
            guard p.count >= 3,
                  let pidStr = p[0].components(separatedBy: "/").filter({ !$0.isEmpty }).first,
                  let pid = Int(pidStr)
            else { continue }

            // 提取数值并从 kB 转为 Bytes
            let valStr = p[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " kB", with: "")
            memDict[pid] = (Int64(valStr) ?? 0) * 1024
        }

        // --- 3. 汇总第二次采样数据并计算最终指标 ---
        var ret: [SystemProcess] = []
        for line in sections[2].lines {
            let f = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            // 基础校验：/proc/stat 至少应包含 52 个字段，pid 在索引 0
            guard f.count > 40, let pid = Int(f[0]) else { continue }

            var v = SystemProcess()
            v.pid = pid
            // 进程名通常在括号中，如 "(bash)"
            v.name = f[1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            // 状态码：R (running), S (sleeping), D (disk sleep), Z (zombie) 等
            v.status = .init(rawValue: f[2])
            // 索引 38: processor (最后运行该进程的 CPU 核心编号)
            v.cpuNum = Int(f[38]) ?? 0
            v.memory = memDict[pid] ?? 0

            let ut2 = Double(f[13]) ?? 0
            let st2 = Double(f[14]) ?? 0
            let totalProc2 = ut2 + st2

            if let totalProc1 = p1Dict[pid] {
                // 实时 CPU 百分比 = (进程 Ticks 差值 / 系统总 Ticks 差值)
                // 注意：这里没有乘以核心数，通常表示“占单核的百分比”
                v.percent = (totalProc2 - totalProc1) / totalDelta
            }

            // 累计耗时转换为秒
            v.user = ut2 / clkTck
            v.system = st2 / clkTck

            // 启动时间计算：索引 21 (starttime) 是系统启动后的 Ticks
            // 公式：(starttime / CLK_TCK) + btime
            v.createTime = ((Double(f[21]) ?? 0.0) / clkTck) + bootTime
            ret.append(v)
        }

        // 默认按 CPU 消耗降序排列，方便前端展示“热点”进程
        return ret.sorted { $0.percent > $1.percent }
    }
}
