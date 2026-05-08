// FoxTerm | Process.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getSystemProcess() async -> [SystemProcess]? {
        let boundary = "PROC_BOUNDARY"
        let gatherCmd = """
        /bin/sh -c "if [ -d /proc ]; then
            echo \\"base|\\$(grep '^btime' /proc/stat | awk '{print \\$2}')|\\$(getconf CLK_TCK 2>/dev/null || echo 100)\\";
            get_total() { grep '^cpu ' /proc/stat | awk '{print \\$2+\\$3+\\$4+\\$5+\\$6+\\$7+\\$8+\\$9+\\$10+\\$11}'; };
            t1=\\$(get_total); p1=\\$(cat /proc/[0-9]*/stat 2>/dev/null);
            sleep 1;
            t2=\\$(get_total); p2=\\$(cat /proc/[0-9]*/stat 2>/dev/null);
            m=\\$(grep -H 'VmRSS:' /proc/[0-9]*/status 2>/dev/null);
            echo \\"total|\\$t1|\\$t2\\"; echo '\\(boundary)';
            echo \\"\\$p1\\"; echo '\\(boundary)';
            echo \\"\\$p2\\"; echo '\\(boundary)';
            echo \\"\\$m\\";
        elif command -v ps >/dev/null; then
            echo \\"ps_mode|macos\\"; echo '\\(boundary)';
            ps -ax -o pid,pcpu,rss,state,comm,time,etime;
        fi"
        """

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
                v.name = f[4].components(separatedBy: "/").last ?? ""
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
            let f = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard f.count > 40, let pid = Int(f[0]) else { return nil }
            var v = SystemProcess()
            v.pid = pid
            v.name = f[1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            v.status = .init(rawValue: f[2])
            v.cpuNum = Int(f[38]) ?? 0
            v.memory = memDict[pid] ?? 0
            let ut2 = Double(f[13]) ?? 0
            let st2 = Double(f[14]) ?? 0
            let totalProc2 = ut2 + st2
            if let totalProc1 = p1Dict[pid] {
                v.percent = (totalProc2 - totalProc1) / totalDelta
            }
            v.user = ut2 / clkTck
            v.system = st2 / clkTck
            v.createTime = ((Double(f[21]) ?? 0.0) / clkTck) + bootTime
            return v
        }.sorted { $0.percent > $1.percent }
    }
}
