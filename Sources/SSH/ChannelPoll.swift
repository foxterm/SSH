// FoxTerm | ChannelPoll.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation
import Sync

/// 封装 SSH 通道读写任务，管理内部流状态及 I/O 缓冲
final class SSHChannelTask {
    let handle: OpaquePointer
    let output: OutputStream
    let outerr: OutputStream?
    let write: InputStream?

    let totalSize: Int64
    let onProgress: ((_ current: Int64, _ total: Int64) -> Bool)?

    let waitGroup: WaitGroup = .init()
    private(set) var isCancelled: Bool = false
    private let lock: Mutex = .init()
    private var continuation: CheckedContinuation<Void, Never>?

    private var writeBuffer = [UInt8]()
    private var writeOffset = 0

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
        lock.withLock { writeOffset < writeBuffer.count }
    }

    func appendPendingData(from pointer: UnsafeRawPointer, count: Int) {
        lock.withLock {
            if writeOffset > 0, writeOffset >= writeBuffer.count / 2 {
                writeBuffer.removeFirst(writeOffset)
                writeOffset = 0
            }
            let ptr = pointer.assumingMemoryBound(to: UInt8.self)
            writeBuffer.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
        }
    }

    func advanceWriteOffset(by count: Int) {
        lock.withLock {
            writeOffset += count
            if writeOffset >= writeBuffer.count {
                writeBuffer.removeAll(keepingCapacity: true)
                writeOffset = 0
            }
        }
    }

    func consumePendingWriteData(_ block: (UnsafeRawPointer, Int) -> Int) -> Int? {
        lock.withLock {
            guard writeOffset < writeBuffer.count else { return nil }
            return writeBuffer.withUnsafeBufferPointer { bp in
                guard let baseAddr = bp.baseAddress else { return nil }
                return block(baseAddr.advanced(by: writeOffset), writeBuffer.count - writeOffset)
            }
        }
    }

    func prepareStreams() {
        if output.streamStatus == .notOpen {
            output.open()
        }
        if outerr?.streamStatus == .notOpen {
            outerr?.open()
        }
        if write?.streamStatus == .notOpen {
            write?.open()
        }
    }

    func cancelAndComplete() {
        lock.withLock {
            guard !isCancelled else { return }
            isCancelled = true

            waitGroup.wait()
            output.close()
            outerr?.close()
            write?.close()

            continuation?.resume()
            continuation = nil
        }
    }
}

/// 高性能 SSH 通道多路复用轮询器
final class SSHChannelPoller {
    private let bufferSize: Int = 0x10000 // 64KB
    private let queue = DispatchQueue(label: "app.foxterm.ssh.poller", qos: .userInitiated)
    let mutex: Mutex = .init()

    private var _tasks: [OpaquePointer: SSHChannelTask] = [:]
    private var isLooping: Bool = false

    func register(
        handle: OpaquePointer, output: OutputStream, outerr: OutputStream?, write: InputStream?,
        totalSize: Int64 = 0, progress: ((_ current: Int64, _ total: Int64) -> Bool)? = nil
    ) async {
        await withCheckedContinuation { continuation in
            let task = SSHChannelTask(
                handle: handle, output: output, outerr: outerr, write: write,
                continuation: continuation, totalSize: totalSize, onProgress: progress
            )

            mutex.withLock {
                _tasks[handle] = task
                if !isLooping {
                    isLooping = true
                    queue.async { [weak self] in self?.runEventLoop() }
                }
            }
        }
    }

    func unregister(handle: OpaquePointer) {
        removeTasks([handle])
    }

    private func runEventLoop() {
        let dataBuffer = Buffer<CChar>(bufferSize)
        var progressTracker: [OpaquePointer: Int64] = [:]

        while true {
            let activeTasks = mutex.withLock {
                let tasks = _tasks.values.filter { !$0.isCancelled }
                if tasks.isEmpty {
                    isLooping = false
                }
                return tasks
            }
            guard !activeTasks.isEmpty else { break }

            var pollFds: [LIBSSH2_POLLFD] = activeTasks.map { task in
                task.prepareStreams()
                return buildPollDescriptor(for: task)
            }

            let pollRc = mutex.withLock { libssh2_poll(&pollFds, pollFds.count.uint32, 10) }

            if pollRc < 0 {
                cleanupAll()
                break
            }

            var tasksToEvict = Set<OpaquePointer>()

            for (idx, task) in activeTasks.enumerated() {
                task.waitGroup.add()
                defer { task.waitGroup.done() }

                let isAlive = mutex.withLock { _tasks[task.handle] != nil && !task.isCancelled }
                if !isAlive {
                    tasksToEvict.insert(task.handle)
                    continue
                }

                let increment = processTaskEvents(task: task, fd: pollFds[idx], buffer: dataBuffer, pollRc: pollRc)

                if increment < 0 {
                    tasksToEvict.insert(task.handle)
                } else if increment > 0 {
                    let newTotal = (progressTracker[task.handle] ?? 0) + increment
                    progressTracker[task.handle] = newTotal
                    if task.onProgress?(newTotal, task.totalSize) == false {
                        tasksToEvict.insert(task.handle)
                    }
                }
            }

            if !tasksToEvict.isEmpty {
                tasksToEvict.forEach { progressTracker.removeValue(forKey: $0) }
                removeTasks(Array(tasksToEvict))
            }
        }
    }

    private func processTaskEvents(task: SSHChannelTask, fd: LIBSSH2_POLLFD, buffer: Buffer<CChar>, pollRc: Int32) -> Int64 {
        let revents = fd.revents.int32
        let isClosed = (revents & LIBSSH2_POLLFD_CHANNEL_CLOSED) != 0
        let isTimeout = (pollRc == 0)
        let isError = (revents & (LIBSSH2_POLLFD_POLLERR | LIBSSH2_POLLFD_POLLHUP)) != 0

        let canRead = isTimeout || isClosed || (revents & (LIBSSH2_POLLFD_POLLIN | LIBSSH2_POLLFD_POLLEXT)) != 0
        let canWrite = !isClosed && (isTimeout || (revents & LIBSSH2_POLLFD_POLLOUT) != 0)

        var currentIncrement: Int64 = 0
        var eofStdout = false
        var eofStderr = (task.outerr == nil)
        var fatalError = isError

        if canRead && !fatalError {
            let r = performRead(task: task, output: task.output, streamId: 0, buffer: buffer)
            if r < 0 {
                fatalError = true
            } else if r == 0 {
                eofStdout = checkEOF(task)
            } else {
                currentIncrement += r
            }
        }

        if canRead && !fatalError && !eofStderr, let errStream = task.outerr {
            let r = performRead(task: task, output: errStream, streamId: 1, buffer: buffer)
            if r < 0 {
                fatalError = true
            } else if r == 0 {
                eofStderr = checkEOF(task)
            } else {
                currentIncrement += r
            }
        }

        if canWrite && !fatalError {
            let w = performWrite(task: task, buffer: buffer)
            if w < 0 {
                fatalError = true
            } else {
                currentIncrement += w
            }
        }

        let bothEof = eofStdout && eofStderr
        let needsEviction = fatalError || (isClosed && currentIncrement == 0) || bothEof

        return needsEviction ? -1 : currentIncrement
    }

    private func buildPollDescriptor(for task: SSHChannelTask) -> LIBSSH2_POLLFD {
        var pollFd = LIBSSH2_POLLFD()
        pollFd.type = LIBSSH2_POLLFD_CHANNEL.uint8
        pollFd.fd.channel = task.handle

        var events = LIBSSH2_POLLFD_POLLIN | LIBSSH2_POLLFD_POLLEXT
        if task.hasPendingWrite || (task.write?.hasBytesAvailable == true) {
            events |= LIBSSH2_POLLFD_POLLOUT
        }
        pollFd.events = events.uint
        pollFd.revents = 0
        return pollFd
    }

    private func performRead(task: SSHChannelTask, output: OutputStream, streamId: Int32, buffer: Buffer<CChar>) -> Int64 {
        let n = mutex.withLock {
            (!task.isCancelled && _tasks[task.handle] != nil)
                ? libssh2_channel_read_ex(task.handle, streamId, buffer.buffer, buffer.count) : -1
        }
        guard n > 0 else { return (n == LIBSSH2_ERROR_EAGAIN || n == 0) ? 0 : -1 }

        var totalWritten = 0
        while totalWritten < n {
            let w = output.write(buffer.buffer.advanced(by: totalWritten), maxLength: n - totalWritten)
            guard w > 0 else { return -1 }
            totalWritten += w
        }
        return n.int64
    }

    private func performWrite(task: SSHChannelTask, buffer: Buffer<CChar>) -> Int64 {
        if let rc = task.consumePendingWriteData({ ptr, count -> Int in
            mutex.withLock {
                if !task.isCancelled, _tasks[task.handle] != nil {
                    let charPtr = ptr.assumingMemoryBound(to: CChar.self)
                    return libssh2_channel_write_ex(task.handle, 0, charPtr, count)
                }
                return -1
            }
        }) {
            if rc > 0 {
                task.advanceWriteOffset(by: rc)
                return rc.int64
            }
            return rc == LIBSSH2_ERROR_EAGAIN ? 0 : -1
        }

        guard let input = task.write, input.hasBytesAvailable else { return 0 }

        let nread = input.read(buffer.buffer, maxLength: buffer.count)
        guard nread > 0 else { return nread < 0 ? -1 : 0 }

        let written = mutex.withLock {
            (!task.isCancelled && _tasks[task.handle] != nil)
                ? libssh2_channel_write_ex(task.handle, 0, buffer.buffer, nread) : -1
        }

        if written > 0 {
            if written < nread {
                task.appendPendingData(from: buffer.buffer.advanced(by: Int(written)), count: nread - Int(written))
            }
            return written.int64
        } else if written == LIBSSH2_ERROR_EAGAIN {
            task.appendPendingData(from: buffer.buffer, count: nread)
            return 0
        }

        return -1
    }

    private func checkEOF(_ task: SSHChannelTask) -> Bool {
        mutex.withLock {
            guard !task.isCancelled, _tasks[task.handle] != nil else { return false }
            return libssh2_channel_eof(task.handle) != 0
        }
    }

    private func removeTasks(_ handles: [OpaquePointer]) {
        guard !handles.isEmpty else { return }

        let removedTasks = mutex.withLock {
            handles.compactMap { _tasks.removeValue(forKey: $0) }
        }
        removedTasks.forEach { $0.cancelAndComplete() }
    }

    private func cleanupAll() {
        let allHandles = mutex.withLock { Array(_tasks.keys) }
        removeTasks(allHandles)
    }
}
