// FoxTerm | CPU.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 获取 CPU 各核心的实时使用率统计
    /// 通过两次采样 /proc/stat 并计算时间片差值，得出用户态、内核态、空闲等百分比
    /// - Returns: 每个核心的统计数据数组
    func getCPUTimesStat() async -> [CPUTimesStat]? {
        let gatherCmd = """
        s1=$(cat /proc/stat | grep '^cpu')
        sleep 1
        s2=$(cat /proc/stat | grep '^cpu')
        echo "$s1" | while read -r l1; do
            id=$(echo "$l1" | awk '{print $1}')
            l2=$(echo "$s2" | grep "^$id[[:space:]]")
            echo "$l1|$l2" | awk '{gsub(/[[:space:]]+/,"|"); print $0}'
        done
        """

        guard let lines = await ssh.channel.exec(gatherCmd)?.string?.lines else { return nil }

        var ret: [CPUTimesStat] = []

        for line in lines {
            // 输出格式：cpu|user|nice|system|idle|iowait|irq|softirq|steal|guest|guestNice|cpu|user...
            let parts = line.components(separatedBy: "|")
            // 两次采样各 11 个字段（1个名称+10个数据），共 22 个字段
            guard parts.count >= 22 else { continue }

            let cpuName = parts[0]

            // 解析第一次采样 (t1) - 对应索引 1 到 10
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

            // 解析第二次采样 (t2) - 对应索引 12 到 21（跳过第 11 位的第二个 cpu 名称）
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

            // 调用你现有的 calculateUsage 逻辑
            let finalStat = CPUTimesStat.calculateUsage(t1: t1, t2: t2)
            ret.append(finalStat)
        }

        return ret.isEmpty ? nil : ret
    }
}
