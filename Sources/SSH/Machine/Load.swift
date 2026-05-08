// FoxTerm | Load.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getAvgStat() async -> AvgStat? {
        let cmd = "/bin/sh -c \"if [ -f /proc/loadavg ]; then awk '{print \\$1\\\"|\\\"\\$2\\\"|\\\"\\$3}' /proc/loadavg; else uptime | awk -F'load average: ' '{print \\$2}' | sed 's/,//g; s/ /|/g'; fi\""

        guard let output = await ssh.exec(cmd)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { return nil }

        let p = output.contains("|") ? output.components(separatedBy: "|") : output.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard p.count >= 3 else { return nil }

        var avg = AvgStat()
        avg.load1 = Double(p[0]) ?? 0.0
        avg.load5 = Double(p[1]) ?? 0.0
        avg.load15 = Double(p[2]) ?? 0.0
        return avg
    }

    func getSystemStat() async -> SystemStat? {
        let cmd = "/bin/sh -c \"if [ -f /proc/stat ]; then awk '/^(btime|ctxt|processes|procs_running|procs_blocked)/ {print \\$1\\\"|\\\"\\$2}' /proc/stat; elif command -v sysctl >/dev/null; then btime=\\$(sysctl -n kern.boottime | awk '{print \\$4}' | tr -d ','); echo \\\"btime|\\$btime\\\"; echo \\\"processes|\\$(ps ax | wc -l)\\\"; fi\""

        guard let lines = await ssh.exec(cmd)?.string?.lines, !lines.isEmpty else { return nil }

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
