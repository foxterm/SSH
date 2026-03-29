// FoxTerm | Load.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getSystemStat() async -> (AvgStat?, SystemStat?) {
        // 脚本改进：在 Shell 端完成 loadavg 的初步清洗，确保输出格式严格对齐
        let gatherCmd = """
        awk '{print "avg|"$1"|"$2"|"$3}' /proc/loadavg 2>/dev/null
        awk '/^(btime|ctxt|processes|procs_running|procs_blocked)/ {print "sys|"$1"|"$2}' /proc/stat 2>/dev/null
        """

        guard let lines = await channel.exec(gatherCmd)?.string?.lines else { return (nil, nil) }

        var avg = AvgStat()
        var sys = SystemStat()
        var avgFound = false
        var sysFound = false

        for line in lines {
            let p = line.components(separatedBy: "|")
            guard p.count >= 2 else { continue }

            switch p[0] {
            case "avg":
                guard p.count >= 4 else { continue }
                avg.load1 = Double(p[1]) ?? 0.0
                avg.load5 = Double(p[2]) ?? 0.0
                avg.load15 = Double(p[3]) ?? 0.0
                avgFound = true
            case "sys":
                guard p.count == 3 else { continue }
                let key = p[1], val = p[2]
                switch key {
                case "btime": sys.bootTime = Int(val) ?? 0
                case "ctxt": sys.context = Int(val) ?? 0
                case "processes": sys.processes = Int64(val) ?? 0
                case "procs_running": sys.processesRunning = Int64(val) ?? 0
                case "procs_blocked": sys.processesBlocked = Int64(val) ?? 0
                default: break
                }
                sysFound = true
            default: break
            }
        }

        return (avgFound ? avg : nil, sysFound ? sys : nil)
    }
}
