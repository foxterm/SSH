// FoxTerm | Load.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 获取平均负载信息
    func getAvgStat() async -> AvgStat? {
        let cmd = "awk '{print $1\"|\"$2\"|\"$3}' /proc/loadavg 2>/dev/null"

        guard
            let output = await ssh.channel.exec(cmd)?.string?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            !output.isEmpty
        else { return nil }

        let p = output.components(separatedBy: "|")
        guard p.count >= 3 else { return nil }

        var avg = AvgStat()
        avg.load1 = Double(p[0].trimmingCharacters(in: .whitespaces)) ?? 0.0
        avg.load5 = Double(p[1].trimmingCharacters(in: .whitespaces)) ?? 0.0
        avg.load15 = Double(p[2].trimmingCharacters(in: .whitespaces)) ?? 0.0
        return avg
    }

    /// 获取系统运行状态（启动时间、上下文切换、进程数等）
    func getSystemStat() async -> SystemStat? {
        let cmd =
            "awk '/^(btime|ctxt|processes|procs_running|procs_blocked)/ {print $1\"|\"$2}' /proc/stat 2>/dev/null"

        guard let lines = await ssh.channel.exec(cmd)?.string?.lines, !lines.isEmpty else {
            return nil
        }

        var sys = SystemStat()
        var found = false

        for line in lines {
            let p = line.components(separatedBy: "|")
            guard p.count == 2 else { continue }

            let key = p[0]
            let val = p[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "btime": sys.bootTime = Int(val) ?? 0
            case "ctxt": sys.context = Int(val) ?? 0
            case "processes": sys.processes = Int64(val) ?? 0
            case "procs_running": sys.processesRunning = Int64(val) ?? 0
            case "procs_blocked": sys.processesBlocked = Int64(val) ?? 0
            default: continue
            }
            found = true
        }

        return found ? sys : nil
    }
}
