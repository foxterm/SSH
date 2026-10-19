// FoxTerm | SCP.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

public extension SSH {
    // MARK: - SCP 上传

    /// 上传文件或目录至远程
    /// - Parameters:
    ///   - localURL: 本地文件/目录路径
    ///   - remotePath: 远程目标路径
    ///   - recursive: 是否递归上传目录
    ///   - progress: 进度回调 (全局已传输字节数, 全局总字节数) -> 是否继续
    /// - Returns: 是否成功
    @discardableResult
    func scpUpload(
        localURL: URL,
        remotePath: String,
        recursive: Bool = true,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        if filterFiles.contains(localURL.lastPathComponent) {
            return true
        }

        return mutex.withLock {
            guard let session = rawSession else { return false }

            let fileManager = FileManager.default
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: localURL.path, isDirectory: &isDir) else { return false }

            var mode = SSH_SCP_WRITE
            if recursive {
                mode |= SSH_SCP_RECURSIVE
            }

            guard let scp = ssh_scp_new(session, mode.int32, remotePath.bytesArray) else { return false }
            rawSCP = scp

            guard ssh_scp_init(scp) == SSH_OK else {
                _closeSCP()
                return false
            }

            // 1. 精确计算本地传输总字节数(排除软链接与过滤文件，确保与实际上传字节数绝对一致)
            let totalSize: Int64
            if isDir.boolValue {
                totalSize = calculateLocalDirectorySize(url: localURL)
            } else {
                let attr = try? fileManager.attributesOfItem(atPath: localURL.path)
                totalSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0
            }

            let safeTotalSize = max(totalSize, 1)
            var accumulatedTransferred: Int64 = 0

            // 初始 0 进度更新
            _ = progress?(0, safeTotalSize)

            // 2. 执行上传
            let success: Bool = if isDir.boolValue {
                recursive ? uploadDirectory(
                    localURL: localURL,
                    scp: scp,
                    totalSize: safeTotalSize,
                    accumulatedTransferred: &accumulatedTransferred,
                    progress: progress
                ) : false
            } else {
                uploadSingleFile(
                    localURL: localURL,
                    scp: scp,
                    totalSize: safeTotalSize,
                    accumulatedTransferred: &accumulatedTransferred,
                    progress: progress
                )
            }

            _closeSCP()
            return success
        }
    }

    // MARK: - SCP 下载

    /// 从远程下载文件或目录
    /// - Parameters:
    ///   - remotePath: 远程路径
    ///   - localDirectoryURL: 本地保存的目标父目录
    ///   - recursive: 是否递归下载
    ///   - progress: 进度回调 (全局已传输字节数, 全局总字节数) -> 是否继续
    /// - Returns: 是否成功
    @discardableResult
    func scpDownload(
        remotePath: String,
        localDirectoryURL: URL,
        recursive: Bool = true,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        let remoteFileName = (remotePath as NSString).lastPathComponent
        if filterFiles.contains(remoteFileName) {
            return true
        }

        return mutex.withLock {
            guard let session = rawSession else { return false }

            var mode = SSH_SCP_READ
            if recursive {
                mode |= SSH_SCP_RECURSIVE
            }

            guard let scp = ssh_scp_new(session, mode.int32, remotePath.bytesArray) else { return false }
            rawSCP = scp

            guard ssh_scp_init(scp) == SSH_OK else {
                _closeSCP()
                return false
            }

            // 纯 SCP 下通过 Pull 流式解析动态更新总大小与已传输进度
            let success = processPullLoop(
                targetDir: localDirectoryURL,
                scp: scp,
                progress: progress
            )
            _closeSCP()
            return success
        }
    }

    // MARK: - SCP 内存数据传输

    /// 通过 SCP 协议下载远程文件并返回内存数据
    /// - Parameters:
    ///   - remotePath: 远程文件路径
    ///   - progress: 进度回调 `(已传输字节数, 总字节数) -> 是否继续`，返回 `false` 中止传输
    /// - Returns: 文件二进制数据 `Data`，失败或被过滤返回 `nil`
    func scpDownloadData(
        remotePath: String,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Data? {
        wait.add()
        defer {
            wait.done()
        }
        let remoteFileName = (remotePath as NSString).lastPathComponent
        if filterFiles.contains(remoteFileName) {
            return nil
        }

        return mutex.withLock {
            guard let session = rawSession else { return nil }
            guard let scp = ssh_scp_new(session, SSH_SCP_READ.int32, remotePath.bytesArray) else { return nil }
            rawSCP = scp

            guard ssh_scp_init(scp) == SSH_OK else {
                _closeSCP()
                return nil
            }
            defer { _closeSCP() }

            let output = OutputStream.toMemory()
            output.open()
            defer { output.close() }

            let buffer = Buffer<UInt8>(bufferSize)

            while true {
                let req = ssh_scp_pull_request(scp)
                let requestType = ssh_scp_request_types(req.uint32)

                switch requestType {
                case SSH_SCP_REQUEST_NEWFILE:
                    let size = ssh_scp_request_get_size64(scp)
                    let safeSize = max(Int64(size), 1)
                    if ssh_scp_accept_request(scp) != SSH_OK {
                        return nil
                    }

                    var bytesRead: UInt64 = 0
                    var shouldCancel = false

                    while bytesRead < size {
                        autoreleasepool {
                            let bytesToRead = min(UInt64(bufferSize), size - bytesRead)
                            let readResult = ssh_scp_read(scp, buffer.buffer, bytesToRead.int)

                            if readResult <= 0 {
                                shouldCancel = true
                                return
                            }

                            if !writeAllToStream(output, buffer: buffer, length: readResult.int) {
                                shouldCancel = true
                                return
                            }

                            bytesRead += UInt64(readResult)

                            if let progress, !progress(bytesRead.int64, safeSize) {
                                shouldCancel = true
                            }
                        }
                        if shouldCancel {
                            return nil
                        }
                    }

                    if let data = output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data {
                        return data
                    }
                    return Data()

                case SSH_SCP_REQUEST_EOF:
                    if let data = output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data {
                        return data
                    }
                    return Data()

                case SSH_SCP_REQUEST_WARNING:
                    break

                default:
                    return nil
                }
            }
        }
    }

    /// 通过 SCP 协议将内存数据上传写入到远程文件
    /// - Parameters:
    ///   - data: 待上传的二进制数据
    ///   - remotePath: 远程目标文件路径
    ///   - mode: 创建文件时的默认权限（默认 `0o644`）
    ///   - progress: 进度回调 `(已传输字节数, 总字节数) -> 是否继续`，返回 `false` 中止传输
    /// - Returns: 是否上传成功
    @discardableResult
    func scpUploadData(
        data: Data,
        remotePath: String,
        mode: mode_t = 0o644,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        let fileName = (remotePath as NSString).lastPathComponent
        if filterFiles.contains(fileName) {
            return true
        }

        return mutex.withLock {
            guard let session = rawSession else { return false }
            guard let scp = ssh_scp_new(session, SSH_SCP_WRITE.int32, remotePath.bytesArray) else { return false }
            rawSCP = scp

            guard ssh_scp_init(scp) == SSH_OK else {
                _closeSCP()
                return false
            }
            defer { _closeSCP() }

            let fileSize = data.count.uint64
            let safeTotalSize = max(Int64(fileSize), 1)

            let pushResult = ssh_scp_push_file64(scp, fileName.bytesArray, fileSize, mode.int32)
            guard pushResult == SSH_OK else {
                return false
            }

            if fileSize == 0 {
                _ = progress?(0, safeTotalSize)
                return true
            }

            let input = InputStream(data: data)
            input.open()
            defer { input.close() }

            let buffer = Buffer<UInt8>(bufferSize)
            var bytesSent: Int64 = 0

            while input.hasBytesAvailable {
                var shouldCancel = false
                autoreleasepool {
                    let bytesRead = input.read(buffer.buffer, maxLength: buffer.count)
                    if bytesRead < 0 {
                        shouldCancel = true
                        return
                    }
                    if bytesRead == 0 {
                        return
                    }

                    let res = ssh_scp_write(scp, buffer.buffer, bytesRead)
                    if res != SSH_OK {
                        shouldCancel = true
                        return
                    }

                    bytesSent += bytesRead.int64
                    if let progress, !progress(bytesSent, safeTotalSize) {
                        shouldCancel = true
                    }
                }
                if shouldCancel {
                    return false
                }
            }

            return true
        }
    }

    /// 关闭并释放当前 SCP 会话（公开安全接口，带锁）
    func closeSCP() {
        mutex.withVoid {
            _closeSCP()
        }
    }

    /// 内部无锁关闭清理方法（专供已在 mutex 保护内的函数调用，避免死锁）
    private func _closeSCP() {
        if let scp = rawSCP {
            ssh_scp_close(scp)
            ssh_scp_free(scp)
            rawSCP = nil
        }
    }

    // MARK: - 内部辅助方法

    /// 上传单个本地文件到远程 SCP 通道
    private func uploadSingleFile(
        localURL: URL,
        scp: ssh_scp,
        totalSize: Int64,
        accumulatedTransferred: inout Int64,
        progress: ((Int64, Int64) -> Bool)?
    ) -> Bool {
        if filterFiles.contains(localURL.lastPathComponent) {
            return true
        }

        // 排除软链接文件，避免大小预估与实际写入矛盾
        if let resourceValues = try? localURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
           resourceValues.isSymbolicLink == true
        {
            return true
        }

        guard let attr = try? FileManager.default.attributesOfItem(atPath: localURL.path),
              let fileHandle = try? FileHandle(forReadingFrom: localURL)
        else {
            return false
        }
        defer { try? fileHandle.close() }

        let fileSize = (attr[.size] as? NSNumber)?.uint64Value ?? 0
        let permissions = (attr[.posixPermissions] as? NSNumber)?.int32Value ?? 0o644

        let pushResult = ssh_scp_push_file64(scp, localURL.lastPathComponent.bytesArray, fileSize, permissions)
        guard pushResult == SSH_OK else {
            return false
        }

        if fileSize == 0 {
            return true
        }

        let startOffset = accumulatedTransferred
        var currentFileSent: Int64 = 0

        while currentFileSent < fileSize.int64 {
            var shouldCancel = false
            var isError = false

            autoreleasepool {
                guard let chunk = try? fileHandle.read(upToCount: bufferSize) else {
                    isError = true
                    return
                }

                if chunk.isEmpty {
                    return
                }

                let res = chunk.withUnsafeBytes { ptr in
                    ssh_scp_write(scp, ptr.baseAddress, ptr.count)
                }
                if res != SSH_OK {
                    isError = true
                    return
                }

                currentFileSent += chunk.count.int64
                let globalTransferred = startOffset + currentFileSent
                if let progress, !progress(globalTransferred, totalSize) {
                    shouldCancel = true
                }
            }

            if isError || shouldCancel {
                return false
            }
        }

        accumulatedTransferred += Int64(fileSize)
        return true
    }

    /// 递归上传本地目录到远程 SCP 通道
    private func uploadDirectory(
        localURL: URL,
        scp: ssh_scp,
        totalSize: Int64,
        accumulatedTransferred: inout Int64,
        progress: ((Int64, Int64) -> Bool)?
    ) -> Bool {
        if filterFiles.contains(localURL.lastPathComponent) {
            return true
        }

        let fileManager = FileManager.default
        guard let attr = try? fileManager.attributesOfItem(atPath: localURL.path),
              let contents = try? fileManager.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        else {
            return false
        }

        let permissions = (attr[.posixPermissions] as? NSNumber)?.int32Value ?? 0o644
        let pushResult = ssh_scp_push_directory(scp, localURL.lastPathComponent.bytesArray, permissions)
        guard pushResult == SSH_OK else {
            return false
        }

        for item in contents {
            if filterFiles.contains(item.lastPathComponent) {
                continue
            }

            // 忽略软链接目录/文件，防止循环递归及实际字节溢出
            if let resourceValues = try? item.resourceValues(forKeys: [.isSymbolicLinkKey]),
               resourceValues.isSymbolicLink == true
            {
                continue
            }

            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir) {
                let ok = isDir.boolValue
                    ? uploadDirectory(
                        localURL: item,
                        scp: scp,
                        totalSize: totalSize,
                        accumulatedTransferred: &accumulatedTransferred,
                        progress: progress
                    )
                    : uploadSingleFile(
                        localURL: item,
                        scp: scp,
                        totalSize: totalSize,
                        accumulatedTransferred: &accumulatedTransferred,
                        progress: progress
                    )
                if !ok {
                    return false
                }
            }
        }

        return ssh_scp_leave_directory(scp) == SSH_OK
    }

    /// SCP 拉取模式下载循环：解析远程文件/目录流并写入本地
    private func processPullLoop(
        targetDir: URL,
        scp: ssh_scp,
        progress: ((Int64, Int64) -> Bool)?
    ) -> Bool {
        let fileManager = FileManager.default
        var currentLocalDir = targetDir
        var dirStack: [URL] = []
        var accumulatedTransferred: Int64 = 0
        var totalDiscoveredSize: Int64 = 0
        var skipDepth = 0

        let buffer = Buffer<UInt8>(bufferSize)

        while true {
            let req = ssh_scp_pull_request(scp)
            let requestType = ssh_scp_request_types(req.uint32)

            switch requestType {
            case SSH_SCP_REQUEST_NEWFILE:
                guard let rawName = ssh_scp_request_get_filename(scp) else { return false }
                let filename = String(cString: rawName)
                let size = ssh_scp_request_get_size64(scp)
                let mode = ssh_scp_request_get_permissions(scp)

                if skipDepth > 0 || filterFiles.contains(filename) {
                    if ssh_scp_deny_request(scp, "Filtered file") != SSH_OK {
                        return false
                    }
                    continue
                }

                // 重点：每次收到新文件时，动态累加已知的总大小
                totalDiscoveredSize += Int64(size)
                let currentTotal = max(totalDiscoveredSize, 1)

                let destURL = currentLocalDir.appendingPathComponent(filename)
                guard ssh_scp_accept_request(scp) == SSH_OK else { return false }

                fileManager.createFile(atPath: destURL.path, contents: nil, attributes: [.posixPermissions: mode])
                guard let fileHandle = try? FileHandle(forWritingTo: destURL) else { return false }

                var currentFileRead: UInt64 = 0
                let startOffset = accumulatedTransferred
                var isFailedOrCancelled = false

                if size > 0 {
                    while currentFileRead < size {
                        autoreleasepool {
                            let bytesToRead = min(UInt64(bufferSize), size - currentFileRead)
                            let readResult = ssh_scp_read(scp, buffer.buffer, bytesToRead.int)

                            if readResult <= 0 {
                                isFailedOrCancelled = true
                                return
                            }

                            let chunkData = Data(bytes: buffer.buffer, count: readResult.int)
                            fileHandle.write(chunkData)
                            currentFileRead += UInt64(readResult)

                            let globalTransferred = startOffset + Int64(currentFileRead)
                            if let progress, !progress(globalTransferred, currentTotal) {
                                isFailedOrCancelled = true
                            }
                        }

                        if isFailedOrCancelled {
                            try? fileHandle.close()
                            return false
                        }
                    }
                } else {
                    _ = progress?(accumulatedTransferred, currentTotal)
                }

                try? fileHandle.close()
                accumulatedTransferred += Int64(size)

            case SSH_SCP_REQUEST_NEWDIR:
                guard let rawName = ssh_scp_request_get_filename(scp) else { return false }
                let dirName = String(cString: rawName)
                let mode = ssh_scp_request_get_permissions(scp)

                if skipDepth > 0 || filterFiles.contains(dirName) {
                    skipDepth += 1
                    if ssh_scp_deny_request(scp, "Filtered directory") != SSH_OK {
                        return false
                    }
                    continue
                }

                let newDirURL = currentLocalDir.appendingPathComponent(dirName)
                guard (try? fileManager.createDirectory(at: newDirURL, withIntermediateDirectories: true, attributes: [.posixPermissions: mode])) != nil else {
                    return false
                }

                guard ssh_scp_accept_request(scp) == SSH_OK else { return false }
                dirStack.append(currentLocalDir)
                currentLocalDir = newDirURL

            case SSH_SCP_REQUEST_ENDDIR:
                if skipDepth > 0 {
                    skipDepth -= 1
                } else if let parentDir = dirStack.popLast() {
                    currentLocalDir = parentDir
                }

            case SSH_SCP_REQUEST_EOF:
                return true

            case SSH_SCP_REQUEST_WARNING:
                break

            default:
                return false
            }
        }
    }

    /// 向输出流完整写入指定字节数的缓冲区数据
    private func writeAllToStream(_ stream: OutputStream, buffer: Buffer<UInt8>, length: Int) -> Bool {
        var offset = 0
        while offset < length {
            let written = stream.write(buffer.buffer.advanced(by: offset), maxLength: length - offset)
            if written < 0 {
                return false
            }
            offset += written
        }
        return true
    }

    /// 准确计算本地目录字节数(跳过软链接和过滤文件)
    private func calculateLocalDirectorySize(url: URL) -> Int64 {
        if filterFiles.contains(url.lastPathComponent) {
            return 0
        }

        let fileManager = FileManager.default
        // 关键：不能跟随软链接 (Symbolic Link) 避免大小统计偏小而实际文件很大的巨大误差
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            if filterFiles.contains(fileName) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]) {
                // 不计算软链接文件/目录的大小
                if resourceValues.isSymbolicLink == true {
                    continue
                }
                if let isDir = resourceValues.isDirectory, !isDir, let size = resourceValues.fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }
}
