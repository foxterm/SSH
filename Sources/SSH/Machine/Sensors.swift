// FoxTerm | Sensors.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    /// 采集远程主机的温度传感器数据
    ///
    /// 双通道探测：优先读取 `/sys/class/hwmon/hwmon*/temp*_input`，
    /// 无数据时回退到 `/sys/class/thermal/thermal_zone*/temp`。
    /// 自动根据传感器名称识别 CPU 温度（匹配 `coretemp`、`k10temp`、`cpu_thermal` 等关键词）。
    ///
    /// - Returns: 各温度传感器的 `TemperatureStat` 数组；采集失败返回 `nil`
    func getTemp() async -> [TemperatureStat]? {
        // 说明：
        // - 只接受纯整数(可带负号)的温度值；hwmon 某些节点可能返回空/非数字，若直接 `[ "$val" -ne 0 ]` 会报错并污染 stderr
        // - hwmon 与 thermal 双通道兜底，任一通道有数据即可
        let gatherCmd = #"found=0; if [ -d /sys/class/hwmon ]; then for d in /sys/class/hwmon/hwmon*; do [ -d "$d" ] || continue; name=$(cat "$d/name" 2>/dev/null || echo "unknown"); for input in "$d"/temp*_input; do [ -f "$input" ] || continue; val=$(cat "$input" 2>/dev/null); case "$val" in ''|*[!0-9-]*) continue ;; esac; [ "$val" -eq 0 ] && continue; base=${input%_input}; echo "hw|$name|$val|$(cat "${base}_crit" 2>/dev/null || echo 0)|$(cat "${base}_max" 2>/dev/null || echo 0)|$(cat "${base}_label" 2>/dev/null || echo "")"; found=1; done; done; fi; if [ "$found" -eq 0 ] && [ -d /sys/class/thermal ]; then for d in /sys/class/thermal/thermal_zone*; do [ -d "$d" ] || continue; type=$(cat "$d/type" 2>/dev/null || echo "unknown"); temp=$(cat "$d/temp" 2>/dev/null || echo 0); case "$temp" in ''|*[!0-9-]*) continue ;; esac; [ "$temp" -eq 0 ] && continue; echo "tz|$type|$temp|0|0|none"; done; fi"#

        let cpuKeywords = ["coretemp", "pkgtemp", "k10temp", "zenpower", "fam15h_power", "amd_energy", "cpu_thermal", "soc_thermal", "scpi_sensors", "cpu", "acpitz", "virt_temp", "package", "soc"]

        guard let output = await ssh.exec(gatherCmd)?.string?.lines else { return nil }

        return output.compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 6 else { return nil }

            let name = parts[1].lowercased()
            let tempRaw = Double(parts[2]) ?? 0
            let critRaw = Double(parts[3]) ?? 0
            let maxRaw = Double(parts[4]) ?? 0
            let label = parts[5].lowercased()

            if tempRaw == 0 {
                return nil
            }

            var t = TemperatureStat()
            t.name = name
            t.label = label
            t.temperature = tempRaw / 1000
            t.sensorCritical = critRaw > 0 ? critRaw / 1000 : 0
            t.sensorHigh = maxRaw > 0 ? maxRaw / 1000 : 0

            let nameMatch = cpuKeywords.contains { name.contains($0) }
            let labelMatch = label.contains("core") || label.contains("pkg") || label.contains("package")

            t.cpu = nameMatch || labelMatch
            return t
        }
    }
}
