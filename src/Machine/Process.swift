// FoxTerm | Process.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 解析 `/proc/[pid]/stat` 的一行内容
    ///
    /// Linux 的进程名(comm)可能包含空格、括号等字符，因此**不能**按空白切分整行。
    /// 正确做法：找到第一个 `(` 与最后一个 `)`，括号内的就是进程名，
    /// 括号后的字段从 state(第 3 个字段)开始，序号与 `man proc` 的字段表一致(comm 已被剥离)。
    ///
    /// - Returns: pid、进程名、以及 comm 之后的全部字段(从 state 开始)
    private func parseStatLine(_ line: String) -> (pid: Int, comm: String, rest: [String])? {
        guard
            let open = line.firstIndex(of: "("),
            let close = line.lastIndex(of: ")"),
            close > open
        else { return nil }

        let pidStr = line[..<open].trimmingCharacters(in: .whitespaces)
        guard let pid = Int(pidStr) else { return nil }

        let comm = String(line[line.index(after: open) ..< close])
        let restStr = line[line.index(after: close)...]
        let rest = restStr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return (pid, comm, rest)
    }

    /// 采集远程主机的系统进程列表及 CPU/内存使用率
    ///
    /// 优先通过 `/proc/[pid]/stat` 两次采样（间隔 1 秒）精确计算各进程 CPU 占用率，
    /// 同时从 `/proc/[pid]/status` 获取 VmRSS 内存用量。
    /// 若 `/proc` 不可用则回退到 `ps` 命令。结果按 CPU 使用率降序排列。
    ///
    /// - Returns: `SystemProcess` 进程信息数组；采集失败返回 `nil`
    func getSystemProcess() async -> [SystemProcess]? {
        let boundary = "PROC_BOUNDARY"
        let gatherCmd = #"if [ -d /proc ]; then echo "base|$(grep '^btime' /proc/stat | awk '{print $2}')|$(getconf CLK_TCK 2>/dev/null || echo 100)"; get_total() { grep '^cpu ' /proc/stat | awk '{print $2+$3+$4+$5+$6+$7+$8+$9+$10+$11}'; }; t1=$(get_total); p1=$(cat /proc/[0-9]*/stat 2>/dev/null); sleep 1; t2=$(get_total); p2=$(cat /proc/[0-9]*/stat 2>/dev/null); m=$(grep -H 'VmRSS:' /proc/[0-9]*/status 2>/dev/null); echo "total|$t1|$t2"; echo "\#(boundary)"; echo "$p1"; echo "\#(boundary)"; echo "$p2"; echo "\#(boundary)"; echo "$m"; elif command -v ps >/dev/null; then echo "ps_mode|fallback"; echo "\#(boundary)"; ps -ax -o pid= -o pcpu= -o rss= -o state= -o comm=; fi"#

        guard let output = await ssh.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: boundary)
        guard sections.count >= 2 else { return nil }

        if sections[0].contains("ps_mode") {
            return sections[1].lines.compactMap { line in
                let f = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard f.count >= 5, let pid = Int(f[0]) else { return nil }
                var v = SystemProcess()
                v.pid = pid
                v.percent = (Double(f[1]) ?? 0.0) / 100.0
                v.memory = (Int64(f[2]) ?? 0) * 1024
                v.status = .init(rawValue: f[3])
                // comm 可能包含空格，取剩余字段拼接
                v.name = f.dropFirst(4).joined(separator: " ")
                return v
            }.sorted { $0.percent > $1.percent }
        }

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

        // 第一次采样：仅需 pid -> (utime + stime)
        func parseProcStat(_ section: String) -> [Int: Double] {
            var dict: [Int: Double] = [:]
            for line in section.lines {
                guard let parsed = parseStatLine(line) else { continue }
                // rest[11] = utime(第14字段), rest[12] = stime(第15字段)
                guard parsed.rest.count > 12 else { continue }
                dict[parsed.pid] = (Double(parsed.rest[11]) ?? 0) + (Double(parsed.rest[12]) ?? 0)
            }
            return dict
        }
        let p1Dict = parseProcStat(sections[1])

        var memDict: [Int: Int64] = [:]
        for line in sections[3].lines {
            let p = line.components(separatedBy: ":")
            guard p.count >= 3,
                  let pidStr = p[0].components(separatedBy: "/").filter({ !$0.isEmpty }).first,
                  let pid = Int(pidStr) else { continue }
            let valStr = p[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " kB", with: "")
            memDict[pid] = (Int64(valStr) ?? 0) * 1024
        }

        return sections[2].lines.compactMap { line in
            guard let parsed = parseStatLine(line) else { return nil }
            let f = parsed.rest
            // 需要 processor(第39字段 -> rest[36])，故要求至少 37 个字段
            guard f.count > 36 else { return nil }

            var v = SystemProcess()
            v.pid = parsed.pid
            v.name = parsed.comm
            v.status = .init(rawValue: f[0])
            v.cpuNum = Int(f[36]) ?? 0
            v.memory = memDict[parsed.pid] ?? 0
            let ut2 = Double(f[11]) ?? 0
            let st2 = Double(f[12]) ?? 0
            let totalProc2 = ut2 + st2
            if let totalProc1 = p1Dict[parsed.pid] {
                // 新进程复用旧 PID 时差值可能为负，做钳制
                v.percent = min(1.0, max(0.0, (totalProc2 - totalProc1) / totalDelta))
            }
            v.user = ut2 / clkTck
            v.system = st2 / clkTck
            v.createTime = ((Double(f[19]) ?? 0.0) / clkTck) + bootTime
            return v
        }.sorted { $0.percent > $1.percent }
    }
}
