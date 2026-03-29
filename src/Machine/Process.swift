// FoxTerm | Process.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

public extension Machine {
    func getSystemProcess() async -> [SystemProcess]? {
        // 脚本逻辑：
        // 1. 获取系统启动时间 (btime) 和 时钟节拍 (getconf)
        // 2. 采样两次系统总 CPU 时间 (用于计算分母)
        // 3. 采样两次所有进程的 utime/stime (用于计算分子)
        // 4. 获取所有进程的内存 RSS 和 PID 对应关系
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

        guard let output = await channel.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: "---")
        guard sections.count >= 4 else { return nil }

        // --- 1. 解析基础参数 ---
        let headerLines = sections[0].lines
        var bootTime: Double = 0
        var clkTck: Double = 100
        var totalDelta: Double = 0

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

        /// --- 2. 解析第一次采样进程 (PID -> TotalTicks) ---
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

        // --- 3. 解析内存数据 (PID -> Bytes) ---
        var memDict: [Int: Int64] = [:]
        for line in sections[3].lines {
            // 格式: /proc/123/status:VmRSS: 4560 kB
            let p = line.components(separatedBy: ":")
            guard p.count >= 3,
                  let pidStr = p[0].components(separatedBy: "/").filter({ !$0.isEmpty }).first,
                  let pid = Int(pidStr) else { continue }
            let val = Int64(p[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " kB", with: "")) ?? 0
            memDict[pid] = val * 1024
        }

        // --- 4. 解析第二次采样并汇总 ---
        var ret: [SystemProcess] = []
        for line in sections[2].lines {
            let f = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard f.count > 40, let pid = Int(f[0]) else { continue }

            var v = SystemProcess()
            v.pid = pid
            v.name = f[1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            v.status = .init(rawValue: f[2])
            v.cpuNum = Int(f[38]) ?? 0
            v.memory = memDict[pid] ?? 0 // 补充物理内存

            let ut2 = Double(f[13]) ?? 0
            let st2 = Double(f[14]) ?? 0
            let totalProc2 = ut2 + st2

            if let totalProc1 = p1Dict[pid] {
                // 实时 CPU 百分比计算
                v.percent = (totalProc2 - totalProc1) / totalDelta
            }

            v.user = ut2 / clkTck
            v.system = st2 / clkTck
            v.createTime = ((Double(f[21]) ?? 0.0) / clkTck) + bootTime
            ret.append(v)
        }

        return ret.sorted { $0.percent > $1.percent } // 默认按 CPU 排序
    }
}
