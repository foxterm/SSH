// FoxTerm | ChannelTask.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation

class SSHChannelTask {
    let handle: OpaquePointer
    let output: OutputStream
    let outerr: OutputStream?
    let write: InputStream?
    var continuation: CheckedContinuation<Void, Never>?
    var totalSize: Int64 = 0
    var onProgress: ((_ current: Int64, _ total: Int64) -> Bool)?
    var writeBuffer = [UInt8]()

    init(handle: OpaquePointer, output: OutputStream, outerr: OutputStream?, write: InputStream?, continuation: CheckedContinuation<Void, Never>?, totalSize: Int64, onProgress: ((Int64, Int64) -> Bool)?) {
        self.handle = handle
        self.output = output
        self.outerr = outerr
        self.write = write
        self.continuation = continuation
        self.totalSize = totalSize
        self.onProgress = onProgress
    }
}

class ChannelTask {
    let bufferSize = 0x10000 // 64K
    let queue = DispatchQueue(label: "app.foxterm.channeltask.queue")
    var _isLooping: Bool = false
    let mutex: Mutex = .init()
    private var _tasks: [SSHChannelTask] = []
}

extension ChannelTask {
    func register(handle: OpaquePointer, output: OutputStream, outerr: OutputStream?, write: InputStream?, totalSize: Int64 = 0,
                  progress: ((_ current: Int64, _ total: Int64) -> Bool)? = nil) async
    {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let task = SSHChannelTask(
                handle: handle,
                output: output,
                outerr: outerr,
                write: write,
                continuation: continuation,
                totalSize: totalSize,
                onProgress: progress
            )

            mutex.with {
                _tasks.append(task)
                if !_isLooping {
                    _isLooping = true
                    queue.async { [weak self] in
                        self?.runMasterLoop()
                    }
                }
            }
        }
    }

    /// 外部主动取消（如关闭标签页、中断长命令）时的强行注销与解挂接口
    func unregister(handle: OpaquePointer) {
        remove([handle])
    }

    func runMasterLoop() {
        let data: Buffer<CChar> = .init(bufferSize)
        var progressTracker: [OpaquePointer: Int64] = [:]

        while true {
            // 拿到当前的引用列表
            let currentTasks = mutex.with { _tasks }
            if currentTasks.isEmpty { break }

            var poolls: [LIBSSH2_POLLFD] = []
            for t in currentTasks {
                // 检查流状态（防止在流关闭后继续操作）
                setupStreams(for: t)

                var poll = LIBSSH2_POLLFD()
                poll.type = LIBSSH2_POLLFD_CHANNEL.uint8
                poll.fd.channel = t.handle
                poll.revents = 0

                var events = LIBSSH2_POLLFD_POLLIN
                if t.outerr != nil { events |= LIBSSH2_POLLFD_POLLEXT }

                // 直接访问 class 属性，无需回写
                if !t.writeBuffer.isEmpty || (t.write?.hasBytesAvailable == true) {
                    events |= LIBSSH2_POLLFD_POLLOUT
                }
                poll.events = events.uint
                poolls.append(poll)
            }

            // poll 超时时间建议稍短或根据任务数动态调整
            let pollRc = libssh2_poll(&poolls, poolls.count.uint32, 10)

            if pollRc < 0 {
                cleanupAll()
                break
            }
            if pollRc == 0 { continue }

            var tasksToRemove = Set<OpaquePointer>()

            for (index, task) in currentTasks.enumerated() {
                let revents = poolls[index].revents.int32
                if revents == 0 { continue } // 没有任何事件，跳过
                var currentIncrement: Int64 = 0
                // A. 处理读取
                if (revents & LIBSSH2_POLLFD_POLLIN) != 0 {
                    let r = read(data: data, handle: task.handle, output: task.output, stream_id: 0)
                    if r < 0 { tasksToRemove.insert(task.handle) } else { currentIncrement += r }
                }

                // B. 处理标准错误
                if (revents & LIBSSH2_POLLFD_POLLEXT) != 0, let outerr = task.outerr {
                    let r = read(data: data, handle: task.handle, output: outerr, stream_id: 1)
                    if r < 0 { tasksToRemove.insert(task.handle) } else { currentIncrement += r }
                }

                // C. 处理写入 (无需手动回写 _tasks，因为是 Class)
                if (revents & LIBSSH2_POLLFD_POLLOUT) != 0 {
                    let w = write(data: data, task: task)
                    if w < 0 { tasksToRemove.insert(task.handle) } else { currentIncrement += w }
                }

                // D. 进度与 EOF 检查
                if currentIncrement > 0 {
                    let total = (progressTracker[task.handle] ?? 0) + currentIncrement
                    progressTracker[task.handle] = total
                    if task.onProgress?(total, task.totalSize) == false {
                        tasksToRemove.insert(task.handle)
                    }
                }

                // 检查是否有关闭信号（这是防止闪退的关键判定）
                let closeMask = Int32(LIBSSH2_POLLFD_CHANNEL_CLOSED) | Int32(LIBSSH2_POLLFD_SESSION_CLOSED)
                if (revents & closeMask) != 0 {
                    tasksToRemove.insert(task.handle)
                    continue
                }
                if libssh2_channel_eof(task.handle) != 0 {
                    tasksToRemove.insert(task.handle)
                }
            }

            if !tasksToRemove.isEmpty {
                let toRemove = Array(tasksToRemove)
                toRemove.forEach { progressTracker.removeValue(forKey: $0) }
                remove(toRemove)
            }
        }
        mutex.with { _isLooping = false }
    }

    /// 当发生系统级网络错误（poll 返回 < 0）时，强制清理所有当前正在运行的任务
    private func cleanupAll() {
        let allHandles = mutex.with { _tasks.map { $0.handle } }
        if !allHandles.isEmpty {
            #if DEBUG
                print("🚨 触发全局清理，正在移除 \(allHandles.count) 个任务")
            #endif
            remove(allHandles)
        }
    }

    private func setupStreams(for task: SSHChannelTask) {
        if task.output.streamStatus == .notOpen { task.output.open() }
        if task.outerr?.streamStatus == .notOpen { task.outerr?.open() }
        if task.write?.streamStatus == .notOpen { task.write?.open() }
    }

    func remove(_ tasksToRemove: [OpaquePointer]) {
        if tasksToRemove.isEmpty { return }

        #if DEBUG
            for handle in tasksToRemove {
                print("🚨 准备移除 Handle: \(handle), 当前任务总数: \(_tasks.count)")
            }
        #endif

        var removedTasks: [SSHChannelTask] = []
        mutex.with {
            removedTasks = _tasks.filter { tasksToRemove.contains($0.handle) }
            _tasks.removeAll { task in
                tasksToRemove.contains(task.handle)
            }
        }

        for t in removedTasks {
            t.output.close()
            t.outerr?.close()
            t.write?.close()
            t.continuation?.resume()
        }
    }

    func read(data: Buffer<CChar>, handle: OpaquePointer, output: OutputStream, stream_id: Int32) -> Int64 {
        let n = libssh2_channel_read_ex(handle, stream_id, data.buffer, data.count)
        if n > 0 {
            output.write(data.buffer, maxLength: n)
            return n.int64 // 💡 显式强转成统一的 Int
        } else if n == LIBSSH2_ERROR_EAGAIN {
            return 0
        } else {
            return -1
        }
    }

    /// 💡 注意：为了能修改 task 内部的 writeBuffer，我们需要传入 inout 类型的 task
    func write(data: Buffer<CChar>, task: SSHChannelTask) -> Int64 {
        // 1. 如果之前有残留未发完的数据，优先发送残留数据
        if !task.writeBuffer.isEmpty {
            let remainingData = task.writeBuffer
            let rc = libssh2_channel_write_ex(task.handle, 0, remainingData, remainingData.count)

            if rc > 0 {
                if rc >= remainingData.count {
                    task.writeBuffer.removeAll(keepingCapacity: true)
                    return rc.int64
                } else {
                    task.writeBuffer.removeFirst(rc)
                    return rc.int64
                }
            } else if rc == LIBSSH2_ERROR_EAGAIN {
                return 0 // 缓冲区依然满，直接退回主循环，不卡死线程
            } else {
                return -1 // 真正发生错误
            }
        }

        // 2. 之前没有残留数据，从 InputStream 读取新数据
        guard let input = task.write, input.hasBytesAvailable else { return 0 }

        let nread = input.read(data.buffer, maxLength: data.count)
        if nread > 0 {
            // 💡 只调用一次，绝不用 while 循环死等！
            let written = libssh2_channel_write_ex(task.handle, 0, data.buffer, nread)

            if written > 0 {
                if written < nread {
                    // 如果只写了一部分，把没写完的塞进该任务自己的 writeBuffer 缓存起来
                    let leftCount = nread - written
                    let pointer = UnsafeRawPointer(data.buffer).advanced(by: written)
                    let leftData = pointer.bindMemory(to: UInt8.self, capacity: leftCount)
                    task.writeBuffer.append(contentsOf: Array(UnsafeBufferPointer(start: leftData, count: leftCount)))
                }
                return written.int64
            } else if written == LIBSSH2_ERROR_EAGAIN {
                // 🚨 核心修复：遇到 EAGAIN，说明一字节都没写进去。
                // 把这次读出来的全部数据暂存进 writeBuffer，下次 POLLOUT 激活时再发，同时立刻返回 0 释放线程！
                let rawData = UnsafeRawPointer(data.buffer).bindMemory(to: UInt8.self, capacity: nread)
                task.writeBuffer.append(contentsOf: Array(UnsafeBufferPointer(start: rawData, count: nread)))
                return 0
            } else {
                return -1
            }
        } else if nread < 0 {
            return -1
        }

        return 0
    }
}
