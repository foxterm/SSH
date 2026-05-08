// FoxTerm | Error.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

public extension SSH {
    /// 获取当前 SSH 会话的最后一个错误信息
    /// 将 libssh2 的内部错误状态转换为 Swift 的 Error (NSError) 对象
    /// - Returns: 包含错误码和错误描述的 Error 对象，若无错误则返回 nil
    var lastError: Error? {
        guard rawSession != nil else {
            return nil
        }

        // 用于接收 libssh2 返回的错误消息字符串指针
        var cstr: UnsafeMutablePointer<CChar>?

        // 调用 libssh2_session_last_error 获取错误码及描述字符串
        let code = libssh2_session_last_error(rawSession, &cstr, nil, 0)

        // 如果返回值为 LIBSSH2_ERROR_NONE (0)，表示没有发生错误
        guard code != LIBSSH2_ERROR_NONE else {
            return nil
        }

        // 如果 cstr 为空，则无法获取具体的文本描述
        guard let cstr else {
            return nil
        }

        // 将 C 风格的错误码和字符串封装为 NSError
        // 使用 NSLocalizedDescriptionKey 使得可以使用 .localizedDescription 获取描述
        return NSError(
            domain: "libssh2",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: String(cString: cstr)]
        )
    }
}
