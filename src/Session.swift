// FoxTerm | Session.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

public extension SSH {
    // MARK: - 代理与算法注册

    /// 注册 SSH 会话事件代理
    func registerSessionDelegate(_ delegate: SessionDelegate) {
        sessionDelegate = delegate
    }

    /// 注册 Shell 数据交互代理
    func registerShellDelegate(_ delegate: ShellDelegate) {
        shellDelegate = delegate
    }

    /// 注册自定义主机密钥算法
    func registerHostKeyAlgorithms(_ algo: String) {
        hostKeyAlgorithms = algo
    }

    // MARK: - 握手与连接协商

    /// 执行 SSH 握手协议
    /// 包含会话初始化、选项配置、已知主机校验及握手协商
    /// - Returns: 握手成功返回 `true`，失败则自动释放资源并返回 `false`
    func handshake() -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        guard !user.isEmpty else {
            return false
        }
        guard let session = ssh_new() else {
            return false
        }
//        #if DEBUG
//            var verbosity = SSH_LOG_DEBUG
//            ssh_options_set(session, SSH_OPTIONS_LOG_VERBOSITY, &verbosity)
//        #endif
        var processConfig: CInt = 0
        ssh_options_set(session, SSH_OPTIONS_PROCESS_CONFIG, &processConfig)

        ssh_options_set(session, SSH_OPTIONS_KNOWNHOSTS, URL.knownHosts.path.bytesArray)
        ssh_options_set(session, SSH_OPTIONS_GLOBAL_KNOWNHOSTS, "/dev/null".bytesArray)

        if !hostKeyAlgorithms.isEmpty {
            ssh_options_set(session, SSH_OPTIONS_HOSTKEYS, hostKeyAlgorithms.bytesArray)
        }
        var gssapi_delegate: CInt = 1
        ssh_options_set(session, SSH_OPTIONS_GSSAPI_DELEGATE_CREDENTIALS, &gssapi_delegate)

        ssh_options_set(session, SSH_OPTIONS_USER, user.bytesArray)
        ssh_options_set(session, SSH_OPTIONS_HOST, host.bytesArray)
        var cPort = CUnsignedInt(port)
        ssh_options_set(session, SSH_OPTIONS_PORT, &cPort)
        var cTimeout = CLong(timeout)
        ssh_options_set(session, SSH_OPTIONS_TIMEOUT, &cTimeout)
        var cFd = socket_t(fd)
        ssh_options_set(session, SSH_OPTIONS_FD, &cFd)
        ssh_options_set(session, SSH_OPTIONS_COMPRESSION, compress ? "yes".bytesArray : "no".bytesArray)
        var cCompressLevel = CUnsignedInt(compress_level)
        ssh_options_set(session, SSH_OPTIONS_COMPRESSION_LEVEL, &cCompressLevel)

        guard ssh_connect(session) == SSH_OK else {
            error = ssh_get_error(session.pointer).string
            ssh_free(session)
            return false
        }
        rawSession = session
        let state = ssh_session_is_known_server(session)
        guard let info = getHostInfo() else {
            ssh_disconnect(rawSession)
            ssh_free(rawSession)
            rawSession = nil
            return false
        }
        switch state {
        case SSH_KNOWN_HOSTS_NOT_FOUND, SSH_KNOWN_HOSTS_UNKNOWN:
            guard sessionDelegate?.knownState(info: info, state: state) ?? true else {
                ssh_disconnect(rawSession)
                ssh_free(rawSession)
                rawSession = nil
                return false
            }
            ssh_session_update_known_hosts(session)
        default:
            guard sessionDelegate?.knownState(info: info, state: state) ?? true else {
                ssh_disconnect(rawSession)
                ssh_free(rawSession)
                rawSession = nil
                return false
            }
        }
        return true
    }

    /// 发送忽略消息
    /// - Parameter data: 忽略消息的名称，默认为 "keepalive"
    /// - Returns: 是否成功发送忽略消息
    func sendIgnore(data: String = "keepalive") -> Bool {
        mutex.withLock {
            guard let rawSession else {
                return false
            }
            let rc = ssh_send_ignore(rawSession, data.bytesArray)
            return rc == SSH_OK
        }
    }

    // MARK: - 主机信息与公钥指纹

    /// 获取当前 SSH 连接的主机详细结构化信息
    /// - Returns: `HostInfo` 模型(包含地址、Banner、公钥及指纹)
    func getHostInfo() -> HostInfo? {
        var remoteAddrStr = "-"
        var remoteIPStr = ""
        var localAddrStr = "-"
        var serverBannerStr = "-"
        var clientbannerStr = "-"
        var publickeyStr = "-"
        var fingerprints: [String] = []
        if let (host, port) = remoteAddr {
            remoteAddrStr = Net.joinHostPort(host: host, port: port)
            remoteIPStr = host
        }
        if let (host, port) = localAddr {
            localAddrStr = Net.joinHostPort(host: host, port: port)
        }
        serverBannerStr = serverBanner ?? "-"
        clientbannerStr = clientbanner ?? "-"
        if let pub = publickey() {
            publickeyStr = pub.exportPublickey() ?? "-"
            for type in HostkeyHash.allCases {
                if let hash = pub.fingerprint(type) {
                    fingerprints.append(hash)
                }
            }
        }
        return .init(
            remoteAddr: remoteAddrStr,
            remoteIP: remoteIPStr,
            localAddr: localAddrStr,
            serverBanner: serverBannerStr,
            clientbanner: clientbannerStr,
            publickey: publickeyStr,
            fingerprints: fingerprints
        )
    }

    /// 获取服务端公钥对象
    func publickey() -> SSHKey? {
        guard let rawSession else {
            return nil
        }
        var key = ssh_key_new()
        ssh_get_server_publickey(rawSession, &key)
        guard let key else {
            return nil
        }
        return .init(key: key)
    }

    /// 获取指定计算类型的服务端公钥指纹
    /// - Parameter type: 指纹哈希算法(例如 `.sha256`、`.md5`)
    /// - Returns: 指纹字符串
    func fingerprint(_ type: HostkeyHash = .sha256) -> String? {
        publickey()?.fingerprint(type)
    }

    /// 默认 SHA256 服务端公钥指纹
    var fingerprint: String? {
        fingerprint()
    }

    /// 客户端发送的 SSH Banner 字符串
    var clientbanner: String? {
        guard let rawSession else {
            return nil
        }
        let char = ssh_get_clientbanner(rawSession)
        return char?.string
    }

    /// 服务端返回的 SSH Banner 字符串
    var serverBanner: String? {
        guard let rawSession else {
            return nil
        }
        let char = ssh_get_serverbanner(rawSession)
        return char?.string
    }

    /// 根据服务端 Banner 简单检测目标服务器是否为 Windows 系统
    var isWindows: Bool {
        guard let version = serverBanner?.lowercased() else {
            return false
        }
        return version.contains("windows") || version.contains("mssh")
    }

    /// 获取当前会话底层最后的 libssh 错误描述字符串
    var lastError: String? {
        guard let rawSession else {
            return nil
        }
        return ssh_get_error(rawSession.pointer).string
    }

    /// 便捷生成 Machine 控制模型
    var machine: Machine {
        .init(ssh: self)
    }

    // MARK: - 静态支持库算法查询

    /// 获取底层 libssh 支持的主机公钥类型分类(区分安全与高风险不安全项)
    static func getHostKeys() -> HostKeySupport {
        let insecureSet: Set = ["ssh-rsa-cert-v01@openssh.com", "ssh-rsa", "ssh-dss"]
        let hostkeys = getSupportedMethods(SSH_HOSTKEYS)
        return HostKeySupport(
            supported: hostkeys.filter { !insecureSet.contains($0) },
            insecure: hostkeys.filter { insecureSet.contains($0) }
        )
    }

    /// 根据 libssh KEX 类型获取所支持的算法方法列表
    static func getSupportedMethods(_ type: ssh_kex_types_e) -> [String] {
        guard let char = ssh_get_supported_methods(type) else {
            return []
        }
        return char.string.components(separatedBy: ",")
    }

    // MARK: - 会话销毁与清理

    /// 释放并清理 SSH 会话句柄及关联 Delegate
    func freeSession() {
        wait.wait()
        mutex.withVoid {
            if let rawSession {
                ssh_disconnect(rawSession)
                ssh_free(rawSession)
            }

            rawSession = nil
            sessionDelegate = nil
            shellDelegate = nil
        }
    }
}
