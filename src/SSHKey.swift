// FoxTerm | SSHKey.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

public class SSHKey {
    let key: ssh_key

    public init(key: ssh_key) {
        self.key = key
    }

    deinit {
        ssh_key_free(key)
        #if DEBUG
            print("♻️", "SSH Key")
        #endif
    }
}

// MARK: - 密钥生成与导入导出

public extension SSHKey {
    /// 生成指定类型与位数的 SSH 密钥对
    /// - Parameters:
    ///   - type: 密钥算法类型(RSA, ED25519, ECDSA 等)
    ///   - bits: 密钥长度位数(主要用于 RSA，例如 2048/4096)
    /// - Returns: 生成成功返回 `SSHKey` 实例，失败返回 `nil`
    static func generate(type: KeyType, bits: Int = 0) -> SSHKey? {
        guard let ctx = ssh_pki_ctx_new() else { return nil }
        defer { ssh_pki_ctx_free(ctx) }

        if type == .rsa {
            _ = bits.withUnsafeRawPointer { bit in
                ssh_pki_ctx_options_set(ctx, SSH_PKI_OPTION_RSA_KEY_SIZE, bit)
            }
        }

        var key: ssh_key?
        guard ssh_pki_generate_key(type.value, ctx, &key) == SSH_OK, let key else {
            return nil
        }
        return .init(key: key)
    }

    /// 从 Base64 文本导入私钥
    /// - Parameters:
    ///   - base64: Base64 编码的私钥字符串
    ///   - passphrase: 私钥密码(可选)
    /// - Returns: 导入成功返回 `SSHKey` 实例，失败返回 `nil`
    static func importPrivkey(base64: String, passphrase: String = "") -> SSHKey? {
        var key: ssh_key?
        let pass = passphrase.trim
        let res = ssh_pki_import_privkey_base64(
            base64.bytesArray,
            pass.isEmpty ? nil : pass.bytesArray,
            nil,
            nil,
            &key
        )
        guard res == SSH_OK, let key else {
            return nil
        }
        return .init(key: key)
    }

    /// 计算并返回公钥指纹
    /// - Parameter type: 密钥指纹哈希类型(默认为 `.sha1`)
    /// - Returns: 格式化后的指纹字符串(例如 "SHA256:...")
    func fingerprint(_ type: HostkeyHash = .sha1) -> String? {
        guard isPublic else {
            return nil
        }
        var hash: UnsafeMutablePointer<UInt8>?
        var hlen: size_t = 0
        guard ssh_get_publickey_hash(key, type.value, &hash, &hlen) == SSH_OK else {
            return nil
        }
        defer {
            ssh_clean_pubkey_hash(&hash)
        }
        guard let char = ssh_get_fingerprint_hash(type.value, hash, hlen) else {
            return nil
        }
        return char.string
    }

    /// 导出为标准公钥文本格式(如 "ssh-rsa AAAAB3NzaC1...")
    func exportPublickey() -> String? {
        guard isPublic else {
            return nil
        }
        var buf: UnsafeMutablePointer<CChar>?
        guard ssh_pki_export_pubkey_base64(key, &buf) == SSH_OK else {
            return nil
        }
        defer {
            ssh_string_free_char(buf)
        }
        guard let buf else {
            return nil
        }
        let b64 = buf.string
        return "\(name) \(b64)"
    }

    /// 导出 Base64 私钥文本
    /// - Parameters:
    ///   - passphrase: 导出时加密使用的密码
    ///   - format: 导出格式(PEM 或 OpenSSH 格式)
    /// - Returns: 格式化后的私钥字符串
    func exportPrivkey(passphrase: String = "", format: KeyFormat = .pem) -> String? {
        guard isPrivate else {
            return nil
        }
        var buf: UnsafeMutablePointer<CChar>?
        let pass = passphrase.trim
        let res = ssh_pki_export_privkey_base64_format(
            key,
            pass.isEmpty ? nil : pass.bytesArray,
            nil,
            nil,
            &buf,
            format.value
        )
        guard res == SSH_OK, let buf else {
            return nil
        }
        defer {
            ssh_string_free_char(buf)
        }
        let rawString = buf.string

        if format == .openssh {
            return formatOpenSSHKeyString(rawString)
        }

        return rawString
    }

    /// 将原始字符串按 64 字符行宽拆分并格式化为标准 OpenSSH 私钥样式
    private func formatOpenSSHKeyString(_ raw: String) -> String {
        let header = "-----BEGIN OPENSSH PRIVATE KEY-----"
        let footer = "-----END OPENSSH PRIVATE KEY-----"

        var body = raw
            .replacingOccurrences(of: header, with: "")
            .replacingOccurrences(of: footer, with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var formattedLines: [String] = []
        while !body.isEmpty {
            let chunk = String(body.prefix(64))
            formattedLines.append(chunk)
            body = String(body.dropFirst(64))
        }

        return ([header] + formattedLines + [footer]).joined(separator: "\n")
    }

    // MARK: - 属性访问与状态判断

    /// 获取公钥句柄(如果是私钥则自动导出其对应的公钥)
    var pubkey: ssh_key? {
        if isPublic, !isPrivate {
            return key
        }
        var pubkey: ssh_key?
        guard ssh_pki_export_privkey_to_pubkey(key, &pubkey) == SSH_OK, let pubkey else {
            return nil
        }
        return pubkey
    }

    /// 获取私钥句柄(非私钥则返回 nil)
    var privkey: ssh_key? {
        guard isPrivate else {
            return nil
        }
        return key
    }

    /// 获取密钥的底层 C 库枚举类型 (`ssh_keytypes_e`)
    var type: ssh_keytypes_e {
        ssh_key_type(key)
    }

    /// 获取密钥类型的字符串标识名称(例如 "ssh-rsa"、"ssh-ed25519")
    var name: String {
        ssh_key_type_to_char(type).string
    }

    /// 检查密钥是否包含公钥信息
    var isPublic: Bool {
        ssh_key_is_public(key) == 1
    }

    /// 检查密钥是否为私钥
    var isPrivate: Bool {
        ssh_key_is_private(key) == 1
    }
}

// MARK: - 辅助类型定义

/// 支持的密钥生成类型
public enum KeyType: String, CaseIterable {
    case ed25519
    case ecdsaP256 = "ecdsa-sha2-nistp256"
    case ecdsaP384 = "ecdsa-sha2-nistp384"
    case ecdsaP521 = "ecdsa-sha2-nistp521"
    case rsa

    /// 对应的 libssh C API 映射枚举值
    public var value: ssh_keytypes_e {
        switch self {
        case .rsa:
            SSH_KEYTYPE_RSA
        case .ed25519:
            SSH_KEYTYPE_ED25519
        case .ecdsaP256:
            SSH_KEYTYPE_ECDSA_P256
        case .ecdsaP384:
            SSH_KEYTYPE_ECDSA_P384
        case .ecdsaP521:
            SSH_KEYTYPE_ECDSA_P521
        }
    }
}

/// 导出私钥时的文件格式
public enum KeyFormat: String, CaseIterable {
    case openssh
    case pem

    /// 对应的 libssh C API 格式枚举
    var value: ssh_file_format_e {
        switch self {
        case .pem:
            SSH_FILE_FORMAT_PEM
        case .openssh:
            SSH_FILE_FORMAT_OPENSSH
        }
    }

    /// 可读名称
    public var name: String {
        switch self {
        case .pem:
            "PEM"
        case .openssh:
            "OpenSSH"
        }
    }
}
