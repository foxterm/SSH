// FoxTerm | Extension.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Foundation
import libssh

/// 为 `ssh_session` 提供便捷的原始指针转换
extension ssh_session {
    /// 将 SSH 会话句柄转换为无类型原始指针（用于 libssh C API 调用）
    var pointer: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(self)
    }
}

public extension URL {
    /// 沙盒 Documents 目录
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// known_hosts 文件的完整 URL（存储在沙盒 Documents 目录下）
    static var knownHosts: URL {
        documentsDirectory.appendingPathComponent("known_hosts")
    }
}

public extension String {
    // MARK: - 压缩 / 解压格式判断

    /// 是否为支持压缩/解压的文件扩展名或路径(例如 "tar.gz"、"/tmp/logs.tar.xz"、"archive.zip")
    var isSupportedArchiveFormat: Bool {
        ArchiveFormat.infer(from: self) != nil
    }

    /// 尝试推断并返回对应的压缩格式枚举，如果不支持则返回 `nil`
    var archiveFormat: ArchiveFormat? {
        ArchiveFormat.infer(from: self)
    }

    /// 明确判断是否支持解压(当前所有支持格式均同时支持解压)
    var isSupportedDecompressFormat: Bool {
        isSupportedArchiveFormat
    }

    /// 明确判断是否支持压缩(当前所有支持格式均同时支持压缩)
    var isSupportedCompressFormat: Bool {
        isSupportedArchiveFormat
    }
}

/// 获取底层 libssh 支持的主机密钥算法列表
/// - Returns: 算法名称字符串数组（如 `["ssh-ed25519", "ecdsa-sha2-nistp256", ...]`）
public func sshSupportedHostKeys() -> [String] {
    guard let ptr = ssh_get_supported_methods(SSH_HOSTKEYS) else { return [] }
    return ptr.string.components(separatedBy: ",")
}
