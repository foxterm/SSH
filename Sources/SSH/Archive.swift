// FoxTerm | Archive.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh

public extension SSH {
    // MARK: - 核心压缩/解压接口

    /// 执行远程文件或目录的压缩操作
    /// - Parameters:
    ///   - sourcePath: 要压缩的源文件或目录路径 (例如 `/var/log/app`)
    ///   - destinationPath: 压缩的目标文件路径 (例如 `/tmp/archive.tar.gz`)
    ///   - format: 压缩格式，如果不传则自动根据 `destinationPath` 文件名后缀推断
    ///   - password: 加密密码(可选)
    ///   - overwrite: 是否允许覆盖已存在的目标文件，默认 `true`
    ///   - onLog: 实时标准输出日志回调 (stdout)
    ///   - onError: 实时标准错误日志回调 (stderr)
    /// - Returns: 命令是否成功完整执行并返回退出码 0
    func compress(
        sourcePath: String,
        destinationPath: String,
        format: ArchiveFormat? = nil,
        password: String? = nil,
        overwrite: Bool = true,
        onLog: ((String) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) async -> Bool {
        guard let archiveFormat = format ?? ArchiveFormat.infer(from: destinationPath) else {
            onError?("[FoxTerm Error] Unable to infer archive format. Please specify the 'format' parameter explicitly.\n")
            return false
        }

        let cmd = buildRobustCompressCommand(
            source: sourcePath,
            destination: destinationPath,
            format: archiveFormat,
            password: password,
            overwrite: overwrite
        )

        return await safeExec(cmd, onLog: onLog, onError: onError)
    }

    /// 执行远程压缩包的解压操作
    /// - Parameters:
    ///   - archivePath: 远程压缩包路径 (例如 `/tmp/archive.tar.xz`)
    ///   - destinationDir: 目标解压目录 (例如 `/var/www/html`)
    ///   - format: 压缩格式，如果不传则自动根据 `archivePath` 文件名后缀推断
    ///   - password: 解密密码(可选)
    ///   - overwrite: 是否强制覆盖解压目录中的同名文件，默认 `true`
    ///   - onLog: 实时标准输出日志回调 (stdout)
    ///   - onError: 实时标准错误日志回调 (stderr)
    /// - Returns: 命令是否成功完整执行并返回退出码 0
    func decompress(
        archivePath: String,
        destinationDir: String,
        format: ArchiveFormat? = nil,
        password: String? = nil,
        overwrite: Bool = true,
        onLog: ((String) -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) async -> Bool {
        guard let archiveFormat = format ?? ArchiveFormat.infer(from: archivePath) else {
            onError?("[FoxTerm Error] Unable to infer archive format. Please specify the 'format' parameter explicitly.\n")
            return false
        }

        let cmd = buildRobustDecompressCommand(
            archive: archivePath,
            destinationDir: destinationDir,
            format: archiveFormat,
            password: password,
            overwrite: overwrite
        )

        return await safeExec(cmd, onLog: onLog, onError: onError)
    }

    // MARK: - 内部执行桥接

    /// 桥接调用原生的 `exec(_:output:outerr:)`，将数据流实时解码并传给闭包
    private func safeExec(
        _ command: String,
        onLog: ((String) -> Void)?,
        onError: ((String) -> Void)?
    ) async -> Bool {
        let stdoutStream = ClosureOutputStream { data in
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                onLog?(text)
            }
        }

        let stderrStream = ClosureOutputStream { data in
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                onError?(text)
            }
        }

        return await exec(command, output: stdoutStream, outerr: stderrStream)
    }

    // MARK: - POSIX 跨平台命令生成器

    /// 构建兼容多平台(Linux/macOS/BSD/BusyBox)的远程压缩命令行
    private func buildRobustCompressCommand(
        source: String,
        destination: String,
        format: ArchiveFormat,
        password: String?,
        overwrite: Bool
    ) -> String {
        let (parentDir, baseName) = POSIXPath.split(source)
        let cdCmd = parentDir.isEmpty ? "" : "cd \(POSIXPath.escape(parentDir)) && "
        let relativeSrc = POSIXPath.escape(baseName)
        let escapedDest = POSIXPath.escape(destination)

        let overwriteGuard = overwrite ? "" : "test ! -e \(escapedDest) && "

        if let pwd = password, !pwd.isEmpty {
            let escapedPwd = POSIXPath.escape(pwd)
            switch format {
            case .zip:
                return "\(overwriteGuard)if command -v zip >/dev/null 2>&1; then \(cdCmd)zip -r -P \(escapedPwd) \(escapedDest) \(relativeSrc); elif command -v 7z >/dev/null 2>&1; then \(cdCmd)7z a -y -p\(escapedPwd) \(escapedDest) \(relativeSrc); else echo '[FoxTerm Error] Missing required tools: neither zip nor 7z is installed on the remote server.' >&2; exit 1; fi"
            case .sevenZip:
                return "\(overwriteGuard)if command -v 7z >/dev/null 2>&1; then \(cdCmd)7z a -y -p\(escapedPwd) -mhe=on \(escapedDest) \(relativeSrc); else echo '[FoxTerm Error] Missing required tool: 7z is not installed on the remote server.' >&2; exit 1; fi"
            default:
                return """
                \(overwriteGuard)if command -v 7z >/dev/null 2>&1; then \
                    \(cdCmd)7z a -y -p\(escapedPwd) -mhe=on \(escapedDest) \(relativeSrc); \
                elif command -v gpg >/dev/null 2>&1; then \
                    \(cdCmd)tar -czvf - \(relativeSrc) | gpg --batch --yes --passphrase \(escapedPwd) -c -o \(escapedDest); \
                elif command -v zip >/dev/null 2>&1; then \
                    \(cdCmd)zip -r -P \(escapedPwd) \(escapedDest) \(relativeSrc); \
                else \
                    echo '[FoxTerm Error] Missing required encryption tools (7z / gpg / zip) for password-protected tar compression.' >&2; exit 1; \
                fi
                """
            }
        }

        let coreCmd = switch format {
        case .tarGz:
            "tar -czvf \(escapedDest) \(relativeSrc)"
        case .tarBz2:
            "tar -cjvf \(escapedDest) \(relativeSrc)"
        case .tarXz:
            "tar -cJvf \(escapedDest) \(relativeSrc) 2>/dev/null || (tar -cvf - \(relativeSrc) | xz -c > \(escapedDest))"
        case .tar:
            "tar -cvf \(escapedDest) \(relativeSrc)"
        case .zip:
            "zip -r \(escapedDest) \(relativeSrc)"
        case .sevenZip:
            "7z a -y \(escapedDest) \(relativeSrc)"
        }

        return "\(overwriteGuard)\(cdCmd)\(coreCmd)"
    }

    /// 构建兼容多平台(Linux/macOS/BSD/BusyBox)的远程解压命令行
    private func buildRobustDecompressCommand(
        archive: String,
        destinationDir: String,
        format: ArchiveFormat,
        password: String?,
        overwrite: Bool
    ) -> String {
        let escapedArchive = POSIXPath.escape(archive)
        let escapedDest = POSIXPath.escape(destinationDir)
        let pwd = password ?? ""
        let hasPwd = !pwd.isEmpty
        let escapedPwd = POSIXPath.escape(pwd)

        let mkdirCmd = "mkdir -p \(escapedDest)"

        let unzipOverwriteFlag = overwrite ? "-o" : "-n"
        let sevenZipOverwriteFlag = overwrite ? "-aoa" : "-aos"
        let tarNoOverwriteFlag = overwrite ? "" : "-k "

        let extractCmd = switch format {
        case .tarGz:
            if hasPwd {
                "if command -v 7z >/dev/null 2>&1; then 7z x -y -p\(escapedPwd) \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive); elif command -v gpg >/dev/null 2>&1; then gpg --batch --yes --passphrase \(escapedPwd) -d \(escapedArchive) | tar -xzv \(tarNoOverwriteFlag)-f - -C \(escapedDest); else echo '[FoxTerm Error] Missing required decryption tools: neither 7z nor gpg is installed.' >&2; exit 1; fi"
            } else {
                "tar -xzv \(tarNoOverwriteFlag)-f \(escapedArchive) -C \(escapedDest)"
            }
        case .tarBz2:
            if hasPwd {
                "if command -v 7z >/dev/null 2>&1; then 7z x -y -p\(escapedPwd) \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive); elif command -v gpg >/dev/null 2>&1; then gpg --batch --yes --passphrase \(escapedPwd) -d \(escapedArchive) | tar -xjv \(tarNoOverwriteFlag)-f - -C \(escapedDest); else echo '[FoxTerm Error] Missing required decryption tools: neither 7z nor gpg is installed.' >&2; exit 1; fi"
            } else {
                "tar -xjv \(tarNoOverwriteFlag)-f \(escapedArchive) -C \(escapedDest)"
            }
        case .tarXz:
            if hasPwd {
                "if command -v 7z >/dev/null 2>&1; then 7z x -y -p\(escapedPwd) \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive); elif command -v gpg >/dev/null 2>&1; then gpg --batch --yes --passphrase \(escapedPwd) -d \(escapedArchive) | tar -xJv \(tarNoOverwriteFlag)-f - -C \(escapedDest); else echo '[FoxTerm Error] Missing required decryption tools: neither 7z nor gpg is installed.' >&2; exit 1; fi"
            } else {
                "tar -xJv \(tarNoOverwriteFlag)-f \(escapedArchive) -C \(escapedDest) 2>/dev/null || (xz -dc \(escapedArchive) | tar -xv \(tarNoOverwriteFlag)-f - -C \(escapedDest))"
            }
        case .tar:
            if hasPwd {
                "if command -v 7z >/dev/null 2>&1; then 7z x -y -p\(escapedPwd) \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive); elif command -v gpg >/dev/null 2>&1; then gpg --batch --yes --passphrase \(escapedPwd) -d \(escapedArchive) | tar -xv \(tarNoOverwriteFlag)-f - -C \(escapedDest); else echo '[FoxTerm Error] Missing required decryption tools: neither 7z nor gpg is installed.' >&2; exit 1; fi"
            } else {
                "tar -xv \(tarNoOverwriteFlag)-f \(escapedArchive) -C \(escapedDest)"
            }
        case .zip:
            if hasPwd {
                "if command -v unzip >/dev/null 2>&1; then unzip -P \(escapedPwd) \(unzipOverwriteFlag) \(escapedArchive) -d \(escapedDest); elif command -v 7z >/dev/null 2>&1; then 7z x -y -p\(escapedPwd) \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive); else echo '[FoxTerm Error] Missing required tools: neither unzip nor 7z is installed.' >&2; exit 1; fi"
            } else {
                "if command -v unzip >/dev/null 2>&1; then unzip \(unzipOverwriteFlag) \(escapedArchive) -d \(escapedDest); elif command -v 7z >/dev/null 2>&1; then 7z x -y \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive); else echo '[FoxTerm Error] Missing required tools: neither unzip nor 7z is installed.' >&2; exit 1; fi"
            }
        case .sevenZip:
            if hasPwd {
                "7z x -y -p\(escapedPwd) \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive)"
            } else {
                "7z x -y \(sevenZipOverwriteFlag) -o\(escapedDest) \(escapedArchive)"
            }
        }

        return "\(mkdirCmd) && \(extractCmd)"
    }
}

// MARK: - POSIX 路径解析与安全转义工具集

/// POSIX Shell 路径解析与安全转义工具集
public enum POSIXPath {
    /// 严丝合缝的 POSIX Shell 参数转义，防止单/双引号闭合失效与 Shell 脚本注入
    /// - Parameter string: 待转义的原始字符串(路径或密码)
    /// - Returns: 使用单引号安全包裹后的 Shell 参数
    public static func escape(_ string: String) -> String {
        if string.isEmpty {
            return "''"
        }
        let escaped = string.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// 提取 POSIX 格式路径的父级目录与文件名/末级目录名(不依赖 Foundation 的 URL 类)
    /// - Parameter path: POSIX 路径字符串
    /// - Returns: 元组 `(parentDir, baseName)`
    public static func split(_ path: String) -> (parentDir: String, baseName: String) {
        var cleanPath = path
        while cleanPath.count > 1, cleanPath.hasSuffix("/") {
            cleanPath.removeLast()
        }

        if cleanPath.isEmpty {
            return ("", "")
        }

        let components = cleanPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        if components.count == 1 {
            return ("", components[0])
        }

        let baseName = components.last ?? ""
        let parentComponents = components.dropLast()

        var parentDir = parentComponents.joined(separator: "/")
        if cleanPath.hasPrefix("/"), !parentDir.hasPrefix("/") {
            parentDir = "/" + parentDir
        }

        return (parentDir.isEmpty ? "/" : parentDir, baseName)
    }
}
