// FoxTerm | Auth.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import GSS
import libetos
import libssh

public extension SSH {
    /// 设置 SSH 连接的用户名（在认证前调用）
    /// - Parameter user: 登录用户名
    func authUser(user: String) {
        self.user = user
    }

    // MARK: - 无密码认证

    /// 尝试 None 认证方式
    /// - Returns: 是否认证成功
    func authNone() -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSession else {
                return false
            }
            guard ssh_userauth_none(rawSession, user.bytesArray) == SSH_AUTH_SUCCESS.rawValue else {
                return false
            }
            isAuth = true
            return true
        }
    }

    // MARK: - GSSAPI 认证

    // 尝试 GSSAPI 及其 Key Exchange 认证方式
    // - Returns: 是否认证成功
//    func authGssapi() -> Bool {
//        mutex.withLock {
//            guard let rawSession else {
//                return false
//            }
//            var rc = ssh_userauth_gssapi(rawSession)
//            if rc == SSH_AUTH_ERROR.rawValue {
//                return false
//            }
//            if rc == SSH_AUTH_SUCCESS.rawValue {
//                isAuth = true
//                return true
//            }
//            rc = ssh_userauth_gssapi_keyex(rawSession)
//            if rc == SSH_AUTH_ERROR.rawValue {
//                return false
//            }
//            if rc == SSH_AUTH_SUCCESS.rawValue {
//                isAuth = true
//                return true
//            }
//            return false
//        }
//    }

    // MARK: - 密码认证

    /// 使用指定密码进行认证
    /// - Parameter password: 密码字符串
    /// - Returns: 是否认证成功
    func authPassword(password: String) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSession else {
                return false
            }
            guard ssh_userauth_password(rawSession, user.bytesArray, password.bytesArray) == SSH_AUTH_SUCCESS.rawValue else {
                return false
            }
            isAuth = true
            return true
        }
    }

    // MARK: - 键盘交互式认证

    /// 执行键盘交互式(Keyboard-Interactive)认证
    /// - Returns: 是否认证成功
    func authKbdint() -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        while true {
            let state: (rc: Int32, name: String, instruction: String, prompts: [String]) = mutex.withLock {
                guard let rawSession else {
                    return (SSH_AUTH_ERROR.rawValue, "", "", [])
                }
                let rc = ssh_userauth_kbdint(rawSession, user.bytesArray, nil)
                guard rc == SSH_AUTH_INFO.rawValue else {
                    return (rc, "", "", [])
                }

                let name = ssh_userauth_kbdint_getname(rawSession)?.string ?? ""
                let instruction = ssh_userauth_kbdint_getinstruction(rawSession)?.string ?? ""
                let n = ssh_userauth_kbdint_getnprompts(rawSession)

                var prompts: [String] = []
                for i in 0 ..< n {
                    let promptPtr = ssh_userauth_kbdint_getprompt(rawSession, i.uint32, nil)
                    prompts.append(promptPtr?.string ?? "")
                }
                return (rc, name, instruction, prompts)
            }

            if state.rc != SSH_AUTH_INFO.rawValue {
                return mutex.withLock {
                    if state.rc == SSH_AUTH_SUCCESS.rawValue {
                        isAuth = true
                        return true
                    }
                    return false
                }
            }

            var answers: [String] = []
            for prompt in state.prompts {
                let answer = sessionDelegate?.keyboardInteractive(
                    name: state.name,
                    instruction: state.instruction,
                    prompt: prompt
                ) ?? ""
                answers.append(answer)
            }

            let setAnswerResult = mutex.withLock {
                guard let rawSession else { return false }
                for (i, answer) in answers.enumerated() {
                    ssh_userauth_kbdint_setanswer(rawSession, i.uint32, answer.bytesArray)
                }
                return true
            }

            guard setAnswerResult else { return false }
        }
    }

    // MARK: - 公钥认证

    /// 使用私钥进行 SSH 公钥认证
    /// - Parameters:
    ///   - privkey: Base64 格式的私钥数据或私钥文本内容
    ///   - passphrase: 私钥密码(无口令可传空字符串)
    /// - Returns: 是否认证成功
    func authPublickey(privkey: String, passphrase: String = "") -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        guard let key = SSHKey.importPrivkey(base64: privkey, passphrase: passphrase),
              let privkeyPtr = key.privkey,
              let pubkeyPtr = key.pubkey
        else {
            return false
        }

        return mutex.withLock {
            guard let rawSession else {
                return false
            }

            guard ssh_userauth_try_publickey(rawSession, user.bytesArray, pubkeyPtr) == SSH_AUTH_SUCCESS.rawValue else {
                return false
            }

            guard ssh_userauth_publickey(rawSession, user.bytesArray, privkeyPtr) == SSH_AUTH_SUCCESS.rawValue else {
                return false
            }
            isAuth = true
            return true
        }
    }

    // MARK: - 查询服务端可用认证方式

    /// 获取服务端支持的认证方式列表
    /// - Returns: 可用认证方式枚举数组 `[AuthType]`
    func authList() -> [AuthType] {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSession else {
                return []
            }
            let method = ssh_userauth_list(rawSession, user.bytesArray).uint32
            let mappings: [(UInt32, AuthType)] = [
                (SSH_AUTH_METHOD_PUBLICKEY, .publickey),
                (SSH_AUTH_METHOD_INTERACTIVE, .keyboard),
                (SSH_AUTH_METHOD_PASSWORD, .password),
//                (SSH_AUTH_METHOD_GSSAPI_MIC, .gssapi),
//                (SSH_AUTH_METHOD_GSSAPI_KEYEX, .gssapi),
                (SSH_AUTH_METHOD_NONE, .none),
            ]
            var result = [AuthType]()
            for (flag, authType) in mappings {
                if (method & flag) != 0, !result.contains(authType) {
                    result.append(authType)
                }
            }

            return result
        }
    }
}
