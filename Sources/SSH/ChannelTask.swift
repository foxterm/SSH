// FoxTerm | ChannelTask.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

struct SSHChannelTask {
    let handle: OpaquePointer
    let output: OutputStream
    let outerr: OutputStream?
    let write: InputStream?
    var continuation: CheckedContinuation<Void, Never>? = nil
}

class ChannelTask {
    let bufferSize = 0x10000 // 64K
    let queue = DispatchQueue(label: "app.foxterm.channeltask.queue")
    var _isLooping: Bool = false
    let mutex: Mutex = .init()
    private var _tasks: [SSHChannelTask] = []
}

extension ChannelTask {
    func register(handle: OpaquePointer, output: OutputStream, outerr: OutputStream?, write: InputStream?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var task = SSHChannelTask(
                handle: handle,
                output: output,
                outerr: outerr,
                write: write,
                continuation: continuation
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

    func runMasterLoop() {
        let data: Buffer<CChar> = .init(bufferSize)
        while true {
            let tasks = mutex.with {
                _tasks
            }
            var poolls: [LIBSSH2_POLLFD] = []

            for t in tasks {
                var poll = LIBSSH2_POLLFD()
                poll.type = LIBSSH2_POLLFD_CHANNEL.uint8
                poll.fd.channel = t.handle
                var events = LIBSSH2_POLLFD_POLLIN
                poll.revents = 0
                if t.outerr != nil {
                    events |= LIBSSH2_POLLFD_POLLEXT
                }
                if let writeStream = t.write, writeStream.hasBytesAvailable {
                    events |= LIBSSH2_POLLFD_POLLOUT
                }
                poll.events = events.uint
                poolls.append(poll)
            }
            if poolls.isEmpty {
                break
            }

            let pollRc = libssh2_poll(&poolls, poolls.count.uint32, 10)

            if pollRc < 0 {
                break
            }
            var n = 0
            var tasksToRemove: [OpaquePointer] = []
            if pollRc > 0 {
                for (index, poll) in poolls.enumerated() {
                    let task = tasks[index]
                    let revents = poll.revents.int32
                    if (revents & LIBSSH2_POLLFD_POLLIN) != 0 {
                        n = libssh2_channel_read_ex(task.handle, 0, data.buffer, data.count)
                        if n > 0 {
                            task.output.write(data.buffer, maxLength: n)
                        } else if n < 0, n != LIBSSH2_ERROR_EAGAIN {
                            tasksToRemove.append(task.handle)
                            continue
                        }
                    }
                    if (revents & LIBSSH2_POLLFD_POLLEXT) != 0 {
                        if let outerrStream = task.outerr {
                            n = libssh2_channel_read_ex(task.handle, 1, data.buffer, data.count)
                            if n > 0 {
                                outerrStream.write(data.buffer, maxLength: n)
                            } else if n < 0, n != LIBSSH2_ERROR_EAGAIN {
                                tasksToRemove.append(task.handle)
                                continue
                            }
                        }
                    }
                    if (revents & LIBSSH2_POLLFD_POLLOUT) != 0 {
                        if let writeStream = task.write {
                            let nread = writeStream.read(data.buffer, maxLength: data.count)
                            if nread > 0 {
                                var offset = 0
                                while offset < nread {
                                    let written = libssh2_channel_write_ex(task.handle, 0, data.buffer + offset, nread - offset)
                                    if written < 0 {
                                        if written != LIBSSH2_ERROR_EAGAIN {
                                            tasksToRemove.append(task.handle)
                                        }
                                        break
                                    }
                                    offset += Int(written)
                                }
                            }
                        }
                    }
                    if (revents & (Int32(LIBSSH2_POLLFD_CHANNEL_CLOSED) | Int32(LIBSSH2_POLLFD_SESSION_CLOSED))) != 0 {
                        tasksToRemove.append(task.handle)
                        continue
                    }
                    if libssh2_channel_eof(task.handle) != 0 {
                        tasksToRemove.append(task.handle)
                        continue
                    }
                }
                if !tasksToRemove.isEmpty {
                    var removedTasks: [SSHChannelTask] = []
                    mutex.with {
                        removedTasks = _tasks.filter { tasksToRemove.contains($0.handle) }
                        _tasks.removeAll { task in
                            tasksToRemove.contains(task.handle)
                        }
                    }
                    for task in removedTasks {
                        task.continuation?.resume()
                    }
                }
            }
        }
        mutex.with { _isLooping = false }
    }
}
