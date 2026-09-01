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

    // 💡 基于游标的环形/偏移 Buffer，避免 removeFirst 的 O(N) 内存拷贝
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
    let mutex: NSLock = .init()

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

            // 2. 构建 LIBSSH2_POLLFD 数组，并做二次合法性校验
            var validTasks: [ChannelStream] = []
            var pollFds: [LIBSSH2_POLLFD] = []
            pollFds.reserveCapacity(currentTasks.count)

            mutex.withLock {
                for t in currentTasks {
                    guard let existingTask = _tasks[t.handle], !existingTask.isCancelled else { continue }

                    setupStreams(for: existingTask)

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

            // 3. 调用 libssh2_poll (超时 10ms)
            let pollRc = pollFds.withUnsafeMutableBufferPointer { bp -> Int32 in
                guard let baseAddress = bp.baseAddress, bp.count > 0 else { return 0 }
                return mutex.withLock {
                    libssh2_poll(baseAddress, UInt32(bp.count), 10)
                }
            }

            if pollRc < 0 {
                cleanupAll()
                break
            }

            var tasksToRemove = Set<OpaquePointer>()

            // 4. 处理轮询事件响应
            for (idx, task) in validTasks.enumerated() {
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

                if revents & LIBSSH2_POLLFD_CHANNEL_CLOSED != 0 {
                    tasksToRemove.insert(task.handle)
                    continue
                }

                let isTimeout = (pollRc == 0)

                let canRead = isTimeout || (revents & (LIBSSH2_POLLFD_POLLIN | LIBSSH2_POLLFD_POLLEXT)) != 0
                let canWrite = isTimeout || (revents & LIBSSH2_POLLFD_POLLOUT) != 0

                if !canRead && !canWrite && (revents & (LIBSSH2_POLLFD_POLLEXT | LIBSSH2_POLLFD_POLLERR | LIBSSH2_POLLFD_POLLHUP)) == 0 {
                    continue
                }

                var currentIncrement: Int64 = 0
                var hasReadError = false
                var hasWriteError = false
                var isEofReached = false

                // 读取 stdout
                if canRead {
                    let r = read(data: data, handle: task.handle, output: task.output, stream_id: 0)
                    if r < 0 {
                        if r != LIBSSH2_ERROR_EAGAIN {
                            hasReadError = true
                        }
                    } else if r == 0 {
                        let eofRc = mutex.withLock {
                            (_tasks[task.handle] != nil && !_tasks[task.handle]!.isCancelled) ? libssh2_channel_eof(task.handle) : 0
                        }
                        if eofRc != 0 {
                            isEofReached = true
                        }
                    } else {
                        currentIncrement += r
                    }
                }

                // 读取 stderr
                if canRead && !hasReadError && !isEofReached, let outerr = task.outerr {
                    let r = read(data: data, handle: task.handle, output: outerr, stream_id: 1)
                    if r < 0 {
                        if r != LIBSSH2_ERROR_EAGAIN {
                            hasReadError = true
                        }
                    } else if r > 0 {
                        currentIncrement += r
                        isEofReached = false
                    }
                }

                // 处理写入
                if canWrite && !hasReadError && !isEofReached {
                    let w = write(data: data, task: task)
                    if w < 0 {
                        if w != LIBSSH2_ERROR_EAGAIN {
                            hasWriteError = true
                        }
                    } else {
                        currentIncrement += w
                    }
                }

                // 进度与清理判断
                if currentIncrement > 0 {
                    let total = (progressTracker[task.handle] ?? 0) + currentIncrement
                    progressTracker[task.handle] = total
                    if task.onProgress?(total, task.totalSize) == false {
                        tasksToRemove.insert(task.handle)
                        continue
                    }
                }

                if hasReadError || hasWriteError || isEofReached || (revents & (LIBSSH2_POLLFD_POLLERR | LIBSSH2_POLLFD_POLLHUP | LIBSSH2_POLLFD_CHANNEL_CLOSED)) != 0 {
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
        mutex.withLock {
            if tasksToRemove.isEmpty {
                return
            }

            var removedTasks: [ChannelStream] = []
            for handle in tasksToRemove {
                if let task = _tasks.removeValue(forKey: handle) {
                    task.isCancelled = true
                    removedTasks.append(task)
                }
            }

            for t in removedTasks {
                t.output.close()
                t.outerr?.close()
                t.write?.close()
                t.continuation?.resume()
                t.continuation = nil
            }
        }
    }

    func read(data: Buffer<CChar>, handle: OpaquePointer, output: OutputStream, stream_id: Int32) -> Int64 {
        let n = mutex.withLock { () -> Int in
            guard let task = _tasks[handle], !task.isCancelled else { return -1 }
            return libssh2_channel_read_ex(handle, stream_id, data.buffer, data.count)
        }
        if n > 0 {
            output.write(data.buffer, maxLength: n)
            return n.int64
        } else if n == LIBSSH2_ERROR_EAGAIN {
            return 0
        } else {
            return -1
        }
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
