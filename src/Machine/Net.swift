// FoxTerm | Net.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getNetIOCountersStat() async -> [NetIOCountersStat]? {
        let gatherCmd = """
        cat /proc/net/dev; echo "---"; sleep 1; cat /proc/net/dev; echo "---"
        for d in /sys/class/net/*; do
            [ -d "$d" ] || continue
            n=${d##*/}
            echo "hw|$n|$(cat $d/mtu 2>/dev/null || echo 0)|$(cat $d/speed 2>/dev/null || echo 0)|$(cat $d/address 2>/dev/null || echo unknown)"
        done
        """

        guard let output = await ssh.channel.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: "---")
        guard sections.count >= 2 else { return nil }

        func parseNetDev(_ section: String) -> [String: [Int64]] {
            var dict: [String: [Int64]] = [:]
            for line in section.lines {
                guard line.contains(":") else { continue }
                let parts = line.components(separatedBy: ":")
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                // 修正点：使用 map + nil 合并，确保数组长度固定为 16
                let vals = parts[1].components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .map { Int64($0) ?? 0 }
                dict[name] = vals
            }
            return dict
        }

        let sample1 = parseNetDev(sections[0])
        let sample2 = parseNetDev(sections[1])
        var ret: [NetIOCountersStat] = []

        for (name, d2) in sample2 {
            // 修正点：d1.count 和 d2.count 现在更有保障
            guard let d1 = sample1[name], d1.count >= 16, d2.count >= 16 else { continue }

            var io = NetIOCountersStat()
            io.name = name
            // 索引说明：0:rBytes, 1:rPackets, 2:rErrs, 3:rDrop, 8:sBytes, 10:sErrs, 11:sDrop
            io.bytesRecv = d2[0] - d1[0]
            io.bytesSent = d2[8] - d1[8]
            io.bytesRecvTotal = d2[0]
            io.bytesSentTotal = d2[8]
            io.packetsRecv = d2[1] - d1[1]
            io.packetsSent = d2[9] - d1[9]
            io.errin = d2[2]
            io.errout = d2[10]
            io.dropin = d2[3]
            io.dropout = d2[11]
            ret.append(io)
        }

        // 补充硬件属性
        if sections.count >= 3 {
            for line in sections[2].lines where line.hasPrefix("hw|") {
                let p = line.components(separatedBy: "|")
                guard p.count >= 5 else { continue }
                if let index = ret.firstIndex(where: { $0.name == p[1] }) {
                    ret[index].mtu = Int64(p[2]) ?? 0
                    // 某些虚拟网卡 speed 为 -1，需处理
                    let spd = Int64(p[3]) ?? 0
                    ret[index].speed = spd > 0 ? spd * 1_000_000 : 0
                    ret[index].address = p[4]
                }
            }
        }
        return ret.isEmpty ? nil : ret
    }

    func getNetConnStat() async -> [NetConnStat]? {
        // 脚本逻辑：分别读取 4 个内核文件，通过前缀区分协议和 IP 版本
        let gatherCmd = """
        awk 'NR>1 {st[$4]++} END {for(s in st) print "v4|tcp|"s"|"st[s]}' /proc/net/tcp 2>/dev/null
        awk 'NR>1 {st[$4]++} END {for(s in st) print "v6|tcp|"s"|"st[s]}' /proc/net/tcp6 2>/dev/null
        awk 'NR>1 {st[$4]++} END {for(s in st) print "v4|udp|"s"|"st[s]}' /proc/net/udp 2>/dev/null
        awk 'NR>1 {st[$4]++} END {for(s in st) print "v6|udp|"s"|"st[s]}' /proc/net/udp6 2>/dev/null
        """

        guard let lines = await ssh.channel.exec(gatherCmd)?.string?.lines else { return nil }

        var ret: [NetConnStat] = []

        for line in lines {
            let p = line.components(separatedBy: "|")
            guard p.count == 4 else { continue }

            var stat = NetConnStat()

            // 1. 识别 IP 版本
            stat.ipVersion = (p[0] == "v6") ? .v6 : .v4

            // 2. 识别协议
            stat.protocol = (p[1] == "udp") ? .udp : .tcp

            // 3. 统计数量
            stat.count = Int64(p[3]) ?? 0

            // 4. 映射状态码
            let hexState = p[2].uppercased()
            switch hexState {
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

            ret.append(stat)
        }

        return ret.isEmpty ? nil : ret
    }
}
