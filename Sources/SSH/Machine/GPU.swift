// FoxTerm | GPU.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

extension Machine {
    /// 异步获取 GPU 统计信息，使用 `lspci` 检测硬件，并根据不同的 GPU 型号调用适当的工具。
    public func getGPUTimesStat() async -> [GPUStat]? {
        // 用于检测硬件类型的命令，过滤掉非显卡设备
        if gpu == nil {
            guard
                let bin = await ssh.exec(
                    "which nvidia-smi || which amd-smi || which rocm-smi || which xpu-smi"
                )?.string?
                .trim,
                !bin.isEmpty
            else {
                return nil
            }
            if bin.hasSuffix("nvidia-smi") {
                gpu = .nvidia
            } else if bin.hasSuffix("amd-smi") {
                gpu = .amd
            } else if bin.hasSuffix("rocm-smi") {
                gpu = .rocm
            } else if bin.hasSuffix("xpu-smi") {
                gpu = .intel
            }

            smibin = bin
        }
        guard let gpu else {
            return nil
        }

        switch gpu {
        case .nvidia:
            return await fetchNvidiaSmiStats()
        case .amd:
            return await fetchAmdSmiStats()
        case .rocm:
            return await fetchRocmSmiStats()
        case .intel:
            return await fetchIntelXpuStats()
        }
    }

    private func fetchNvidiaSmiStats() async -> [GPUStat]? {
        let nVidiaCmd =
            "\(smibin) --query-gpu=index,name,memory.total,memory.used,utilization.gpu,temperature.gpu,power.draw,power.limit,enforced.power.limit --format=csv,noheader,nounits"

        guard let output = await ssh.exec(nVidiaCmd)?.string?.lines, !output.isEmpty else {
            return nil
        }

        return output.compactMap { line in
            let fields = line.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard fields.count >= 9 else { return nil }

            let pLimit = parseNA(fields[7]) ?? parseNA(fields[8]) ?? 0.0
            let pDraw = parseNA(fields[6]) ?? 0.0
            return GPUStat(
                index: Int(fields[0]) ?? 0,
                name: fields[1],
                memoryTotal: (Double(fields[2]) ?? 0) * 0x100000,
                memoryUsed: (Double(fields[3]) ?? 0) * 0x100000,
                utilizationGPU: Double(fields[4]) ?? 0,
                temperatureGPU: Double(fields[5]) ?? 0,
                powerDraw: pDraw,
                powerLimit: pLimit
            )
        }
    }

    private func parseNA(_ value: String) -> Double? {
        if value.contains("N/A") {
            return nil
        }
        return Double(value)
    }

    private func fetchRocmSmiStats() async -> [GPUStat]? {
        guard let output = await ssh.exec("\(smibin) -a --showmeminfo vram --json")?.string,
              let data = output.data(using: .utf8)
        else { return nil }

        do {
            let rawDict =
                try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] ?? [:]
            return rawDict.compactMap { key, val in
                guard let index = Int(key.replacingOccurrences(of: "card", with: "")) else {
                    return nil
                }
                return GPUStat(
                    index: index,
                    name: "AMD GPU \(index)",
                    memoryTotal: parseToBytes(
                        val["VRAM Total Memory (B)"] as? String ?? val["vram_total"] as? String
                    ),
                    memoryUsed: parseToBytes(
                        val["VRAM Total Used Memory (B)"] as? String ?? val["vram_used"]
                            as? String
                    ),
                    utilizationGPU: Double(val["GPU use (%)"] as? String ?? "0") ?? 0,
                    temperatureGPU: Double(
                        val["Temperature (Sensor edge) (C)"] as? String ?? "0"
                    ) ?? 0,
                    powerDraw: Double(
                        val["Average Graphics Package Power (W)"] as? String ?? "0"
                    ) ?? 0.0,
                    powerLimit: Double(val["Max Graphics Package Power (W)"] as? String ?? "0")
                        ?? 0.0
                )
            }
        } catch {
            return nil
        }
    }

    private func fetchAmdSmiStats() async -> [GPUStat]? {
        guard let output = await ssh.exec("\(smibin) metric --json")?.string,
              let data = output.data(using: .utf8)
        else { return nil }

        do {
            let decoder = JSONDecoder()
            let devices = try decoder.decode(AMDSMIResponse.self, from: data).devices
            return devices.map { dev in
                GPUStat(
                    index: dev.gpu_id,
                    name: dev.model_name ?? "AMD GPU",
                    memoryTotal: parseToBytes(dev.vram_total),
                    memoryUsed: parseToBytes(dev.vram_used),
                    utilizationGPU: dev.gpu_load,
                    temperatureGPU: dev.temperature,
                    powerDraw: dev.average_socket_power ?? dev.current_socket_power ?? 0.0,
                    powerLimit: dev.power_cap ?? dev.power_limit ?? 0.0
                )
            }

        } catch {
            return nil
        }
    }

    /// 增强版解析：支持带单位字符串、纯数字字符串、甚至直接是数字类型
    private func parseToBytes(_ input: Any?) -> Double {
        let str: String
        if let s = input as? String {
            str = s.lowercased().trim
        } else if let d = input as? Double {
            return d
        } else if let i = input as? Int {
            return Double(i)
        } else {
            return 0
        }

        if str.isEmpty {
            return 0
        }

        let pattern = "[0-9.]+"
        guard let range = str.range(of: pattern, options: .regularExpression),
              let value = Double(str[range])
        else { return 0 }

        if str.contains("gib") || str.contains("gb") {
            return value * 0x4000000
        }
        if str.contains("mib") || str.contains("mb") {
            return value * 0x10000
        }
        if str.contains("kib") || str.contains("kb") {
            return value * 0x400
        }
        return value
    }

    private func fetchIntelXpuStats() async -> [GPUStat]? {
        // -m 0,1,5,18,22 分别对应: GPU Util, GPU Temp, VRAM Used, VRAM Total, Power
        // -n 1 表示只采样一次, -j 表示 JSON 格式
        let cmd = "\(smibin) dump -m 0,1,5,18,22 -n 1 -j"

        guard let output = await ssh.exec(cmd)?.string,
              let data = output.data(using: .utf8)
        else { return nil }

        do {
            // xpu-smi 的 JSON 结构通常包含 "device_list"
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let deviceList = json?["device_list"] as? [[String: Any]] else { return nil }

            return deviceList.compactMap { dev in
                guard let deviceId = dev["device_id"] as? Int,
                      let dataList = dev["data_list"] as? [[String: Any]],
                      let metrics = dataList.first
                else { return nil }
                return GPUStat(
                    index: deviceId,
                    name: "Intel GPU \(deviceId)",
                    memoryTotal: parseToBytes(metrics["memory_total"]),
                    memoryUsed: parseToBytes(metrics["memory_used"]),
                    utilizationGPU: Double(parseToDouble(metrics["gpu_utilization"])),
                    temperatureGPU: Double(parseToDouble(metrics["gpu_temperature"])),
                    powerDraw: parseToDouble(metrics["power"]),
                    powerLimit: 0.0
                )
            }
        } catch {
            return nil
        }
    }

    /// 辅助工具：处理类似 "35.5 W" 或 "12 %" 的纯数值提取
    private func parseToDouble(_ input: Any?) -> Double {
        guard let s = input as? String else { return 0.0 }
        let pattern = "[0-9.]+"
        if let range = s.range(of: pattern, options: .regularExpression),
           let val = Double(s[range])
        {
            return val
        }
        return 0.0
    }
}
