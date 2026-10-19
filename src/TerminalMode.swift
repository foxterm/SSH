// FoxTerm | TerminalMode.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation

/// Terminal Modes (RFC 4254 & RFC 8160)
public enum TerminalMode {
    // MARK: - 特殊字符控制

    case vintr(UInt8) // Interrupt (e.g. Ctrl+C = 0x03)
    case vquit(UInt8) // Quit (e.g. Ctrl+\ = 0x1C)
    case verase(UInt8) // Erase/Backspace (e.g. 0x7F or 0x08)
    case vkill(UInt8) // Kill Line (e.g. Ctrl+U = 0x15)
    case veof(UInt8) // End-of-file (e.g. Ctrl+D = 0x04)
    case vstart(UInt8) // Start output (e.g. Ctrl+Q = 0x11)
    case vstop(UInt8) // Stop output (e.g. Ctrl+S = 0x13)
    case vsusp(UInt8) // Suspend job (e.g. Ctrl+Z = 0x1A)
    case vwerase(UInt8) // Word erase (e.g. Ctrl+W = 0x17)
    case vlnext(UInt8) // Literal next (e.g. Ctrl+V = 0x16)

    // MARK: - 输入模式

    case icrnl(Bool) // 将输入的 CR (\r) 映射为 NL (\n)
    case ixon(Bool) // 开启软件流控 (XON/XOFF)
    case ixany(Bool) // 允许任意键恢复暂停输出
    case ixoff(Bool) // 发送 XON/XOFF 字符
    case iutf8(Bool) // UTF-8 编码模式 (RFC 8160)

    // MARK: - 本地模式

    case isig(Bool) // 使能信号字符 (Ctrl+C, Ctrl+Z 等)
    case icanon(Bool) // 规范输入模式 (行缓冲)
    case echo(Bool) // 本地/远程回显
    case echoe(Bool) // 视觉擦除退格字符
    case echok(Bool) // 清行后自动换行
    case iexten(Bool) // 使能扩展输入处理 (Ctrl+W/Ctrl+V)
    case echoctl(Bool) // 显式打印控制字符 (如 ^C)
    case echoke(Bool) // Visual erase for VKILL

    // MARK: - 输出模式

    case opost(Bool) // 开启输出后处理
    case onlcr(Bool) // 将输出的 NL (\n) 翻译为 CR-NL (\r\n)

    // MARK: - 波特率

    case ispeed(UInt32) // 输入波特率
    case ospeed(UInt32) // 输出波特率

    // MARK: - 底层 Opcode 映射表

    private var opcode: UInt8 {
        switch self {
        case .vintr: 1
        case .vquit: 2
        case .verase: 3
        case .vkill: 4
        case .veof: 5
        case .vstart: 8
        case .vstop: 9
        case .vsusp: 10
        case .vwerase: 13
        case .vlnext: 14
        case .icrnl: 36
        case .ixon: 38
        case .ixany: 39
        case .ixoff: 40
        case .iutf8: 42
        case .isig: 50
        case .icanon: 51
        case .echo: 53
        case .echoe: 54
        case .echok: 55
        case .iexten: 59
        case .echoctl: 60
        case .echoke: 61
        case .opost: 70
        case .onlcr: 72
        case .ispeed: 128
        case .ospeed: 129
        }
    }

    // MARK: - 底层 32位数值映射 (全部转为 UInt32 准备序列化)

    private var rawValue: UInt32 {
        switch self {
        case let .vintr(v), let .vquit(v), let .verase(v), let .vkill(v),
             let .veof(v), let .vstart(v), let .vstop(v), let .vsusp(v),
             let .vwerase(v), let .vlnext(v):
            v.uint32

        case let .icrnl(b), let .ixon(b), let .ixany(b), let .ixoff(b), let .iutf8(b),
             let .isig(b), let .icanon(b), let .echo(b), let .echoe(b), let .echok(b),
             let .iexten(b), let .echoctl(b), let .echoke(b), let .opost(b), let .onlcr(b):
            b ? 1 : 0

        case let .ispeed(rate), let .ospeed(rate):
            rate
        }
    }

    /// 序列化为 RFC 4254 标准的大端序 5 字节数据包 [Opcode (1 byte) + Value (4 bytes Big-Endian)]
    public var bytes: [UInt8] {
        var result = [opcode]
        result.append(contentsOf: rawValue.bigEndian.bytes)
        return result
    }
}

// MARK: - 便捷生成器扩展

public extension [TerminalMode] {
    /// 将配置数组转换为可直接传给 libssh 的 [UInt8] 字节流 (自动追加 TTY_OP_END)
    var serializedBytes: [UInt8] {
        var bytes = flatMap(\.bytes)
        bytes.append(0) // 追加 TTY_OP_END (0)
        return bytes
    }

    /// 开箱即用的终端标准配置
    static var defaultTerminalModes: [TerminalMode] {
        [
            // 特殊控制字符映射
            .verase(0x7F), // Backspace 键设为 ASCII DEL (127)
            .vintr(0x03), // Ctrl+C (3)
            .vkill(0x15), // Ctrl+U (21)
            .vwerase(0x17), // Ctrl+W (23)

            // 基础控制与字符映射
            .echo(true), // 开启回显
            .icrnl(true), // 回车转换行
            .onlcr(true), // 换行转回车换行 (防止阶梯排版错乱)
            .iutf8(true), // 开启 UTF-8 支持

            // 交互体验
            .echoctl(true), // 显式打印 Ctrl+C 为 ^C
            .echoe(true), // 擦除退格字符
            .echok(true), // 清行自动换行
            .echoke(true),

            // 作业与信号控制
            .isig(true), // 开启信号
            .iexten(true), // 开启扩展按键

            // 流控与波特率
            .ixon(true), // 软件流控
            .ixany(true),
            .ispeed(38400),
            .ospeed(38400),
        ]
    }
}
