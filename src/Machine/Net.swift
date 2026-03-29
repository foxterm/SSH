// FoxTerm | Net.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 获取网络 I/O 统计与硬件属性
    /// - Returns: 包含各网卡的流量速率、累计值、MTU 及物理地址等信息。
    /// - Note:
    ///   1. 通过采样 `/proc/net/dev` 两次（间隔 1 秒）计算瞬时带宽。
    ///   2. 遍历 `/sys/class/net/` 获取网卡硬件静态属性。
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

        /// 解析 /proc/net/dev 内容
        /// 每一行格式为 `interface: receive_bytes receive_packets ... transmit_bytes ...`
        func parseNetDev(_ section: String) -> [String: [Int64]] {
            var dict: [String: [Int64]] = [:]
            for line in section.lines {
                guard line.contains(":") else { continue }
                let parts = line.components(separatedBy: ":")
                let name = parts[0].trimmingCharacters(in: .whitespaces)

                // 提取所有数值字段。标准内核输出通常为 16 个字段
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
            // 确保采样完整且字段数符合预期（至少包含 16 个统计项）
            guard let d1 = sample1[name], d1.count >= 16, d2.count >= 16 else { continue }

            var io = NetIOCountersStat()
            io.name = name

            // Linux 内核索引说明:
            // Receive (0-7): 0:bytes, 1:packets, 2:errs, 3:drop, 4:fifo, 5:frame, 6:compressed, 7:multicast
            // Transmit (8-15): 8:bytes, 9:packets, 10:errs, 11:drop, 12:fifo, 13:colls, 14:carrier, 15:compressed

            // 计算 1 秒内的差值（速率）
            io.bytesRecv = d2[0] - d1[0]
            io.bytesSent = d2[8] - d1[8]

            // 累计总量
            io.bytesRecvTotal = d2[0]
            io.bytesSentTotal = d2[8]

            io.packetsRecv = d2[1] - d1[1]
            io.packetsSent = d2[9] - d1[9]

            // 错误与丢包统计
            io.errin = d2[2]
            io.errout = d2[10]
            io.dropin = d2[3]
            io.dropout = d2[11]

            ret.append(io)
        }

        // 补充网卡硬件属性 (MTU, Speed, MAC)
        if sections.count >= 3 {
            for line in sections[2].lines where line.hasPrefix("hw|") {
                let p = line.components(separatedBy: "|")
                guard p.count >= 5 else { continue }
                if let index = ret.firstIndex(where: { $0.name == p[1] }) {
                    ret[index].mtu = Int64(p[2]) ?? 0

                    // speed 文件单位为 Mbps，需转换为 bps
                    // 某些虚拟网卡或未连接的网卡 speed 为 -1
                    let spd = Int64(p[3]) ?? 0
                    ret[index].speed = spd > 0 ? spd * 1_000_000 : 0
                    ret[index].address = p[4]
                }
            }
        }
        return ret.isEmpty ? nil : ret
    }

    /// 获取网络连接状态统计
    /// - Returns: 按 协议 + 状态 分组的连接统计列表。
    /// - Note: 直接读取 `/proc/net/tcp[6]` 和 `/proc/net/udp[6]`，避免调用 netstat/ss 命令以提高性能。
    func getNetConnStat() async -> [NetConnStat]? {
        // 使用 awk 在服务器端完成分组聚合，第 4 列 ($4) 是十六进制的状态码
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
            stat.ipVersion = (p[0] == "v6") ? .v6 : .v4
            stat.protocol = (p[1] == "udp") ? .udp : .tcp
            stat.count = Int64(p[3]) ?? 0

            // 内核定义的 TCP 状态十六进制映射 (include/net/tcp_states.h)
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
