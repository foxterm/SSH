// FoxTerm | LinuxStats.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation

extension Machine {
    // MARK: - 标准 Linux 虚拟文件系统路径定义

    /// 定义主机的等效目录路径
    var hostEtc: String {
        "/etc"
    }

    /// 定义主机的进程管理目录路径
    var hostProc: String {
        "/proc"
    }

    /// 定义主机的内核虚拟文件系统目录路径
    var hostSys: String {
        "/sys"
    }

    /// 定义主机的设备节点目录路径
    var hostDev: String {
        "/dev"
    }

    /// 定义主机的类设备目录路径
    var hostClass: String {
        hostSys.appendingPathComponent("class")
    }
}

/// 表示平台信息的数据结构
public struct PlatformInfo: Identifiable, Equatable {
    public let id = UUID()

    /// 平台名称
    public var platform: String

    /// 平台家族
    public var family: String

    /// 平台版本
    public var version: String
}

/// CPU 时间统计的数据结构
public struct CPUTimesStat: Identifiable, Equatable {
    public let id = UUID()

    /// CPU 标签
    public var cpu: String = ""

    /// 用户时间 (秒)
    var user: Double = 0.0

    /// 系统时间 (秒)
    var system: Double = 0.0

    /// 空闲时间 (秒)
    var idle: Double = 0.0

    /// 调度时间 (秒)
    var nice: Double = 0.0

    /// I/O 队列等待时间 (秒)
    var iowait: Double = 0.0

    /// 中断处理时间 (秒)
    var irq: Double = 0.0

    /// 软中断处理时间 (秒)
    var softirq: Double = 0.0

    /// 窃取虚拟 CPU 时间 (秒)
    var steal: Double = 0.0

    /// 客户机时间 (秒)
    var guest: Double = 0.0

    /// 客户机调度时间 (秒)
    var guestNice: Double = 0.0

    /// 总使用率
    public var percent: Double = 0.0

    /// 用户百分比
    public var userPercent: Double = 0.0

    /// 系统百分比
    public var systemPercent: Double = 0.0

    /// 空闲百分比
    public var idlePercent: Double = 0.0

    /// 调度百分比
    public var nicePercent: Double = 0.0

    /// I/O 队列等待百分比
    public var iowaitPercent: Double = 0.0

    /// 中断处理百分比
    public var irqPercent: Double = 0.0

    /// 软中断处理百分比
    public var softirqPercent: Double = 0.0

    /// 窃取虚拟 CPU 百分比
    public var stealPercent: Double = 0.0

    /// 客户机百分比
    public var guestPercent: Double = 0.0

    /// 客户机调度百分比
    public var guestNicePercent: Double = 0.0

    /// 计算 CPU 使用率的方法
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

    /// 计算忙碌时间 (user + nice + system - idle - iowait)
    var busy: Double {
        total - idle - iowait
    }

    /// 计算总时间 (user + nice + system + idle + iowait + irq + softirq + steal)
    var total: Double {
        user + nice + system + idle + iowait + irq + softirq + steal
    }
}

/// CPU 详细信息的数据结构
public struct CPUInfoStat: Identifiable, Equatable {
    public let id = UUID()

    /// CPU 标签
    public var cpu: Int = -1

    /// CPU 厂商 ID
    public var vendorID: String = ""

    /// CPU 家族
    public var family: String = ""

    /// CPU 模型
    public var model: String = ""

    /// CPU 步进编号
    public var stepping: Int = 0

    /// 物理 ID
    public var physicalID: String = ""

    /// 核心 ID
    public var coreID: String = ""

    /// 模型名称
    public var modelName: String = ""

    /// CPU 频率 (MHz)
    public var mhz: Double = 0.0

    // 哈希缓存大小 (KB)
    // public var cacheSize: Int = 0

    /// CPU 标志列表
    public var flags: [String] = []

    /// 微代码版本
    public var microcode: String = ""
}

/// 表示平均负载统计数据的数据结构
public struct AvgStat: Identifiable, Equatable {
    public let id = UUID()

    /// 1 分钟内的平均负载
    public var load1: Double = 0.0

    /// 5 分钟内的平均负载
    public var load5: Double = 0.0

    /// 15 分钟内的平均负载
    public var load15: Double = 0.0
}

/// 表示虚拟内存统计数据的数据结构
public struct VirtualMemoryStat: Identifiable, Equatable {
    public let id = UUID()

    /// 总虚拟内存大小 (字节)
    public var total: Int64 = 0

    /// 可用虚拟内存大小 (字节)
    public var available: Int64 = 0

    /// 已用虚拟内存大小 (字节)
    public var used: Int64 = 0

    /// 已用虚拟内存百分比
    public var usedPercent: Double = 0.0

    /// 空闲虚拟内存大小 (字节)
    public var free: Int64 = 0

    /// 激活的虚拟内存大小 (字节)
    public var active: Int64 = 0

    /// 非激活的虚拟内存大小 (字节)
    public var inactive: Int64 = 0

    /// 被占用的虚拟内存大小 (字节)
    public var wired: Int64 = 0

    /// 等待写回的虚拟内存大小 (字节)
    public var laundry: Int64 = 0

    /// 缓冲区使用的虚拟内存大小 (字节)
    public var buffers: Int64 = 0

    /// 缓存区使用的虚拟内存大小 (字节)
    public var cached: Int64 = 0

    /// 正在写回的虚拟内存大小 (字节)
    public var writeBack: Int64 = 0

    /// 被标记为脏页的虚拟内存大小 (字节)
    public var dirty: Int64 = 0

    /// 正在写回临时区的虚拟内存大小 (字节)
    public var writeBackTmp: Int64 = 0

    /// 共享的虚拟内存大小 (字节)
    public var shared: Int64 = 0

    /// 索引页表使用的虚拟内存大小 (字节)
    public var slab: Int64 = 0

    /// 可重新回收的索引页表使用的虚拟内存大小 (字节)
    public var sreclaimable: Int64 = 0

    /// 不可重新回收的索引页表使用的虚拟内存大小 (字节)
    public var sunreclaim: Int64 = 0

    /// 页面表使用的虚拟内存大小 (字节)
    public var pageTables: Int64 = 0

    /// 命名空间缓存区使用的虚拟内存大小 (字节)
    public var swapCached: Int64 = 0

    /// 提交限制的虚拟内存大小 (字节)
    public var commitLimit: Int64 = 0

    /// 已提交的地址空间大小 (字节)
    public var committedAS: Int64 = 0

    /// 高内存部分的总大小 (字节)
    public var highTotal: Int64 = 0

    /// 高内存部分的空闲大小 (字节)
    public var highFree: Int64 = 0

    /// 低内存部分的总大小 (字节)
    public var lowTotal: Int64 = 0

    /// 低内存部分的空闲大小 (字节)
    public var lowFree: Int64 = 0

    /// 总交换空间大小 (字节)
    public var swapTotal: Int64 = 0

    /// 空闲交换空间大小 (字节)
    public var swapFree: Int64 = 0

    /// 映射的虚拟内存大小 (字节)
    public var mapped: Int64 = 0

    /// 虚拟内存区域使用的总字节数
    public var vmallocTotal: Int64 = 0

    /// 已分配的虚拟内存区域使用的总字节数
    public var vmallocUsed: Int64 = 0

    /// 虚拟内存区域使用的空闲块大小 (字节)
    public var vmallocChunk: Int64 = 0

    /// 大页内存的总数量
    public var hugePagesTotal: Int64 = 0

    /// 空闲的大页内存数量
    public var hugePagesFree: Int64 = 0

    /// 预留的大页内存数量
    public var hugePagesRsvd: Int64 = 0

    /// 超额的大页内存数量
    public var hugePagesSurp: Int64 = 0

    /// 大页内存的大小 (字节)
    public var hugePageSize: Int64 = 0

    /// 匿名大页内存使用的总字节数
    public var anonHugePages: Int64 = 0

    /// 文件系统上活动的文件的虚拟内存使用量（字节）
    public var activeFile: Int64 = 0

    /// 文件系统上非活动的文件的虚拟内存使用量（字节）
    public var inactiveFile: Int64 = 0

    /// 匿名空间中活动的虚拟内存使用量（字节）
    public var activeAnon: Int64 = 0

    /// 匿名空间中非活动的虚拟内存使用量（字节）
    public var inactiveAnon: Int64 = 0

    /// 不可被驱逐的虚拟内存使用量（字节）
    public var unevictable: Int64 = 0
}

/// 表示系统统计信息的数据结构
public struct SystemStat: Identifiable, Equatable {
    public let id = UUID()

    /// 上下文切换次数
    public var context: Int = 0

    /// 系统启动时间 (秒)
    public var bootTime: Int = 0

    /// 当前运行的进程数
    public var processes: Int64 = 0

    /// 当前正在运行的进程数
    public var processesRunning: Int64 = 0

    /// 当前阻塞的进程数
    public var processesBlocked: Int64 = 0
}

/// 表示网络 IP 版本的数据结构
public enum NetIPVersion: String {
    case v4 = "IPv4"
    case v6 = "IPv6"
}

/// 表示网络协议的数据结构
public enum NetProtocol: String {
    case tcp = "TCP"
    case udp = "UDP"
}

/// 枚举了网络连接的状态，根据其字符串表示进行匹配。
/// 这些状态在 `netstat` 输出中很常见，表示 TCP/IP 握手和数据传输的不同阶段。
public enum NetConnState: String {
    /// 连接已经成功建立，本地与远程主机之间建立了连接。
    case established = "ESTABLISHED"

    /// 客户端已发送连接请求，但尚未收到服务器的确认。
    case synSent = "SYN_SENT"

    /// 服务器已接收客户端的连接请求，并等待发送确认来完成握手。
    case synRecv = "SYN_RECV"

    /// 本地主机正在关闭连接过程中，收到远程主机发送的 FIN 包。
    case finWait1 = "FIN_WAIT1"

    /// 两个 parties 都已经收到 FIN 包，但连接尚未完全关闭，因为还有数据或响应未处理。
    case finWait2 = "FIN_WAIT2"

    /// 在响应远程 party 的 FIN 时，本地主机发送了一个最终的 ACK，并在等待其确认以完成关闭过程。
    case timeWait = "TIME_WAIT"

    /// 一个 party 已经关闭连接，但连接仍然保持打开状态，直到双方都确认连接完全关闭。
    case close = "CLOSE"

    /// 本地主机收到远程主机发送的 FIN 包，并等待其确认以完成关闭过程。
    case closeWait = "CLOSE_WAIT"

    /// 本地主机在响应 remote party 的 FIN 时发送了一个最终的 ACK，但尚未收到确认来确认连接完全关闭。
    case lastAck = "LAST_ACK"

    /// 服务器正在等待客户端确认其 own FIN 包以完成连接终止过程。
    case listen = "LISTEN"

    /// 两个 parties 都在关闭连接过程中，但还没有发送 final 的 ACK 确认连接完全关闭。
    case closing = "CLOSING"

    /// 连接状态未知或未被识别。
    case unknown = "UNKNOWN"
}

/// 表示网络连接统计信息的数据结构
public struct NetConnStat: Identifiable, Equatable {
    public let id = UUID()
    /// IP 版本
    public var ipVersion: NetIPVersion = .v4

    /// 协议类型
    public var `protocol`: NetProtocol = .tcp

    /// 连接状态
    public var state: NetConnState = .unknown

    /// 连接数量
    public var count: Int64 = 0
}

/// 表示网络 IO 计数器统计信息的数据结构
public struct NetIOCountersStat: Identifiable, Equatable {
    public let id = UUID()

    /// 网络接口名称
    public var name: String = ""

    /// 发送的字节数 (字节)
    public var bytesSent: Int64 = 0

    /// 接收的字节数 (字节)
    public var bytesRecv: Int64 = 0

    /// 发送的数据包数
    public var packetsSent: Int64 = 0

    /// 接收的数据包数
    public var packetsRecv: Int64 = 0

    /// 输入错误数
    public var errin: Int64 = 0

    /// 输出错误数
    public var errout: Int64 = 0

    /// 输入丢弃的字节数
    public var dropin: Int64 = 0

    /// 输出丢弃的字节数
    public var dropout: Int64 = 0

    /// 队列输入的字节数
    public var fifoin: Int64 = 0

    /// 队列输出的字节数
    public var fifoout: Int64 = 0

    /// 发送的总字节数 (字节)
    public var bytesSentTotal: Int64 = 0

    /// 接收的总字节数 (字节)
    public var bytesRecvTotal: Int64 = 0

    /// MTU 大小
    public var mtu: Int64 = 0

    /// 连接速度 (bps)
    public var speed: Int64 = 0

    /// 网络接口地址
    public var address: String = ""
}

/// 表示磁盘空间与挂载统计信息的数据结构
public struct DiskUsageStat {
    /// 设备名，如 /dev/sda1
    public var device: String = ""

    /// 挂载点，如 /
    public var mountPoint: String = ""

    /// 文件系统类型，如 ext4, xfs
    public var fsType: String = ""

    /// 总量 (字节)
    public var total: Int64 = 0

    /// 已用 (字节)
    public var used: Int64 = 0

    /// 剩余 (字节)
    public var free: Int64 = 0

    /// 使用率 (0.0~1.0)
    public var usedPercent: Double = 0
}

/// 表示磁盘 IO 计数器统计信息的数据结构
public struct DiskIOCountersStat: Identifiable, Equatable {
    public let id = UUID()

    /// 读取次数
    public var readCount: Int64 = 0

    /// 合并的读取次数
    public var mergedReadCount: Int64 = 0

    /// 写入次数
    public var writeCount: Int64 = 0

    /// 合并的写入次数
    public var mergedWriteCount: Int64 = 0

    /// 读取字节数 (字节)
    public var readBytes: Int64 = 0

    /// 写入字节数 (字节)
    public var writeBytes: Int64 = 0

    /// 读取时间 (毫秒)
    public var readTime: Int64 = 0

    /// 写入时间 (毫秒)
    public var writeTime: Int64 = 0

    /// 正在进行的 I/O 操作数
    public var iopsInProgress: Int64 = 0

    /// 总 I/O 时间 (毫秒)
    public var ioTime: Int64 = 0

    /// 加权的 I/O 时间 (毫秒)
    public var weightedIO: Int64 = 0

    /// 网络接口名称
    public var name: String = ""

    /// 读取的总字节数 (字节)
    public var readBytesTotal: Int64 = 0

    /// 写入的总字节数 (字节)
    public var writeBytesTotal: Int64 = 0

    /// 接口大小 (字节)
    public var size: Int64 = 0
}

/// 表示温度统计信息的数据结构
public struct TemperatureStat: Identifiable, Equatable {
    public let id = UUID()

    /// 设备名称
    public var name: String = ""

    /// 标签
    public var label: String = ""

    /// 温度值 (摄氏度)
    public var temperature: Double = 0.0

    /// 最高温度阈值 (摄氏度)
    public var sensorHigh: Double = 0.0

    /// 危急温度阈值 (摄氏度)
    public var sensorCritical: Double = 0.0

    /// 是否为 CPU 温度
    public var cpu: Bool = false
}

/// 表示系统进程信息的数据结构
public struct SystemProcess: Identifiable, Equatable {
    public var id: Int {
        pid
    }

    /// 进程 ID
    public var pid: Int = 0

    /// 进程名称
    public var name: String = ""

    /// 状态
    public var status: ProcessStatus = .UnknownState

    /// 用户 CPU 时间 (秒)
    public var user: Double = 0.0

    /// 系统 CPU 时间 (秒)
    public var system: Double = 0.0

    /// 子进程用户 CPU 时间 (秒)
    public var childrenUser: Double = 0.0

    /// 子进程系统 CPU 时间 (秒)
    public var childrenSystem: Double = 0.0

    /// I/O 等待时间 (秒)
    public var iowait: Double = 0.0

    /// 进程所在 CPU 核心
    public var cpuNum: Int = 0

    /// 内存使用量 (字节)
    public var memory: Int64 = 0

    /// 创建时间 (秒)
    public var createTime: Double = 0

    /// 总 CPU 使用率
    public var percent: Double = 0.0

    /// 计算进程总 CPU 使用率的方法
    public static func calculatePercent(t1: SystemProcess, t2: SystemProcess, delta: Double)
        -> Double
    {
        let delta_proc = (t2.user - t1.user) + (t2.system - t1.system)
        return ((delta_proc / delta) * 100) * Double(t1.cpuNum)
    }
}

/// 表示主机平台信息的数据结构
public struct HostPlatform: Identifiable, Equatable {
    public let id = UUID()

    /// 平台名称
    public var platform: String = ""

    /// 平台版本
    public var version: String = ""
}

/// 表示进程状态的枚举
public enum ProcessStatus: String, CaseIterable {
    ///  进程状态的枚举值
    /// - Daemon: 守护进程
    /// - Blocked: 阻塞状态
    /// - Detached: 分离状态
    /// - Idle: 空闲状态
    /// - Lock: 锁定状态
    /// - Orphan: 孤儿进程
    /// - Running: 运行状态
    /// - Sleep: 睡眠状态
    /// - Stop: 停止状态
    /// - Wait: 等待状态
    /// - System: 系统进程
    /// - Zombie: 孤子进程（僵尸）
    /// - UnknownState: 未知状态
    case Daemon, Blocked, Detached, Idle, Lock, Orphan, Running, Sleep, Stop, Wait, System, Zombie,
         UnknownState

    /// 根据字符串初始化进程状态的方法
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

/// Docker 容器统计信息的数据结构
public struct DockerStat: Identifiable, Equatable {
    public var id: String {
        containerID
    }

    /// 容器 ID
    public let containerID: String

    /// 容器名称
    public let name: String

    /// 镜像名称
    public let image: String

    /// 容器状态
    public let status: String

    /// 是否正在运行
    public let running: Bool

    /// 创建时间 (字符串格式)
    public let createdAt: String

    /// 端口信息
    public let ports: String
}

/// Docker 统计信息的数据结构
public struct DockerStats: Identifiable, Equatable {
    public var id: String {
        containerID
    }

    /// 容器 ID
    public let containerID: String

    /// 容器名称
    public let name: String

    /// CPU 使用率 (百分比)
    public let CPUPerc: String

    /// 内存使用率 (百分比)
    public let memPerc: String

    /// 网络 I/O 信息
    public let netIO: String

    /// 块设备 I/O 信息
    public let blockIO: String
}

/// GPU 统计信息的数据结构
public struct GPUStat: Identifiable, Equatable {
    public let id = UUID()

    /// GPU 索引号
    public let index: Int

    /// GPU 名称
    public let name: String

    /// GPU 内存总大小 (GB)
    public let memoryTotal: Double

    /// GPU 已使用内存大小 (GB)
    public let memoryUsed: Double

    /// GPU 利用率 (%)
    public let utilizationGPU: Double

    /// GPU 温度 (摄氏度)
    public let temperatureGPU: Double

    /// GPU 功耗 (瓦特)
    public let powerDraw: Double

    /// GPU 功耗限制 (瓦特)
    public let powerLimit: Double
}

/// AMD SMI 响应的数据结构
struct AMDSMIResponse: Decodable {
    let devices: [AMDSMIDevice]
}

/// AMD SMI 设备的数据结构
struct AMDSMIDevice: Decodable {
    /// GPU 设备的 ID
    let gpu_id: Int

    /// GPU 的型号名称，可选
    let model_name: String?

    /// GPU 的总显存
    let vram_total: String

    /// 已使用的显存
    let vram_used: String

    /// GPU 的负载百分比
    let gpu_load: Double

    /// GPU 当前的温度
    let temperature: Double

    /// 使用可选类型，方便后面做回退逻辑
    /// 平均socket 功耗（瓦特），可选
    let average_socket_power: Double?

    /// 当前socket 功耗（瓦特），可选
    let current_socket_power: Double?

    /// 最大功耗限制（瓦特），可选
    let power_cap: Double?

    /// 功耗限制（瓦特），可选
    let power_limit: Double?

    enum CodingKeys: String, CodingKey {
        case gpu_id = "device_id"
        case model_name = "product_name"
        case vram_total
        case vram_used
        case gpu_load = "gpu_utilization"
        case temperature = "temperature_edge"

        /// 映射所有可能的功耗字段
        case average_socket_power, current_socket_power, power_cap, power_limit
    }
}

/// GPU 品牌标识符
public enum GPU: String, CaseIterable {
    case nvidia
    case amd
    case rocm
    case intel
}
