// FoxTerm | Socket.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation
import libetos

public extension SSH {
    /// 发起标准的 TCP 直接连接
    /// 使用 libetos 库进行非阻塞/带超时的 Socket 初始化
    /// - Returns: 是否连接成功
    func connect() async -> Bool {
        await io.call { [self] in
            // 初始化套接字，设置主机、端口、超时及 TTL/窗口缩放等参数
            fd = etos_socket_connect(host, port.int32, timeout.int32, ttl, window, scale)
            // 启用 Socket 层的 KeepAlive 机制防止链路被运营商中间设备切断
            etos_socket_keepalive(fd)
            return isConnected
        }
    }

    /// 通过代理服务器发起连接
    /// 支持 SOCKS5、HTTP 代理以及 SSL 加密代理
    /// - Parameter proxy: 代理配置信息对象
    /// - Returns: 是否连接成功
    func connect(_ proxy: ProxyInfo) async -> Bool {
        await io.call { [self] in
            // 调用 etos 代理连接接口，处理握手、认证及可选的 SSL/SNI 验证
            fd = proxy.connect(shost: host, sport: port, timeout: timeout)
            etos_socket_keepalive(fd)
            return isConnected
        }
    }

    /// 内部数据发送方法
    /// - Parameters:
    ///   - fd: 套接字句柄
    ///   - buffer: 待发送数据指针
    ///   - length: 数据长度
    ///   - flags: 系统 send 标志位
    /// - Returns: 实际发送的字节数，负值代表错误
    func send(fd: Int32, buffer: UnsafeRawPointer, length: ssize_t, flags: CInt) -> Int {
        let size = etos_socket_send(fd, buffer, length, flags)
        guard size >= 0 else {
            return size
        }
        // 原子增加全局发送流量统计
        sendSize.add(size)
        return size
    }

    /// 内部数据接收方法
    /// - Parameters:
    ///   - fd: 套接字句柄
    ///   - buffer: 接收缓冲区指针
    ///   - length: 预期接收长度
    ///   - flags: 系统 recv 标志位
    /// - Returns: 实际接收的字节数，负值代表错误
    func recv(fd: Int32, buffer: UnsafeMutableRawPointer, length: ssize_t, flags: CInt)
        -> Int
    {
        let size = etos_socket_recv(fd, buffer, length, flags)
        guard size >= 0 else {
            return size
        }
        // 原子增加全局接收流量统计
        recvSize.add(size)
        return size
    }

    #if DEBUG
        func printIsolationCompressionRatio() {
            // 1. 获取原始的 Int64 数据
            let rawSendBytes = sendSize.load
            let rawRecvBytes = recvSize.load

            let rawRowSendBytes = channelPoll.sendSize.load
            let rawRowRecvBytes = channelPoll.recvSize.load

            // 2. 将数据强转为 Double 类型，用于高精度浮点数计算
            let send = Double(rawSendBytes)
            let recv = Double(rawRecvBytes)

            let rowSend = Double(rawRowSendBytes)
            let rowRecv = Double(rawRowRecvBytes)

            print("====== 独立连接压缩率精准分析 ======")

            // 3. 计算发送端压缩率
            if rawRowSendBytes > 0 {
                let sendRatio = (send / rowSend) * 100.0
                print(String(format: "发送端 (Output): 原始 %lld 字节 -> 物理发出 %lld 字节 [ 压缩至: %.2f%% ]", rawRowSendBytes, rawSendBytes, sendRatio))
            } else {
                print("发送端 (Output): 暂无业务数据发送。")
            }

            // 4. 计算接收端压缩率
            if rawRowRecvBytes > 0 {
                let recvRatio = (recv / rowRecv) * 100.0
                print(String(format: "接收端 (Input) : 物理收到 %lld 字节 -> 原始还原 %lld 字节 [ 压缩至: %.2f%% ]", rawRecvBytes, rawRowRecvBytes, recvRatio))
            } else {
                print("接收端 (Input) : 暂无业务数据接收。")
            }
        }
    #endif
    /// 检查 Socket 是否已关闭（句柄为 -1）
    var closed: Bool {
        fd == -1
    }

    /// 检查底层 Socket 是否处于已连接状态
    var isConnected: Bool {
        etos_socket_is_connect(fd)
    }

    /// 等待套接字就绪（配合 libssh2 的非阻塞 IO）
    func waitSocket() -> Bool {
        guard rawSession != nil else {
            return false
        }

        // 获取 libssh2 期望的等待方向
        let dir = libssh2_session_block_directions(rawSession)

        // 如果没有任何方向需要等待，说明不需要阻塞，直接返回 true 驱动下一步
        if dir == 0 {
            return true
        }

        // 彻底废弃 poll 避免闪退，直接休眠 10 毫秒（10,000 微秒）
        // 这会将当前线程的 CPU 时间片让出，防止无脑空转
        usleep(10000)

        // 返回 true 让 libssh2 继续尝试执行下一步非阻塞操作
        return true
    }

    /// 执行 Socket 半关闭操作
    /// - Parameter how: 关闭类型
    func shutdown(_ how: Shout) {
        etos_socket_shutdown(fd, how.rawValue)
    }

    /// 彻底关闭并释放 Socket 资源
    /// 包含互斥锁保护以确保线程安全，并释放 SSL 上下文
    func closeSocket() {
        // 先停止读取流
        shutdown(.read)
        channelPoll.mutex.with {
            etos_socket_close(fd)
            fd = -1
            #if DEBUG
                print("♻️", "Socket 连接已彻底释放")
            #endif
        }
    }
}
