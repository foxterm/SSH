// FoxTerm | LinuxStats.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh2

extension Machine {
    // MARK: - 标准 Linux 虚拟文件系统路径定义

    var hostEtc: String {
        "/etc"
    }

    var hostProc: String {
        "/proc"
    }

    var hostSys: String {
        "/sys"
    }

    var hostDev: String {
        "/dev"
    }

    var hostClass: String {
        hostSys.appendingPathComponent("class")
    }
}

public struct PlatformInfo: Identifiable, Equatable {
    public let id = UUID()
    public var platform: String
    public var family: String
    public var version: String
}

public struct CPUTimesStat: Identifiable, Equatable {
    public let id = UUID()
    public var cpu: String = ""
    var user: Double = 0.0
    var system: Double = 0.0
    var idle: Double = 0.0
    var nice: Double = 0.0
    var iowait: Double = 0.0
    var irq: Double = 0.0
    var softirq: Double = 0.0
    var steal: Double = 0.0
    var guest: Double = 0.0
    var guestNice: Double = 0.0
    public var percent: Double = 0.0
    public var userPercent: Double = 0.0
    public var systemPercent: Double = 0.0
    public var idlePercent: Double = 0.0
    public var nicePercent: Double = 0.0
    public var iowaitPercent: Double = 0.0
    public var irqPercent: Double = 0.0
    public var softirqPercent: Double = 0.0
    public var stealPercent: Double = 0.0
    public var guestPercent: Double = 0.0
    public var guestNicePercent: Double = 0.0
}

public extension CPUTimesStat {
    static func calculateUsage(t1: CPUTimesStat, t2: CPUTimesStat) -> CPUTimesStat {
        var result = t2
        let deltaTotal = t2.total - t1.total

        guard deltaTotal > 0 else { return result }

        /// 计算辅助函数，确保范围在 0-1
        func getPercent(_ delta: Double) -> Double {
            min(1.0, max(0.0, delta / deltaTotal))
        }

        // 计算百分比
        result.userPercent = getPercent(t2.user - t1.user)
        result.systemPercent = getPercent(t2.system - t1.system)
        result.idlePercent = getPercent(t2.idle - t1.idle)
        result.nicePercent = getPercent(t2.nice - t1.nice)
        result.iowaitPercent = getPercent(t2.iowait - t1.iowait)
        result.irqPercent = getPercent(t2.irq - t1.irq)
        result.softirqPercent = getPercent(t2.softirq - t1.softirq)
        result.stealPercent = getPercent(t2.steal - t1.steal)

        // Guest 占比通常是相对于 user 的细分指标
        result.guestPercent = getPercent(t2.guest - t1.guest)

        // 最终总使用率
        let deltaBusy = t2.busy - t1.busy
        result.percent = getPercent(deltaBusy)

        return result
    }

    var busy: Double {
        total - idle - iowait
    }

    var total: Double {
        user + nice + system + idle + iowait + irq + softirq + steal
    }
}

public struct CPUInfoStat: Identifiable, Equatable {
    public let id = UUID()

    public var cpu: Int = -1
    public var vendorID: String = ""
    public var family: String = ""
    public var model: String = ""
    public var stepping: Int = 0
    public var physicalID: String = ""
    public var coreID: String = ""
    public var modelName: String = ""
    public var mhz: Double = 0.0
//    public var mhzMax: Double = 0.0
//    public var mhzMin: Double = 0.0
    public var cacheSize: Int = 0
    public var flags: [String] = []
    public var microcode: String = ""
}

public struct AvgStat: Identifiable, Equatable {
    public let id = UUID()
    public var load1: Double = 0.0
    public var load5: Double = 0.0
    public var load15: Double = 0.0
    // public var cpu: Int = 0
}

public struct VirtualMemoryStat: Identifiable, Equatable {
    public let id = UUID()
    public var total: Int64 = 0
    public var available: Int64 = 0
    public var used: Int64 = 0
    public var usedPercent: Double = 0.0
    public var free: Int64 = 0
    public var active: Int64 = 0
    public var inactive: Int64 = 0
    public var wired: Int64 = 0
    public var laundry: Int64 = 0
    public var buffers: Int64 = 0
    public var cached: Int64 = 0
    public var writeBack: Int64 = 0
    public var dirty: Int64 = 0
    public var writeBackTmp: Int64 = 0
    public var shared: Int64 = 0
    public var slab: Int64 = 0
    public var sreclaimable: Int64 = 0
    public var sunreclaim: Int64 = 0
    public var pageTables: Int64 = 0
    public var swapCached: Int64 = 0
    public var commitLimit: Int64 = 0
    public var committedAS: Int64 = 0
    public var highTotal: Int64 = 0
    public var highFree: Int64 = 0
    public var lowTotal: Int64 = 0
    public var lowFree: Int64 = 0
    public var swapTotal: Int64 = 0
    public var swapFree: Int64 = 0
    public var mapped: Int64 = 0
    public var vmallocTotal: Int64 = 0
    public var vmallocUsed: Int64 = 0
    public var vmallocChunk: Int64 = 0
    public var hugePagesTotal: Int64 = 0
    public var hugePagesFree: Int64 = 0
    public var hugePagesRsvd: Int64 = 0
    public var hugePagesSurp: Int64 = 0
    public var hugePageSize: Int64 = 0
    public var anonHugePages: Int64 = 0

    public var activeFile: Int64 = 0
    public var inactiveFile: Int64 = 0
    public var activeAnon: Int64 = 0
    public var inactiveAnon: Int64 = 0
    public var unevictable: Int64 = 0
}

public struct SystemStat: Identifiable, Equatable {
    public let id = UUID()
    public var context: Int = 0
    public var bootTime: Int = 0
    public var processes: Int64 = 0
    public var processesRunning: Int64 = 0
    public var processesBlocked: Int64 = 0
}

public enum NetIPVersion: String {
    case v4 = "IPv4"
    case v6 = "IPv6"
}

public enum NetProtocol: String {
    case tcp = "TCP"
    case udp = "UDP"
}

public enum NetConnState: String {
    case established = "ESTABLISHED"
    case synSent = "SYN_SENT"
    case synRecv = "SYN_RECV"
    case finWait1 = "FIN_WAIT1"
    case finWait2 = "FIN_WAIT2"
    case timeWait = "TIME_WAIT"
    case close = "CLOSE"
    case closeWait = "CLOSE_WAIT"
    case lastAck = "LAST_ACK"
    case listen = "LISTEN"
    case closing = "CLOSING"
    case unknown = "UNKNOWN"
}

public struct NetConnStat {
    public var ipVersion: NetIPVersion = .v4
    public var `protocol`: NetProtocol = .tcp
    public var state: NetConnState = .unknown
    public var count: Int64 = 0
}

public struct NetIOCountersStat: Identifiable, Equatable {
    public let id = UUID()

    public var name: String = ""
    public var bytesSent: Int64 = 0
    public var bytesRecv: Int64 = 0
    public var packetsSent: Int64 = 0
    public var packetsRecv: Int64 = 0
    public var errin: Int64 = 0
    public var errout: Int64 = 0
    public var dropin: Int64 = 0
    public var dropout: Int64 = 0
    public var fifoin: Int64 = 0
    public var fifoout: Int64 = 0
    public var bytesSentTotal: Int64 = 0
    public var bytesRecvTotal: Int64 = 0

    public var mtu: Int64 = 0
    public var speed: Int64 = 0
    public var address: String = ""
}

/// 磁盘空间与挂载
public struct DiskUsageStat {
    public var device: String = "" // 设备名，如 /dev/sda1
    public var mountPoint: String = "" // 挂载点，如 /
    public var fsType: String = "" // 文件系统，如 ext4, xfs
    public var total: Int64 = 0 // 总量 (Bytes)
    public var used: Int64 = 0 // 已用 (Bytes)
    public var free: Int64 = 0 // 剩余 (Bytes)
    public var usedPercent: Double = 0 // 使用率 (0.0~1.0)
}

public struct DiskIOCountersStat: Identifiable, Equatable {
    public let id = UUID()

    public var readCount: Int64 = 0
    public var mergedReadCount: Int64 = 0
    public var writeCount: Int64 = 0
    public var mergedWriteCount: Int64 = 0
    public var readBytes: Int64 = 0
    public var writeBytes: Int64 = 0
    public var readTime: Int64 = 0
    public var writeTime: Int64 = 0
    public var iopsInProgress: Int64 = 0
    public var ioTime: Int64 = 0
    public var weightedIO: Int64 = 0
    public var name: String = ""
    public var readBytesTotal: Int64 = 0
    public var writeBytesTotal: Int64 = 0
    public var size: Int64 = 0
}

public struct TemperatureStat: Identifiable, Equatable {
    public let id = UUID()
    public var name: String = ""
    public var label: String = ""
    public var temperature: Double = 0.0
    public var sensorHigh: Double = 0.0
    public var sensorCritical: Double = 0.0
    public var cpu: Bool = false
}

public struct SystemProcess: Identifiable, Equatable {
    public var id: Int {
        pid
    }

    public var pid: Int = 0
    public var name: String = ""
    public var status: ProcessStatus = .UnknownState
    public var user: Double = 0.0
    public var system: Double = 0.0
    public var childrenUser: Double = 0.0
    public var childrenSystem: Double = 0.0
    public var iowait: Double = 0.0
    public var cpuNum: Int = 0
    public var memory: Int64 = 0
    public var createTime: Double = 0
    public var percent: Double = 0.0

    public static func calculatePercent(t1: SystemProcess, t2: SystemProcess, delta: Double) -> Double {
        let delta_proc = (t2.user - t1.user) + (t2.system - t1.system)
        return ((delta_proc / delta) * 100) * Double(t1.cpuNum)
    }
}

public struct HostPlatform: Identifiable, Equatable {
    public let id = UUID()
    public var platform: String = ""
    public var version: String = ""
    // public var dns: [String] = []
}

public enum ProcessStatus: String, CaseIterable {
    case Daemon, Blocked, Detached, Idle, Lock, Orphan, Running, Sleep, Stop, Wait, System, Zombie, UnknownState

    public init(rawValue: String) {
        switch rawValue {
        case "A":
            self = .Daemon
        case "D", "U":
            self = .Blocked
        case "E":
            self = .Detached
        case "I":
            self = .Idle
        case "L":
            self = .Lock
        case "O":
            self = .Orphan
        case "R":
            self = .Running
        case "S":
            self = .Sleep
        case "T", "t":
            self = .Stop
        case "W":
            self = .Wait
        case "Y":
            self = .System
        case "Z":
            self = .Zombie
        default:
            self = .UnknownState
        }
    }
}

public struct DockerStat: Identifiable, Equatable {
    public var id: String {
        containerID
    }

    public let containerID: String
    public let name: String
    public let image: String
    public let status: String
    public let running: Bool
    public let createdAt: String
    public let ports: String
}

public struct DockerStats: Identifiable, Equatable {
    public var id: String {
        containerID
    }

    public let containerID: String
    public let name: String
    public let CPUPerc: String
    public let memPerc: String
    public let netIO: String
    public let blockIO: String
}
