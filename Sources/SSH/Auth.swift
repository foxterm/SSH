// FoxTerm | Auth.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

public extension SSH {
    /// 获取远程服务器支持的身份验证方法列表
    /// - Parameter user: 用户名
    /// - Returns: 服务器支持的认证类型数组（如 .password, .publickey 等）
    func getUserauthList(user: String) async -> [AuthType] {
        self.user = user
        guard rawSession != nil else {
            return []
        }
        // 调用 libssh2 获取逗号分隔的认证方式字符串
        let ptr = await callSSH2 {
            libssh2_userauth_list(self.rawSession, user, user.count.uint32)
        }
        guard let ptr else {
            return []
        }

        var auth: [AuthType] = []
        // 解析返回的字符串并转换为内部定义的 AuthType 枚举
        for a in ptr.string.components(separatedBy: ",") {
            switch a {
            case "publickey":
                auth.append(.publickey)
            case "keyboard-interactive":
                auth.append(.keyboard)
            case "password":
                auth.append(.password)
            case "none":
                auth.append(.none)
            default:
                continue
            }
        }
        return auth
    }

    /// 检查当前会话是否已经通过身份验证
    var isAuthenticated: Bool {
        guard let rawSession else {
            return false
        }
        return libssh2_userauth_authenticated(rawSession) == 1
    }

    /// 使用用户名和密码进行身份验证
    /// - Parameters:
    ///   - user: 用户名
    ///   - password: 密码
    /// - Returns: 认证是否成功
    func authenticate(user: String, password: String) async -> Bool {
        // 先确认服务器是否支持密码登录
        guard await getUserauthList(user: user).contains(.password) else {
            return false
        }
        if isAuthenticated {
            return true
        }
        guard rawSession != nil else {
            return false
        }

        let code = await callSSH2 {
            libssh2_userauth_password_ex(
                self.rawSession, user, user.count.uint32, password, password.count.uint32, nil
            )
        }

        return code == LIBSSH2_ERROR_NONE && isAuthenticated
    }

    /// 使用公钥/私钥对进行身份验证
    /// 直接从内存加载密钥字符串，无需写入本地文件，安全性更高
    /// - Parameters:
    ///   - user: 用户名
    ///   - privateKey: 私钥内容（PEM 格式）
    ///   - passphrase: 私钥解密密码（如有）
    ///   - publickey: 公钥内容（可选，部分服务器需要）
    /// - Returns: 认证是否成功
    func authenticate(
        user: String, privateKey: String, passphrase: String = "", publickey: String = ""
    ) async -> Bool {
        guard await getUserauthList(user: user).contains(.publickey) else {
            return false
        }
        if isAuthenticated {
            return true
        }
        guard rawSession != nil else {
            return false
        }

        let code = await callSSH2 {
            libssh2_userauth_publickey_frommemory(
                self.rawSession, user, user.count, publickey, publickey.count, privateKey,
                privateKey.count, passphrase
            )
        }
        return code == LIBSSH2_ERROR_NONE && isAuthenticated
    }

    /// 执行“无密码”认证或“交互式”认证 (Keyboard-Interactive)
    /// - Parameters:
    ///   - user: 用户名
    ///   - none: 是否尝试 'none' 认证（用于探测或某些免密环境）
    /// - Returns: 认证是否成功
    func authenticate(user: String, none: Bool = false) async -> Bool {
        if none {
            guard await getUserauthList(user: user).contains(.none) else {
                return false
            }
            return isAuthenticated
        }

        guard await getUserauthList(user: user).contains(.keyboard) else {
            return false
        }
        if isAuthenticated {
            return true
        }
        guard rawSession != nil else {
            return false
        }

        // 核心：处理 SSH 键盘交互式认证的回调逻辑
        let code = await callSSH2 {
            libssh2_userauth_keyboard_interactive_ex(self.rawSession, user, user.count.uint32) {
                _, _, _, _, numPrompts, prompts, responses, abstract in
                // 从 abstract 指针中取回关联的 SSH 实例
                guard let ssh = abstract?.address.ssh else { return }

                // 遍历服务器发出的每一个提示（Prompt）
                for i in 0 ..< Int(numPrompts) {
                    guard let promptI = prompts?[i], let text = promptI.text else { continue }
                    guard let prompt = Data(bytes: text, count: promptI.length).string else {
                        continue
                    }

                    // 通过代理向用户请求输入（如验证码、二次确认等）
                    let password =
                        ssh.sessionDelegate?.keyboardInteractive(ssh: ssh, prompt: prompt) ?? ""

                    // 将用户的输入填入响应结构体返回给 libssh2
                    let response = LIBSSH2_USERAUTH_KBDINT_RESPONSE(
                        text: password.bytes, length: password.count.uint32
                    )
                    responses?[i] = response
                }
            }
        }
        return code == LIBSSH2_ERROR_NONE && isAuthenticated
    }

    /// 开启 SSH 心跳包计时器
    /// 每隔 5 秒发送一次 Keepalive 信号，防止连接因闲置被网关断开
    func keepalive() {
        keepaliveConfig()
        timer?.cancel()
        timer = nil

        // 使用 DispatchSource 创建高精度的后台计时器
        timer = DispatchSource.makeTimerSource(queue: .global())
        timer?.schedule(deadline: .now() + .seconds(5), repeating: 5.0)
        timer?.setEventHandler { [weak self] in
            self?.sendKeepalive()
        }
        timer?.resume()
    }
}
