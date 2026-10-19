// FoxTerm | Net.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 采集远程主机各网络接口的 IO 流量统计
    ///
    /// 通过两次采样 `/proc/net/dev`（间隔 1 秒）计算实时收发速率，
    /// 同时从 `/sys/class/net/*/` 获取 MTU、链路速率和 MAC 地址等硬件属性。
    ///
    /// - Returns: 各网络接口的 `NetIOCountersStat` 数组；采集失败返回 `nil`
    func getNetIOCountersStat() async -> [NetIOCountersStat]? {
        let boundary = "NET_STAT_BOUNDARY"
        let gatherCmd = #"sed 's/://g' /proc/net/dev | awk 'NR>2 {print $1"|"$2"|"$3"|"$4"|"$5"|"$6"|"$10"|"$11"|"$12"|"$13"|"$14}'; echo "\#(boundary)"; sleep 1; sed 's/://g' /proc/net/dev | awk 'NR>2 {print $1"|"$2"|"$3"|"$4"|"$5"|"$6"|"$10"|"$11"|"$12"|"$13"|"$14}'; echo "\#(boundary)"; for d in /sys/class/net/*; do [ -d "$d" ] && echo "hw|${d##*/}|$(cat $d/mtu 2>/dev/null || echo 0)|$(cat $d/speed 2>/dev/null || echo 0)|$(cat $d/address 2>/dev/null || echo unknown)"; done"#

        guard let output = await ssh.exec(gatherCmd)?.string else { return nil }
        let sections = output.components(separatedBy: boundary)
        guard sections.count >= 2 else { return nil }

        // 解析函数：将 awk 输出的管道符字符串转为数值数组
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

            // 实时速率(差值)
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

    /// 采集远程主机的网络连接状态统计（按 IP 版本、协议和状态聚合计数）
    ///
    /// 解析 `/proc/net/tcp`、`/proc/net/tcp6`、`/proc/net/udp`、`/proc/net/udp6`，
    /// 将各连接按 TCP 状态码（ESTABLISHED、LISTEN、TIME_WAIT 等）分组计数。
    ///
    /// - Returns: 聚合后的 `NetConnStat` 数组；采集失败返回 `nil`
    func getNetConnStat() async -> [NetConnStat]? {
        // 用 FILE 标记区分 tcp/tcp6/udp/udp6，从而正确填充 ipVersion 与 protocol
        let gatherCmd = #"for f in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do [ -f "$f" ] && { echo "FILE|$f"; cat "$f"; }; done"#

        guard let output = await ssh.exec(gatherCmd)?.string else { return nil }

        // 状态码 -> NetConnState 的映射
        func state(from hex: String) -> NetConnState {
            switch hex {
            case "01": .established
            case "02": .synSent
            case "03": .synRecv
            case "04": .finWait1
            case "05": .finWait2
            case "06": .timeWait
            case "07": .close
            case "08": .closeWait
            case "09": .lastAck
            case "0A": .listen
            case "0B": .closing
            default: .unknown
            }
        }

        var statsDict: [String: (version: NetIPVersion, protocol: NetProtocol, state: NetConnState, count: Int64)] = [:]
        var currentVersion = NetIPVersion.v4
        var currentProtocol = NetProtocol.tcp

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 文件切换标记
            if trimmed.hasPrefix("FILE|") {
                let path = String(trimmed.dropFirst(5))
                if path.contains("udp") {
                    currentProtocol = .udp
                } else {
                    currentProtocol = .tcp
                }
                currentVersion = path.contains("6") ? .v6 : .v4
                continue
            }

            // 跳过表头和空行
            guard !trimmed.isEmpty, !trimmed.hasPrefix("sl") else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // 第 4 列为状态码 (st)，索引为 3
            guard parts.count >= 4 else { continue }

            let stateHex = parts[3].uppercased()
            let key = "\(currentVersion.rawValue)|\(currentProtocol.rawValue)|\(stateHex)"
            statsDict[key, default: (currentVersion, currentProtocol, state(from: stateHex), 0)].count += 1
        }

        guard !statsDict.isEmpty else { return nil }

        return statsDict.values.map { item in
            var stat = NetConnStat()
            stat.ipVersion = item.version
            stat.protocol = item.protocol
            stat.state = item.state
            stat.count = item.count
            return stat
        }
    }
}
