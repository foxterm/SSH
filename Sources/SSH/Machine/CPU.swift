// FoxTerm | CPU.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getCPUTimesStat() async -> [CPUTimesStat]? {
        let gatherCmd = """
        /bin/sh -c "s1=\\$(cat /proc/stat | grep '^cpu'); sleep 1; s2=\\$(cat /proc/stat | grep '^cpu'); printf '%s\\n%s' \\"\\$s1\\" \\"\\$s2\\" | awk '
        {
            id=\\$1; 
            val=\\$2; for(i=3;i<=11;i++) val=val\\"|\\"\\$i;
            if(arr[id]) { print id\\"|\\"arr[id]\\"|\\"id\\"|\\"val }
            else { arr[id]=val }
        }'"
        """

        // 注意：由于 Swift 字符串转义，脚本中的 $ 改为了 \\$
        guard let output = await ssh.exec(gatherCmd)?.string?.lines else { return nil }

        return output.compactMap { line in
            // 现在输出格式严格为: cpu|user|...|cpu|user...
            let parts = line.components(separatedBy: "|")

            // 解析逻辑保持不变，但现在的 parts 更加稳定
            guard parts.count >= 22 else { return nil }

            let cpuName = parts[0]

            // 解析第一次采样 (t1) - 索引 1 到 10
            var t1 = CPUTimesStat()
            t1.cpu = cpuName
            t1.user = Double(parts[1]) ?? 0
            t1.nice = Double(parts[2]) ?? 0
            t1.system = Double(parts[3]) ?? 0
            t1.idle = Double(parts[4]) ?? 0
            t1.iowait = Double(parts[5]) ?? 0
            t1.irq = Double(parts[6]) ?? 0
            t1.softirq = Double(parts[7]) ?? 0
            t1.steal = Double(parts[8]) ?? 0
            t1.guest = Double(parts[9]) ?? 0
            t1.guestNice = Double(parts[10]) ?? 0

            // 解析第二次采样 (t2) - 索引 12 到 21 (第 11 位是重复的 cpuName)
            var t2 = CPUTimesStat()
            t2.cpu = cpuName
            t2.user = Double(parts[12]) ?? 0
            t2.nice = Double(parts[13]) ?? 0
            t2.system = Double(parts[14]) ?? 0
            t2.idle = Double(parts[15]) ?? 0
            t2.iowait = Double(parts[16]) ?? 0
            t2.irq = Double(parts[17]) ?? 0
            t2.softirq = Double(parts[18]) ?? 0
            t2.steal = Double(parts[19]) ?? 0
            t2.guest = Double(parts[20]) ?? 0
            t2.guestNice = Double(parts[21]) ?? 0

            return CPUTimesStat.calculateUsage(t1: t1, t2: t2)
        }
    }
}
