// FoxTerm | Sensors.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

public extension Machine {
    func getTemp() async -> [TemperatureStat]? {
        let gatherCmd = """
        /bin/sh -c "found=0;
        if [ -d /sys/class/hwmon ]; then
            for d in /sys/class/hwmon/hwmon*; do
                [ -d \\"\\$d\\" ] || continue;
                name=\\$(cat \\"\\$d/name\\" 2>/dev/null || echo \\"unknown\\");
                for input in \\"\\$d\\"/temp*_input; do
                    [ -f \\"\\$input\\" ] || continue;
                    val=\\$(cat \\"\\$input\\" 2>/dev/null);
                    if [ -n \\"\\$val\\" ] && [ \\"\\$val\\" -ne 0 ]; then
                        base=\\${input%_input};
                        echo \\"hw|\\$name|\\$val|\\$(cat \\"\\${base}_crit\\" 2>/dev/null || echo 0)|\\$(cat \\"\\${base}_max\\" 2>/dev/null || echo 0)|\\$(cat \\"\\${base}_label\\" 2>/dev/null || echo \\"\\")\\";
                        found=1;
                    fi;
                done;
            done;
        fi;
        if [ \\"\\$found\\" -eq 0 ] && [ -d /sys/class/thermal ]; then
            for d in /sys/class/thermal/thermal_zone*; do
                [ -d \\"\\$d\\" ] || continue;
                type=\\$(cat \\"\\$d/type\\" 2>/dev/null || echo \\"unknown\\");
                temp=\\$(cat \\"\\$d/temp\\" 2>/dev/null || echo 0);
                if [ \\"\\$temp\\" -ne 0 ]; then
                    echo \\"tz|\\$type|\\$temp|0|0|none\\";
                fi;
            done;
        fi"
        """

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
