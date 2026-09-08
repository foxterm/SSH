// FoxTerm | ChannelPoll.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation
import Sync

class ChannelStream {
    let wait: WaitGroup = .init()
    let handle: OpaquePointer
    let output: OutputStream
    let outerr: OutputStream?
    let write: InputStream?
    var continuation: CheckedContinuation<Void, Never>?
    var totalSize: Int64 = 0
    var onProgress: ((_ current: Int64, _ total: Int64) -> Bool)?

    // 基于游标的环形/偏移 Buffer，避免 removeFirst 的 O(N) 内存拷贝
    var writeBuffer = [UInt8]()
    var writeBufferOffset = 0

    /// 线程安全与生命周期控制标记，避免外部注销或释放句柄后引发悬空指针闪退
    var isCancelled: Bool = false

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

    var hasPendingWrite: Bool {
        writeBufferOffset < writeBuffer.count
    }

    func appendWriteData(from pointer: UnsafePointer<UInt8>, count: Int) {
        if writeBufferOffset > 0, writeBufferOffset == writeBuffer.count {
            writeBuffer.removeAll(keepingCapacity: true)
            writeBufferOffset = 0
        }
        writeBuffer.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
    }
}

class ChannelPoll {
    var bufferSize = 0x10000 // 64KB
    let queue = DispatchQueue(label: "app.foxterm.channeltask.queue")
    var _isLooping: Bool = false
    let mutex: Mutex = .init()

    private var _tasks: [OpaquePointer: ChannelStream] = [:]
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

            mutex.withLock {
                _tasks[handle] = task
                if !_isLooping {
                    _isLooping = true
                    queue.async { [weak self] in
                        self?.runMasterLoop()
                    }
                }
            }
        }
    }

    func unregister(handle: OpaquePointer) {
        remove([handle])
    }

    func runMasterLoop() {
        defer {
            mutex.withLock { _isLooping = false }
        }

        let data: Buffer<CChar> = .init(bufferSize)
        var progressTracker: [OpaquePointer: Int64] = [:]

        while true {
            // 1. 在锁保护下提取有效（未取消）的 Task
            let currentTasks = mutex.withLock {
                _tasks.values.filter { !$0.isCancelled }
            }
            if currentTasks.isEmpty {
                break
            }

            // 2. 构建 LIBSSH2_POLLFD 数组
            var validTasks: [ChannelStream] = []
            var pollFds: [LIBSSH2_POLLFD] = []
            pollFds.reserveCapacity(currentTasks.count)

            // 锁内仅提取句柄和计算状态，避免在锁内执行 setupStreams 导致的耗时阻塞
            mutex.withLock {
                for t in currentTasks {
                    guard let existingTask = _tasks[t.handle], !existingTask.isCancelled else { continue }

                    var pollFd = LIBSSH2_POLLFD()
                    pollFd.type = LIBSSH2_POLLFD_CHANNEL.uint8
                    pollFd.fd.channel = existingTask.handle

                    var events = LIBSSH2_POLLFD_POLLIN | LIBSSH2_POLLFD_POLLEXT
                    if existingTask.hasPendingWrite || (existingTask.write?.hasBytesAvailable == true) {
                        events |= LIBSSH2_POLLFD_POLLOUT
                    }

                    pollFd.events = events.uint
                    pollFd.revents = 0

                    pollFds.append(pollFd)
                    validTasks.append(existingTask)
                }
            }

            if validTasks.isEmpty {
                break
            }

            // 锁外统一初始化 Stream 状态
            for task in validTasks {
                setupStreams(for: task)
            }

            // 3. 调用 libssh2_poll (超时 10ms)
            let pollRc = mutex.withLock {
                libssh2_poll(&pollFds, pollFds.count.uint32, 10)
            }

            if pollRc < 0 {
                cleanupAll()
                break
            }

            var tasksToRemove = Set<OpaquePointer>()

            // 4. 处理轮询事件响应
            for (idx, task) in validTasks.enumerated() {
                task.wait.add()
                defer {
                    task.wait.done()
                }

                // 读取/写入前校验：防范 poll 阻塞 10ms 期间外部触发了注销
                let isTaskAlive = mutex.withLock {
                    if let t = _tasks[task.handle], !t.isCancelled {
                        return true
                    }
                    return false
                }

                if !isTaskAlive {
                    tasksToRemove.insert(task.handle)
                    continue
                }

                let revents = pollFds[idx].revents.int32
                let isChannelClosed = (revents & LIBSSH2_POLLFD_CHANNEL_CLOSED) != 0
                let isTimeout = (pollRc == 0)

                let canRead = isTimeout || isChannelClosed || (revents & (LIBSSH2_POLLFD_POLLIN | LIBSSH2_POLLFD_POLLEXT)) != 0
                let canWrite = !isChannelClosed && (isTimeout || (revents & LIBSSH2_POLLFD_POLLOUT) != 0)

                var currentIncrement: Int64 = 0
                var hasReadError = false
                var hasWriteError = false
                var isStdoutEof = false
                var isStderrEof = (task.outerr == nil)

                // 4.1 读取 stdout (stream_id: 0)
                if canRead {
                    let r = read(data: data, handle: task.handle, output: task.output, stream_id: 0)
                    if r < 0 {
                        if r != LIBSSH2_ERROR_EAGAIN {
                            hasReadError = true
                        }
                    } else if r == 0 {
                        isStdoutEof = checkChannelEof(handle: task.handle)
                    } else {
                        currentIncrement += r
                    }
                }

                // 4.2 读取 stderr (stream_id: 1)
                if canRead && !hasReadError && !isStderrEof, let outerr = task.outerr {
                    let r = read(data: data, handle: task.handle, output: outerr, stream_id: 1)
                    if r < 0 {
                        if r != LIBSSH2_ERROR_EAGAIN {
                            hasReadError = true
                        }
                    } else if r == 0 {
                        isStderrEof = checkChannelEof(handle: task.handle)
                    } else {
                        currentIncrement += r
                    }
                }

                // 4.3 处理写入
                if canWrite && !hasReadError {
                    let w = write(data: data, task: task)
                    if w < 0 {
                        if w != LIBSSH2_ERROR_EAGAIN {
                            hasWriteError = true
                        }
                    } else {
                        currentIncrement += w
                    }
                }

                // 4.4 进度更新
                if currentIncrement > 0 {
                    let total = (progressTracker[task.handle] ?? 0) + currentIncrement
                    progressTracker[task.handle] = total
                    if task.onProgress?(total, task.totalSize) == false {
                        tasksToRemove.insert(task.handle)
                        continue
                    }
                }

                // 4.5 退出与清理条件判断
                let bothEofReached = isStdoutEof && isStderrEof
                let isHasPollErr = (revents & (LIBSSH2_POLLFD_POLLERR | LIBSSH2_POLLFD_POLLHUP)) != 0

                if hasReadError || hasWriteError || (isChannelClosed && currentIncrement == 0) || bothEofReached || isHasPollErr {
                    tasksToRemove.insert(task.handle)
                    continue
                }
            }

            if !tasksToRemove.isEmpty {
                for handle in tasksToRemove {
                    progressTracker.removeValue(forKey: handle)
                }
                remove(Array(tasksToRemove))
            }
        }
    }

    private func checkChannelEof(handle: OpaquePointer) -> Bool {
        mutex.withLock {
            guard let t = _tasks[handle], !t.isCancelled else { return false }
            return libssh2_channel_eof(handle) != 0
        }
    }

    private func cleanupAll() {
        let allHandles = mutex.withLock { Array(_tasks.keys) }
        if !allHandles.isEmpty {
            remove(allHandles)
        }
    }

    private func setupStreams(for task: ChannelStream) {
        if task.output.streamStatus == .notOpen {
            task.output.open()
        }
        if task.outerr?.streamStatus == .notOpen {
            task.outerr?.open()
        }
        if task.write?.streamStatus == .notOpen {
            task.write?.open()
        }
    }

    func remove(_ tasksToRemove: [OpaquePointer]) {
        var removedTasks: [ChannelStream] = []

        mutex.withLock {
            if tasksToRemove.isEmpty {
                return
            }

            for handle in tasksToRemove {
                if let task = _tasks.removeValue(forKey: handle) {
                    task.isCancelled = true
                    removedTasks.append(task)
                }
            }
        }

        for t in removedTasks {
            t.wait.wait()
            t.output.close()
            t.outerr?.close()
            t.write?.close()
            t.continuation?.resume()
            t.continuation = nil
        }
    }

    func read(data: Buffer<CChar>, handle: OpaquePointer, output: OutputStream, stream_id: Int32) -> Int64 {
        let n = mutex.withLock { () -> Int in
            guard let task = _tasks[handle], !task.isCancelled else { return -1 }
            return libssh2_channel_read_ex(handle, stream_id, data.buffer, data.count)
        }
        if n > 0 {
            // 确保全量写入 OutputStream，避免高并发或缓存区不足时漏数据
            let success = writeFully(to: output, buffer: UnsafeRawPointer(data.buffer).assumingMemoryBound(to: UInt8.self), count: n)
            return success ? n.int64 : -1
        } else if n == LIBSSH2_ERROR_EAGAIN {
            return 0
        } else if n == 0 {
            return 0
        } else {
            return -1
        }
    }

    private func writeFully(to output: OutputStream, buffer: UnsafePointer<UInt8>, count: Int) -> Bool {
        var totalWritten = 0
        while totalWritten < count {
            let written = output.write(buffer.advanced(by: totalWritten), maxLength: count - totalWritten)
            if written <= 0 {
                return false
            }
            totalWritten += written
        }
        return true
    }

    func write(data: Buffer<CChar>, task: ChannelStream) -> Int64 {
        if task.hasPendingWrite {
            let pendingCount = task.writeBuffer.count - task.writeBufferOffset

            let rc = task.writeBuffer.withUnsafeBufferPointer { bp -> Int in
                guard let baseAddr = bp.baseAddress else { return 0 }
                let ptr = baseAddr.advanced(by: task.writeBufferOffset)
                return mutex.withLock { () -> Int in
                    guard let t = _tasks[task.handle], !t.isCancelled else { return -1 }
                    return libssh2_channel_write_ex(task.handle, 0, ptr, pendingCount)
                }
            }

            if rc > 0 {
                task.writeBufferOffset += rc
                if task.writeBufferOffset >= task.writeBuffer.count {
                    task.writeBuffer.removeAll(keepingCapacity: true)
                    task.writeBufferOffset = 0
                }
                return rc.int64
            } else if rc == LIBSSH2_ERROR_EAGAIN {
                return 0
            } else {
                return -1
            }
        }

        guard let input = task.write, input.hasBytesAvailable else { return 0 }

        let nread = input.read(data.buffer, maxLength: data.count)
        if nread > 0 {
            let written = mutex.withLock { () -> Int in
                guard let t = _tasks[task.handle], !t.isCancelled else { return -1 }
                return libssh2_channel_write_ex(task.handle, 0, data.buffer, nread)
            }

            if written > 0 {
                if written < nread {
                    let leftCount = nread - written
                    let rawPtr = UnsafeRawPointer(data.buffer).advanced(by: written).assumingMemoryBound(to: UInt8.self)
                    task.appendWriteData(from: rawPtr, count: leftCount)
                }
                return written.int64
            } else if written == LIBSSH2_ERROR_EAGAIN {
                let rawPtr = UnsafeRawPointer(data.buffer).assumingMemoryBound(to: UInt8.self)
                task.appendWriteData(from: rawPtr, count: nread)
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
