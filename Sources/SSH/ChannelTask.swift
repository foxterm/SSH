// FoxTerm | ChannelTask.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Darwin
import Extension
import Foundation
import Sync

/// 封装 SSH 通道读写任务，管理内部流状态及 I/O 缓冲
final class ChannelTask {
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
