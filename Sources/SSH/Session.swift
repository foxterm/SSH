// FoxTerm | Session.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation
import libetos

public extension SSH {
    /// 执行 SSH 握手协议
    /// 包含会话初始化、回调绑定、压缩配置及底层握手协商
    /// - Returns: 握手成功返回 true，否则释放资源并返回 false
    func handshake() async -> Bool {
        // 初始化 libssh2 会话，将 self 指针传入以便在回调中获取上下文
        rawSession = libssh2_session_init_ex(
            nil, nil, nil, Unmanaged.passUnretained(self).toOpaque()
        )
        guard let rawSession else {
            return false
        }
        // 握手阶段通常使用阻塞模式以简化状态机
        sessionBlocking = true

        #if DEBUG
            // 调试模式下开启错误追踪
            libssh2_trace(rawSession, LIBSSH2_TRACE_ERROR)
            libssh2_trace_sethandler(rawSession, nil, tracCallback)
        #endif

        // 注册核心回调：断开连接、数据发送与接收
        libssh2_session_callback_set2(
            rawSession,
            LIBSSH2_CALLBACK_DISCONNECT,
            unsafeBitCast(disconnectCallback, to: cbGenericType.self)
        )
        libssh2_session_callback_set2(
            rawSession,
            LIBSSH2_CALLBACK_SEND,
            unsafeBitCast(sendCallback, to: cbGenericType.self)
        )
        libssh2_session_callback_set2(
            rawSession,
            LIBSSH2_CALLBACK_RECV,
            unsafeBitCast(recvCallback, to: cbGenericType.self)
        )

        // 配置会话选项
        libssh2_session_flag(rawSession, LIBSSH2_FLAG_COMPRESS, compress ? 1 : 0)
        libssh2_session_flag(rawSession, LIBSSH2_FLAG_QUOTE_PATHS, 1)
        libssh2_session_set_timeout(rawSession, timeout)
        libssh2_session_banner_set(rawSession, clientbanner)

        // 执行底层握手
        let rec = await callSSH2 { [self] in
            libssh2_session_handshake(rawSession, fd)
        }

        guard rec == LIBSSH2_ERROR_NONE else {
            error = lastError?.localizedDescription
            freeSession()
            return false
        }

        // 触发外部委托，用于主机密钥验证等自定义逻辑
        guard sessionDelegate?.handshake(ssh: self) ?? true else {
            freeSession()
            return false
        }
        channelPoll.socketFD = fd
        channelPoll.bufferSize = bufferSize
        return true
    }

    /// 获取当前会话协商的算法方法名
    /// - Parameter type: 方法类型 (如 密钥交换、加解密、压缩等)
    func methods(_ type: SessionMethodType) -> String? {
        guard let rawSession else { return nil }
        guard let methods = libssh2_session_methods(rawSession, type.value) else { return nil }
        return String(cString: methods)
    }

    /// 检查当前连接是否已开启 zlib 压缩
    var isComp: Bool {
        methods(.comp_cs)?.hasPrefix("zlib") ?? false
            && methods(.comp_sc)?.hasPrefix("zlib") ?? false
    }

    /// 获取服务器端的软件版本标识 (Banner)
    var serverBanner: String? {
        guard let rawSession else { return nil }
        return libssh2_session_banner_get(rawSession).string.trim
    }

    /// 获取服务器公钥信息
    var serverPublickeyStr: String? {
        guard let type = methods(.hostkey) else { return nil }
        guard let key = serverPublickey else {
            return nil
        }
        return "\(type) \(key.base64String)"
    }

    /// 获取服务器公钥信息
    var serverPublickey: Data? {
        guard let rawSession else { return nil }
        let len: Buffer<Int> = .init()
        guard let key = libssh2_session_hostkey(rawSession, len.buffer, nil) else {
            return nil
        }
        return Data(bytes: key, count: len.pointee)
    }

    /// 计算并返回服务器公钥的指纹字符串
    /// - Parameter type: 哈希类型
    func fingerprint(_ type: HostkeyHash = .sha256) -> String? {
        guard rawSession != nil else { return nil }
        guard let hashPointer = libssh2_hostkey_hash(rawSession, type.value) else {
            return nil
        }
        return "\(type.string()):\(Data(bytes: hashPointer, count: type.length).fingerprint)"
    }

    /// 获取或设置会话及底层 Socket 的阻塞状态
    var sessionBlocking: Bool {
        get {
            guard rawSession != nil else { return false }
            return libssh2_session_get_blocking(rawSession) != 0
        }
        set {
            guard rawSession != nil else { return }
            // 同时同步底层 Socket 和 libssh2 会话的状态
            etos_socket_set_blocking(fd, newValue)
            libssh2_session_set_blocking(rawSession, newValue ? 1 : 0)
        }
    }

    /// 获取或设置会话超时时间 (毫秒)
    var sessionTimeout: Int {
        get {
            guard rawSession != nil else { return 0 }
            return libssh2_session_get_timeout(rawSession)
        }
        set {
            guard rawSession != nil else { return }
            libssh2_session_set_timeout(rawSession, newValue)
        }
    }

    /// 配置 SSH Keepalive 参数
    /// - Parameter keepaliveInterval: 心跳间隔时间（秒）
    internal func keepaliveConfig(_ keepaliveInterval: Int = 5) {
        guard rawSession != nil else { return }
        libssh2_keepalive_config(rawSession, 1, keepaliveInterval.uint32)
    }

    //    /// 发送心跳包，维持连接不断开
    /// 不需要心跳，使用了 Socket 层的 KeepAlive 机制防止链路被运营商中间设备切断
    //    internal func sendKeepalive() {
    //        guard rawSession != nil, isAuthenticated else { return }
    //        let seconds: Buffer<Int32> = .init()
    //        let rc = libssh2_keepalive_send(rawSession, seconds.buffer)
    //        guard rc == LIBSSH2_ERROR_NONE else {
    //            #if DEBUG
    //                print("心跳失败: \(rc)")
    //            #endif
    //            return
    //        }
    //        #if DEBUG
    //            print("下一次心跳 \(seconds.pointee) 秒")
    //        #endif
    //    }

    /// 读取远程文件的完整内容
    func readFile(_ filename: String) async -> String? {
        guard let data = await scp.download(remotePath: filename) else {
            return nil
        }
        guard let text = data.string else {
            return nil
        }
        return text
    }

    // MARK: - 功能组件访问器

    func exec(_ command: String) async -> Data? {
        await channel.exec(command)
    }

    /// 执行命令数组（自动以空格连接）
    func exec(_ command: [String]) async -> Data? {
        await channel.exec(command)
    }

    /// 获取通用命令通道
    var channel: Channel {
        .init(ssh: self)
    }

    /// 获取安全拷贝组件
    var scp: SCP {
        .init(channel: channel)
    }

    /// 获取端口转发组件
    var direct: Direct {
        .init(channel: channel)
    }

    /// 获取交互式 Shell 组件
    var shell: Shell {
        .init(channel: channel)
    }

    /// 获取文件管理 SFTP 组件
    var sftp: SFTP {
        .init(ssh: self)
    }

    /// 获取容器管理组件
    var machine: Machine {
        .init(ssh: self)
    }

    /// 安全释放 SSH 会话资源
    /// 包含取消定时器、发送断开指令、释放内存等
    func freeSession() {
        // 通知外部代理处理连接中断逻辑
        sessionDelegate?.disconnect()
        channelPoll.mutex.with {
            guard rawSession != nil else { return }
            //            timer?.cancel()
            //            timer = nil

            // 切换回阻塞模式以确保优雅退出
            sessionBlocking = true
            libssh2_session_disconnect_ex(rawSession, SSH_DISCONNECT_BY_APPLICATION, "Bye-Bye", "")
            libssh2_session_free(rawSession)

            sessionDelegate = nil
            rawSession = nil
            #if DEBUG
                print("♻️", "rawSession released")
            #endif
        }
    }
}

extension UnsafeRawPointer {
    /// 将 C 指针转换回 SSH 对象上下文
    var ssh: SSH {
        load()
    }
}
