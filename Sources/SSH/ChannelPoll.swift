// FoxTerm | ChannelPoll.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation

class ChannelStream {
    let handle: OpaquePointer
    let output: OutputStream
    let outerr: OutputStream?
    let write: InputStream?
    var continuation: CheckedContinuation<Void, Never>?
    var totalSize: Int64 = 0
    var onProgress: ((_ current: Int64, _ total: Int64) -> Bool)?
    var writeBuffer = [UInt8]()

    init(
        handle: OpaquePointer, output: OutputStream, outerr: OutputStream?, write: InputStream?,
        continuation: CheckedContinuation<Void, Never>?, totalSize: Int64,
        onProgress: ((Int64, Int64) -> Bool)?
    ) {
        self.handle = handle
        self.output = output
        self.outerr = outerr
        self.write = write
        self.continuation = continuation
        self.totalSize = totalSize
        self.onProgress = onProgress
    }
}

class ChannelPoll {
    var socketFD: Int32 = -1
    var bufferSize = 0x10000
    let queue = DispatchQueue(label: "app.foxterm.channeltask.queue")
    var _isLooping: Bool = false
    let mutex: Mutex = .init()
    private var _tasks: [ChannelStream] = []
}

extension ChannelPoll {
    func register(
        handle: OpaquePointer, output: OutputStream, outerr: OutputStream?, write: InputStream?,
        totalSize: Int64 = 0,
        progress: ((_ current: Int64, _ total: Int64) -> Bool)? = nil
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let task = ChannelStream(
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
        defer {
            mutex.with { _isLooping = false }
        }
        let data: Buffer<CChar> = .init(bufferSize)
        var progressTracker: [OpaquePointer: Int64] = [:]
        while true {
            // 拿到当前的引用列表
            let currentTasks = mutex.with { _tasks }
            if currentTasks.isEmpty { break }

            var pollFd = pollfd()
            pollFd.fd = socketFD
            pollFd.events = 0
            pollFd.revents = 0

            var wantsRead = false
            var wantsWrite = false
            for t in currentTasks {
                setupStreams(for: t)

                // 只要通道在运行，默认都需要监听读（包括标准输出和标准错误）
                wantsRead = true

                // 检查是否有数据等待写入
                if !t.writeBuffer.isEmpty || (t.write?.hasBytesAvailable == true) {
                    wantsWrite = true
                }
            }
            if wantsRead { pollFd.events |= POLLIN.int16 | POLLPRI.int16 }
            if wantsWrite { pollFd.events |= POLLOUT.int16 }

            let pollRc = poll(&pollFd, 1, 10)
            if pollRc < 0 {
                if errno != EINTR {
                    cleanupAll()
                    break
                }
                // cleanupAll()
                continue
            }
            let sysRevents = pollFd.revents
            // 发生错误或挂断
            if (sysRevents & POLLERR.int16) != 0 || (sysRevents & POLLHUP.int16) != 0 {
                cleanupAll()
                break
            }
            // if pollRc == 0 { continue }
            let isTimeout = pollRc == 0
            let canRead = isTimeout || (sysRevents & (POLLIN.int16 | POLLPRI.int16)) != 0
            let canWrite = isTimeout || (sysRevents & POLLOUT.int16) != 0

            if !canRead, !canWrite {
                continue
            }

            var tasksToRemove = Set<OpaquePointer>()
            for task in currentTasks {
                var currentIncrement: Int64 = 0
                var hasReadError = false
                var hasWriteError = false
                var isEofReached = false

                // 1. 先处理读取
                if canRead {
                    let r = read(data: data, handle: task.handle, output: task.output, stream_id: 0)
                    if r < 0 {
                        if r != LIBSSH2_ERROR_EAGAIN { hasReadError = true }
                    } else if r == 0 {
                        if libssh2_channel_eof(task.handle) != 0 { isEofReached = true }
                    } else {
                        currentIncrement += r
                    }
                }

                // 2. 处理标准错误
                if canRead && !hasReadError && !isEofReached, let outerr = task.outerr {
                    let r = read(data: data, handle: task.handle, output: outerr, stream_id: 1)
                    if r < 0 {
                        if r != LIBSSH2_ERROR_EAGAIN { hasReadError = true }
                    } else if r > 0 {
                        currentIncrement += r
                        isEofReached = false
                    }
                }

                // 3. 处理写入
                if canWrite {
                    let w = write(data: data, task: task)
                    if w < 0 {
                        if w != LIBSSH2_ERROR_EAGAIN { hasWriteError = true }
                    } else {
                        currentIncrement += w
                    }
                }

                // 4. 更新进度
                if currentIncrement > 0 {
                    let total = (progressTracker[task.handle] ?? 0) + currentIncrement
                    progressTracker[task.handle] = total
                    if task.onProgress?(total, task.totalSize) == false {
                        tasksToRemove.insert(task.handle)
                        continue
                    }
                }
                // 发生实质性错误，移出队列
                if hasReadError || hasWriteError {
                    tasksToRemove.insert(task.handle)
                    continue
                }

                // 只有满足 EOF 且数据完全排空，才移出队列
                if isEofReached {
                    tasksToRemove.insert(task.handle)
                    continue
                }
            }

            if !tasksToRemove.isEmpty {
                let toRemove = Array(tasksToRemove)
                toRemove.forEach { progressTracker.removeValue(forKey: $0) }
                remove(toRemove)
            }
        }
    }

    /// 当发生系统级网络错误（poll 返回 < 0）时，强制清理所有当前正在运行的任务
    private func cleanupAll() {
        let allHandles = mutex.with { _tasks.map(\.handle) }
        if !allHandles.isEmpty {
            #if DEBUG
                print("🚨 触发全局清理，正在移除 \(allHandles.count) 个任务")
            #endif
            remove(allHandles)
        }
    }

    private func setupStreams(for task: ChannelStream) {
        if task.output.streamStatus == .notOpen { task.output.open() }
        if task.outerr?.streamStatus == .notOpen { task.outerr?.open() }
        if task.write?.streamStatus == .notOpen { task.write?.open() }
    }

    func remove(_ tasksToRemove: [OpaquePointer]) {
        mutex.with {
            if tasksToRemove.isEmpty { return }

            #if DEBUG
                for handle in tasksToRemove {
                    print("🚨 准备移除 Handle: \(handle), 当前任务总数: \(_tasks.count)")
                }
            #endif

            var removedTasks: [ChannelStream] = []
            removedTasks = _tasks.filter { tasksToRemove.contains($0.handle) }
            _tasks.removeAll { task in
                tasksToRemove.contains(task.handle)
            }

            for t in removedTasks {
                t.output.close()
                t.outerr?.close()
                t.write?.close()
                t.continuation?.resume()
            }
        }
    }

    func read(data: Buffer<CChar>, handle: OpaquePointer, output: OutputStream, stream_id: Int32)
        -> Int64
    {
        let n = mutex.with { libssh2_channel_read_ex(handle, stream_id, data.buffer, data.count) }
        if n > 0 {
            output.write(data.buffer, maxLength: n)
            return n.int64 // 💡 显式强转成统一的 Int
        } else if n == LIBSSH2_ERROR_EAGAIN {
            return 0
        } else {
            return -1
        }
    }

    func write(data: Buffer<CChar>, task: ChannelStream) -> Int64 {
        // 1. 如果之前有残留未发完的数据，优先发送残留数据
        if !task.writeBuffer.isEmpty {
            let remainingData = task.writeBuffer
            let rc = mutex.with {
                libssh2_channel_write_ex(task.handle, 0, remainingData, remainingData.count)
            }

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
            let written = mutex.with {
                libssh2_channel_write_ex(task.handle, 0, data.buffer, nread)
            }

            if written > 0 {
                if written < nread {
                    // 如果只写了一部分，把没写完的塞进该任务自己的 writeBuffer 缓存起来
                    let leftCount = nread - written
                    let pointer = UnsafeRawPointer(data.buffer).advanced(by: written)
                    let leftData = pointer.bindMemory(to: UInt8.self, capacity: leftCount)
                    task.writeBuffer.append(
                        contentsOf: Array(UnsafeBufferPointer(start: leftData, count: leftCount))
                    )
                }
                return written.int64
            } else if written == LIBSSH2_ERROR_EAGAIN {
                let rawData = UnsafeRawPointer(data.buffer).bindMemory(
                    to: UInt8.self, capacity: nread
                )
                task.writeBuffer.append(
                    contentsOf: Array(UnsafeBufferPointer(start: rawData, count: nread))
                )
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
