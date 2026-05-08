// FoxTerm | Net.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getNetIOCountersStat() async -> [NetIOCountersStat]? {
        let boundary = "NET_STAT_BOUNDARY"
        // 1. 提取 /proc/net/dev 的全部 16 个数据字段
        // 2. 增加硬件属性读取循环
        let gatherCmd = """
        /bin/sh -c "sed 's/://g' /proc/net/dev | awk 'NR>2 {print \\$1\\"|\\"\\$2\\"|\\"\\$3\\"|\\"\\$4\\"|\\"\\$5\\"|\\"\\$6\\"|\\"\\$10\\"|\\"\\$11\\"|\\"\\$12\\"|\\"\\$13\\"|\\"\\$14}'; echo '\(boundary)'; sleep 1; sed 's/://g' /proc/net/dev | awk 'NR>2 {print \\$1\\"|\\"\\$2\\"|\\"\\$3\\"|\\"\\$4\\"|\\"\\$5\\"|\\"\\$6\\"|\\"\\$10\\"|\\"\\$11\\"|\\"\\$12\\"|\\"\\$13\\"|\\"\\$14}'; echo '\(boundary)'; for d in /sys/class/net/*; do [ -d \\"\\$d\\" ] && echo \\"hw|\\${d##*/}|\\$(cat \\$d/mtu 2>/dev/null || echo 0)|\\$(cat \\$d/speed 2>/dev/null || echo 0)|\\$(cat \\$d/address 2>/dev/null || echo unknown)\\"; done"
        """

        guard let output = await ssh.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: boundary)
        guard sections.count >= 2 else { return nil }

        /// 解析函数：将 awk 输出的管道符字符串转为数值数组
        func parse(_ section: String) -> [String: [Int64]] {
            var dict: [String: [Int64]] = [:]
            for line in section.components(separatedBy: .newlines) {
                let p = line.components(separatedBy: "|")
                guard p.count >= 11 else { continue }
                let name = p[0]
                dict[name] = p.dropFirst().map { Int64($0) ?? 0 }
            }
            return dict
        }

        let s1 = parse(sections[0]), s2 = parse(sections[1])
        var ret: [NetIOCountersStat] = []

        for (name, d2) in s2 {
            guard let d1 = s1[name], d1.count >= 10, d2.count >= 10 else { continue }

            var io = NetIOCountersStat()
            io.name = name

            // 索引映射说明：
            // 0:bytes_r, 1:pkts_r, 2:err_r, 3:drop_r, 4:fifo_r
            // 5:bytes_t, 6:pkts_t, 7:err_t, 8:drop_t, 9:fifo_t

            // 实时速率（差值）
            io.bytesRecv = d2[0] - d1[0]
            io.packetsRecv = d2[1] - d1[1]
            io.bytesSent = d2[5] - d1[5]
            io.packetsSent = d2[6] - d1[6]

            // 累计总量与状态
            io.bytesRecvTotal = d2[0]
            io.bytesSentTotal = d2[5]
            io.errin = d2[2]
            io.errout = d2[7]
            io.dropin = d2[3]
            io.dropout = d2[8]
            io.fifoin = d2[4]
            io.fifoout = d2[9]

            ret.append(io)
        }

        // 补充硬件静态属性 (MTU, Speed, Address)
        if sections.count >= 3 {
            for line in sections[2].components(separatedBy: .newlines) where line.hasPrefix("hw|") {
                let p = line.components(separatedBy: "|")
                guard p.count >= 5 else { continue }
                if let index = ret.firstIndex(where: { $0.name == p[1] }) {
                    ret[index].mtu = Int64(p[2]) ?? 0
                    let spd = Int64(p[3]) ?? 0
                    ret[index].speed = spd > 0 ? spd * 1_000_000 : 0
                    ret[index].address = p[4]
                }
            }
        }

        return ret.isEmpty ? nil : ret
    }

    func getNetConnStat() async -> [NetConnStat]? {
        let gatherCmd = "/bin/sh -c \"for f in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do [ -f \\$f ] && cat \\$f; done\""

        guard let output = await ssh.exec(gatherCmd)?.string else { return nil }

        var statsDict: [String: Int64] = [:]
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // 1. 过滤掉表头和空行
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("sl") else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // 2. 核心修复：索引解析
            // 在 cat 的输出中，第一列是序号(sl)，第二列是 local_address，第三列是 rem_address
            // 第四列才是状态码 (st) -> 索引为 3
            guard parts.count >= 4 else { continue }

            let stateHex = parts[3].uppercased()
            statsDict[stateHex, default: 0] += 1
        }

        // 如果这时候 statsDict 还是空的，说明数据源有问题
        guard !statsDict.isEmpty else { return nil }

        return statsDict.map { hex, count in
            var stat = NetConnStat()
            stat.count = count
            // Linux 内核状态码映射
            switch hex {
            case "01": stat.state = .established
            case "02": stat.state = .synSent
            case "03": stat.state = .synRecv
            case "04": stat.state = .finWait1
            case "05": stat.state = .finWait2
            case "06": stat.state = .timeWait
            case "07": stat.state = .close
            case "08": stat.state = .closeWait
            case "09": stat.state = .lastAck
            case "0A": stat.state = .listen
            case "0B": stat.state = .closing
            default: stat.state = .unknown
            }
            return stat
        }
    }
}
