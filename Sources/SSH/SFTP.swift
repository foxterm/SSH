// FoxTerm | SFTP.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import Extension
import Foundation
import libssh

public extension SSH {
    // MARK: - 会话初始化与释放

    /// 初始化 SFTP 子系统会话
    /// - Returns: 初始化成功返回 `true`，失败或已开启返回 `false` / `true`
    func sftpInit() -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard rawSFTP == nil else {
                return true
            }
            guard let rawSession else {
                return false
            }
            guard let rawSFTP = sftp_new(rawSession) else {
                return false
            }
            guard sftp_init(rawSFTP) == SSH_FX_OK else {
                sftp_free(rawSFTP)
                return false
            }
            self.rawSFTP = rawSFTP
            return true
        }
    }

    /// 获取当前 SFTP 会话的版本号
    /// - Returns: SFTP 服务器版本号，失败返回 0
    func sftpVersion() -> Int {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else {
                return 0
            }
            return sftp_server_version(rawSFTP).int
        }
    }

    /// 关闭并释放当前 SFTP 会话(公开安全接口，带锁)
    func closeSFTP() {
        mutex.withVoid {
            _closeSFTP()
        }
    }

    /// 内部无锁关闭清理方法(专供已在 mutex 保护内的函数调用，避免死锁)
    private func _closeSFTP() {
        guard let rawSFTP else {
            return
        }
        sftp_free(rawSFTP)
        self.rawSFTP = nil
    }

    /// 获取上一次 SFTP 操作的底层错误码
    /// - Returns: SFTP 错误码(例如 SSH_FX_NO_SUCH_FILE 等)
    func sftpGetError() -> Int {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else {
                return 0
            }
            return sftp_get_error(rawSFTP).int
        }
    }

    // MARK: - 扩展协议查询

    /// 获取服务端支持的 SFTP 扩展数量
    func sftpExtensionsGetCount() -> Int {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else {
                return 0
            }
            return sftp_extensions_get_count(rawSFTP).int
        }
    }

    /// 根据索引获取 SFTP 扩展名称
    func sftpExtensionsGetName(index: Int) -> String? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else {
                return nil
            }
            guard let namePtr = sftp_extensions_get_name(rawSFTP, index.uint32) else {
                return nil
            }
            return namePtr.string
        }
    }

    /// 根据索引获取 SFTP 扩展数据(版本信息)
    func sftpExtensionsGetData(index: Int) -> String? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else {
                return nil
            }
            guard let dataPtr = sftp_extensions_get_data(rawSFTP, index.uint32) else {
                return nil
            }
            return dataPtr.string
        }
    }

    /// 检查指定的 SFTP 扩展功能是否受服务端支持
    func sftpExtensionSupported(name: String, version: String) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else {
                return false
            }
            return sftp_extension_supported(rawSFTP, name.bytesArray, version.bytesArray) == 1
        }
    }

    // MARK: - 目录操作

    /// 读取指定目录下的所有文件列表
    /// - Parameter path: 远程目录路径
    /// - Returns: 文件模型数组 `[SFTPFile]`
    func sftpOpendir(path: String) -> [SFTPFile] {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else {
                return []
            }

            guard let sftp_dir = sftp_opendir(rawSFTP, path.bytesArray) else {
                return []
            }

            defer {
                sftp_closedir(sftp_dir)
            }

            var files: [SFTPFile] = []

            while let attr = sftp_readdir(rawSFTP, sftp_dir) {
                defer {
                    sftp_attributes_free(attr)
                }
                let fileName = attr.pointee.name.string

                // 跳过配置的忽略文件以及 filterFiles 列表中的文件
                guard !ignoredFiles.contains(fileName) else {
                    continue
                }
                files.append(SFTPFile(attr: attr.pointee))
            }

            #if DEBUG
                if sftp_dir_eof(sftp_dir) == 0 {
                    let errorCode = sftp_get_error(rawSFTP)
                    print("SFTP readdir 异常中断，错误代码: \(errorCode)")
                } else {
                    print("成功读取完毕，共 \(files.count) 个文件")
                }
            #endif

            return files
        }
    }

    /// 创建远程空文件
    /// - Parameters:
    ///   - path: 文件完整路径
    ///   - mode: 创建文件时的默认权限(默认 `0o644`)
    ///   - overwrite: 是否覆盖已存在的文件(默认 `false`；如果为 `false` 且文件已存在则创建失败)
    /// - Returns: 是否创建成功
    func sftpCreateEmptyFile(path: String, mode: Int = 0o644, overwrite: Bool = false) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }

            let accessType = O_WRONLY | O_CREAT | (overwrite ? O_TRUNC : O_EXCL)

            guard let file = sftp_open(rawSFTP, path.bytesArray, accessType.int32, mode_t(mode)) else {
                return false
            }

            sftp_close(file)
            return true
        }
    }

    /// 创建远程目录
    /// - Parameters:
    ///   - directory: 目录路径
    ///   - mode: 权限位(默认 `0o755`)
    /// - Returns: 是否创建成功
    func sftpMkdir(directory: String, mode: Int = 0o755) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_mkdir(rawSFTP, directory.bytesArray, mode_t(mode)) == SSH_FX_OK
        }
    }

    /// 递归创建远程多级目录(类似 `mkdir -p`)
    /// - Parameters:
    ///   - directory: 目标完整路径(例如 `"/var/www/foxterm/uploads"`)
    ///   - mode: 创建新目录时的默认权限位(默认 `0o755`)
    /// - Returns: 是否创建/已存在成功
    func sftpMkdirAll(directory: String, mode: Int = 0o755) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }

            let cleanPath = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanPath.isEmpty else { return false }

            if let attr = sftp_stat(rawSFTP, cleanPath.bytesArray) {
                let isDir = (attr.pointee.permissions.uint16 & S_IFMT) == S_IFDIR
                sftp_attributes_free(attr)
                if isDir {
                    return true
                }
            }

            let isAbsolute = cleanPath.hasPrefix("/")
            let components = cleanPath.split(separator: "/").map(String.init)

            var currentPath = isAbsolute ? "" : "."

            for component in components {
                currentPath += "/" + component

                if let attr = sftp_stat(rawSFTP, currentPath.bytesArray) {
                    let isDir = (attr.pointee.permissions.uint16 & S_IFMT) == S_IFDIR
                    sftp_attributes_free(attr)
                    if !isDir {
                        return false
                    }
                    continue
                }

                if sftp_mkdir(rawSFTP, currentPath.bytesArray, mode_t(mode)) != SSH_FX_OK {
                    if let attr = sftp_stat(rawSFTP, currentPath.bytesArray) {
                        let isDir = (attr.pointee.permissions.uint16 & S_IFMT) == S_IFDIR
                        sftp_attributes_free(attr)
                        if !isDir {
                            return false
                        }
                    } else {
                        return false
                    }
                }
            }

            return true
        }
    }

    /// 删除远程空目录
    /// - Parameter directory: 目录路径
    /// - Returns: 是否删除成功
    func sftpRmdir(directory: String) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_rmdir(rawSFTP, directory.bytesArray) == SSH_FX_OK
        }
    }

    // MARK: - 文件与路径管理

    /// 获取远程路径的文件属性(跟随符号链接)
    /// - Parameter path: 文件路径
    /// - Returns: `SFTPFile` 模型(失败返回 nil)
    func sftpStat(path: String) -> SFTPFile? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return nil }
            guard let attr = sftp_stat(rawSFTP, path.bytesArray) else {
                return nil
            }
            defer { sftp_attributes_free(attr) }
            return SFTPFile(attr: attr.pointee)
        }
    }

    /// 获取远程路径的文件属性(不跟随符号链接，获取软链接本身属性)
    /// - Parameter path: 文件路径
    /// - Returns: `SFTPFile` 模型(失败返回 nil)
    func sftpLstat(path: String) -> SFTPFile? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return nil }
            guard let attr = sftp_lstat(rawSFTP, path.bytesArray) else {
                return nil
            }
            defer { sftp_attributes_free(attr) }
            return SFTPFile(attr: attr.pointee)
        }
    }

    /// 删除远程文件
    /// - Parameter file: 文件路径
    /// - Returns: 是否删除成功
    func sftpUnlink(file: String) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_unlink(rawSFTP, file.bytesArray) == SSH_FX_OK
        }
    }

    /// 重命名或移动远程文件/目录
    /// - Parameters:
    ///   - originalPath: 原路径
    ///   - newPath: 新路径
    /// - Returns: 是否重命名成功
    func sftpRename(originalPath: String, newPath: String) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_rename(rawSFTP, originalPath.bytesArray, newPath.bytesArray) == SSH_FX_OK
        }
    }

    /// 规范化远程路径(解析 `.`、`..` 和相对路径为绝对路径)
    /// - Parameter path: 待规范化的路径
    /// - Returns: 规范化后的绝对路径字符串
    func sftpCanonicalizePath(_ path: String) -> String? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return nil }
            guard let cStringPtr = sftp_canonicalize_path(rawSFTP, path.bytesArray) else {
                return nil
            }
            defer {
                ssh_string_free_char(cStringPtr)
            }
            return cStringPtr.string
        }
    }

    /// 展开波浪号等路径(利用 OpenSSH `expand-path@openssh.com` 扩展)
    /// - Parameter path: 原始路径(例如 `"~/documents"`)
    /// - Returns: 展开后的完整路径
    func sftpExpandPath(_ path: String) -> String? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return nil }
            guard let cStringPtr = sftp_expand_path(rawSFTP, path.bytesArray) else {
                return nil
            }
            defer { ssh_string_free_char(cStringPtr) }
            return cStringPtr.string
        }
    }

    /// 获取指定用户的家目录(需服务端支持 `home-directory` 扩展)
    /// - Parameter username: 用户名
    /// - Returns: 家目录路径
    func sftpHomeDirectory(username: String) -> String? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return nil }
            guard let cStringPtr = sftp_home_directory(rawSFTP, username.bytesArray) else {
                return nil
            }
            defer { ssh_string_free_char(cStringPtr) }
            return cStringPtr.string
        }
    }

    /// 修改远程文件或目录的权限位(chmod)
    /// - Parameters:
    ///   - path: 远程文件或目录路径
    ///   - mode: POSIX 权限模式(如 `0o644`、`0o755`)
    ///   - recursive: 是否递归应用到子目录和文件(默认 `false`)
    /// - Returns: 是否完全修改成功
    @discardableResult
    func sftpChmod(path: String, mode: Int, recursive: Bool = false) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        // 过滤文件直接略过
        let fileName = path.lastPathComponent
        if filterFiles.contains(fileName) {
            return true
        }

        // 1. 修改当前目标自身的权限
        let currentSuccess: Bool = mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_chmod(rawSFTP, path.bytesArray, mode_t(mode)) == SSH_FX_OK
        }

        guard currentSuccess else { return false }

        // 2. 如果不需要递归，直接返回成功
        guard recursive else { return true }

        // 3. 检查是否为目录，若为目录则递归遍历子项
        guard let remoteStat = sftpLstat(path: path), remoteStat.isDirectory else {
            return true
        }

        let items = sftpOpendir(path: path)
        for item in items {
            guard !filterFiles.contains(item.name) else {
                continue
            }

            let subPath = path.appendingPathComponent(item.name)
            if !sftpChmod(path: subPath, mode: mode, recursive: true) {
                return false
            }
        }

        return true
    }

    /// 修改远程文件所有者及属组(chown)
    /// - Parameters:
    ///   - path: 文件路径
    ///   - owner: 目标 UID
    ///   - group: 目标 GID
    /// - Returns: 是否修改成功
    func sftpChown(path: String, owner: uid_t, group: gid_t) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_chown(rawSFTP, path.bytesArray, owner, group) == SSH_FX_OK
        }
    }

    // MARK: - 链接操作

    /// 创建软链接(符号链接)
    /// - Parameters:
    ///   - target: 链接指向的目标路径
    ///   - dest: 软链接文件自身的路径
    /// - Returns: 是否创建成功
    func sftpSymlink(target: String, dest: String) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_symlink(rawSFTP, target.bytesArray, dest.bytesArray) == SSH_FX_OK
        }
    }

    /// 创建硬链接
    /// - Parameters:
    ///   - oldPath: 原文件路径
    ///   - newPath: 硬链接文件路径
    /// - Returns: 是否创建成功
    func sftpHardlink(oldPath: String, newPath: String) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return false }
            return sftp_hardlink(rawSFTP, oldPath.bytesArray, newPath.bytesArray) == SSH_FX_OK
        }
    }

    /// 读取软链接文件指向的真实路径
    /// - Parameter path: 软链接文件路径
    /// - Returns: 指向的目标路径
    func sftpReadlink(path: String) -> String? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return nil }
            guard let cStringPtr = sftp_readlink(rawSFTP, path.bytesArray) else {
                return nil
            }
            defer { ssh_string_free_char(cStringPtr) }
            return cStringPtr.string
        }
    }

    // MARK: - Data 内存传输扩展

    /// 从远程服务器读取文件内容并直接返回 `Data`
    /// - Parameters:
    ///   - path: 远程文件路径
    ///   - progress: 传输进度回调 `(已传输字节数, 总字节数) -> 是否继续`，返回 `false` 中止传输
    /// - Returns: 文件二进制数据 `Data`，失败则返回 `nil`
    func sftpReadFileData(
        path: String,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Data? {
        wait.add()
        defer {
            wait.done()
        }
        guard let remoteStat = sftpStat(path: path), !remoteStat.isDirectory else {
            return nil
        }

        let output = OutputStream.toMemory()
        guard sftpReadFile(path: path, output: output, totalSize: remoteStat.size.int64, progress: progress) else {
            return nil
        }

        return output.data
    }

    /// 将内存中的 `Data` 直接上传写入到远程服务器文件
    /// - Parameters:
    ///   - data: 待上传的二进制数据
    ///   - path: 远程写入目标路径
    ///   - mode: 创建文件时的默认权限(默认 `0o644`)
    ///   - progress: 传输进度回调 `(已传输字节数, 总字节数) -> 是否继续`，返回 `false` 中止传输
    /// - Returns: 是否完全写入成功
    @discardableResult
    func sftpWriteFileData(
        data: Data,
        path: String,
        mode: mode_t = 0o644,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        let input = InputStream(data: data)
        return sftpWriteFile(
            input: input,
            path: path,
            mode: mode,
            totalSize: data.count.int64,
            progress: progress
        )
    }

    // MARK: - 基础流式 IO(支持进度与取消)

    /// 从远程服务器读取文件内容并推送到输出流 (OutputStream)
    /// - Parameters:
    ///   - path: 远程文件路径
    ///   - output: 数据接收的目标输出流
    ///   - totalSize: 文件总字节数(用于计算进度)
    ///   - progress: 传输进度回调 `(已传输字节数, 总字节数) -> 是否继续`，返回 `false` 中止传输
    /// - Returns: 是否完全读取并写入成功
    @discardableResult
    func sftpReadFile(
        path: String,
        output: OutputStream,
        totalSize: Int64 = 0,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        let file: sftp_file? = mutex.withLock {
            guard let rawSFTP else { return nil }
            return sftp_open(rawSFTP, path.bytesArray, O_RDONLY, 0)
        }

        guard let file else { return false }
        defer {
            mutex.withVoid {
                sftp_close(file)
            }
        }

        let buffer = Buffer<UInt8>(bufferSize)
        if output.streamStatus == .notOpen {
            output.open()
        }
        defer { output.close() }

        var transferred: Int64 = 0

        while true {
            let bytesRead: Int = mutex.withLock {
                sftp_read(file, buffer.buffer, buffer.count).int
            }
            if bytesRead < 0 {
                return false
            }
            if bytesRead == 0 {
                break
            }

            if !writeAll(bytesRead, to: output, buffer: buffer) {
                return false
            }

            transferred += bytesRead.int64
            if let progress, !progress(transferred, totalSize) {
                return false
            }
        }

        return true
    }

    /// 从输入流 (InputStream) 读取数据并写入到远程服务器文件
    /// - Parameters:
    ///   - input: 数据来源输入流
    ///   - path: 远程写入目标路径
    ///   - mode: 创建文件时的默认权限(默认 `0o644`)
    ///   - totalSize: 文件总字节数(用于计算进度)
    ///   - progress: 传输进度回调 `(已传输字节数, 总字节数) -> 是否继续`，返回 `false` 中止传输
    /// - Returns: 是否完全读取流并写入成功
    @discardableResult
    func sftpWriteFile(
        input: InputStream,
        path: String,
        mode: mode_t = 0o644,
        totalSize: Int64 = 0,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        let file: sftp_file? = mutex.withLock {
            guard let rawSFTP else { return nil }
            let accessType = O_WRONLY | O_CREAT | O_TRUNC
            return sftp_open(rawSFTP, path.bytesArray, accessType.int32, mode)
        }

        guard let file else { return false }
        defer {
            mutex.withVoid {
                sftp_close(file)
            }
        }

        let buffer = Buffer<UInt8>(bufferSize)
        if input.streamStatus == .notOpen {
            input.open()
        }
        defer { input.close() }

        var transferred: Int64 = 0

        while input.hasBytesAvailable {
            let bytesRead = input.read(buffer.buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                return false
            }
            if bytesRead == 0 {
                break
            }

            if !writeAllToSFTP(file: file, buffer: buffer, length: bytesRead) {
                return false
            }

            transferred += bytesRead.int64
            if let progress, !progress(transferred, totalSize) {
                return false
            }
        }

        return true
    }

    // MARK: - 高级 URL 传输(支持文件与目录递归及全局总进度)

    /// 上传本地文件或目录至远程 SFTP 服务器
    /// - Parameters:
    ///   - localURL: 本地文件或目录 Request URL
    ///   - remotePath: 远程目标目录或完整文件路径
    ///   - progress: 传输进度回调 `(全局已传输字节数, 全局总字节数) -> 是否继续`
    /// - Returns: 是否上传成功
    @discardableResult
    func sftpUpload(
        localURL: URL,
        remotePath: String,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            return false
        }

        // 如果在过滤列表中，直接略过
        guard !filterFiles.contains(localURL.lastPathComponent) else {
            return true
        }

        // 1. 明确目标路径与总大小计算
        let totalSize: Int64
        let targetRemotePath: String

        if isDir.boolValue {
            totalSize = calculateLocalDirectorySize(url: localURL)
            if let stat = sftpStat(path: remotePath), stat.isDirectory {
                targetRemotePath = (remotePath as NSString).appendingPathComponent(localURL.lastPathComponent)
            } else {
                targetRemotePath = remotePath
            }
        } else {
            let attr = try? fileManager.attributesOfItem(atPath: localURL.path)
            totalSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0

            if let stat = sftpStat(path: remotePath), stat.isDirectory {
                targetRemotePath = (remotePath as NSString).appendingPathComponent(localURL.lastPathComponent)
            } else {
                targetRemotePath = remotePath
            }
        }

        var accumulatedTransferred: Int64 = 0
        _ = progress?(0, max(totalSize, 1))

        // 2. 调起递归上传
        let success = _sftpUploadRecursive(
            localURL: localURL,
            targetRemotePath: targetRemotePath,
            totalSize: totalSize,
            accumulatedTransferred: &accumulatedTransferred,
            progress: progress
        )

        if success {
            _ = progress?(totalSize, max(totalSize, 1))
        }

        return success
    }

    /// 从远程 SFTP 服务器下载文件或目录至本地
    /// - Parameters:
    ///   - remotePath: 远程文件或目录路径
    ///   - localURL: 本地保存的目标目录或文件 URL
    ///   - progress: 传输进度回调 `(全局已传输字节数, 动态探索到的全局总字节数) -> 是否继续`
    /// - Returns: 是否下载成功
    @discardableResult
    func sftpDownload(
        remotePath: String,
        localURL: URL,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) -> Bool {
        wait.add()
        defer {
            wait.done()
        }
        guard let remoteStat = sftpLstat(path: remotePath) else {
            return false
        }

        // 如果在过滤列表中，直接略过
        guard !filterFiles.contains((remotePath as NSString).lastPathComponent) else {
            return true
        }

        let fileManager = FileManager.default
        var isLocalDir: ObjCBool = false
        let localExists = fileManager.fileExists(atPath: localURL.path, isDirectory: &isLocalDir)

        // 1. 明确目标本地 URL
        let targetLocalURL: URL = if remoteStat.isDirectory {
            if localExists, isLocalDir.boolValue {
                localURL.appendingPathComponent((remotePath as NSString).lastPathComponent, isDirectory: true)
            } else {
                localURL
            }
        } else {
            if localURL.hasDirectoryPath || (localExists && isLocalDir.boolValue) {
                localURL.appendingPathComponent((remotePath as NSString).lastPathComponent)
            } else {
                localURL
            }
        }

        // 2. 取消预计算远程目录大小，初始化动态统计变量
        var accumulatedTransferred: Int64 = 0
        var discoveredTotalSize: Int64 = 0

        _ = progress?(0, 1)

        // 3. 调起递归下载
        let success = _sftpDownloadRecursive(
            remotePath: remotePath,
            targetLocalURL: targetLocalURL,
            discoveredTotalSize: &discoveredTotalSize,
            accumulatedTransferred: &accumulatedTransferred,
            progress: progress
        )

        if success {
            let finalTotal = max(discoveredTotalSize, accumulatedTransferred)
            _ = progress?(finalTotal, max(finalTotal, 1))
        }

        return success
    }

    // MARK: - 内部递归与容量计算辅助逻辑

    /// 递归上传内部实现
    private func _sftpUploadRecursive(
        localURL: URL,
        targetRemotePath: String,
        totalSize: Int64,
        accumulatedTransferred: inout Int64,
        progress: ((Int64, Int64) -> Bool)?
    ) -> Bool {
        // 过滤跳过配置的文件
        guard !filterFiles.contains(localURL.lastPathComponent) else {
            return true
        }

        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        guard fileManager.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            return false
        }

        if isDir.boolValue {
            guard sftpMkdirAll(directory: targetRemotePath) else {
                return false
            }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: localURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return false
            }

            for item in contents {
                // 双重确保跳过过滤文件
                guard !filterFiles.contains(item.lastPathComponent) else { continue }

                let subRemotePath = (targetRemotePath as NSString).appendingPathComponent(item.lastPathComponent)
                if !_sftpUploadRecursive(
                    localURL: item,
                    targetRemotePath: subRemotePath,
                    totalSize: totalSize,
                    accumulatedTransferred: &accumulatedTransferred,
                    progress: progress
                ) {
                    return false
                }
            }
            return true
        } else {
            guard let attr = try? fileManager.attributesOfItem(atPath: localURL.path),
                  let fileSize = (attr[.size] as? NSNumber)?.int64Value,
                  let mode = (attr[.posixPermissions] as? NSNumber)?.uint32Value,
                  let input = InputStream(url: localURL)
            else {
                return false
            }

            let startOffset = accumulatedTransferred

            let success = sftpWriteFile(
                input: input,
                path: targetRemotePath,
                mode: mode_t(mode),
                totalSize: fileSize,
                progress: { currentFileTransferred, _ in
                    let globalTransferred = startOffset + currentFileTransferred
                    return progress?(globalTransferred, totalSize) ?? true
                }
            )

            if success {
                accumulatedTransferred += fileSize
                _ = progress?(accumulatedTransferred, totalSize)
            }
            return success
        }
    }

    /// 递归下载内部实现(动态累加发现的总大小，无需提前预估)
    private func _sftpDownloadRecursive(
        remotePath: String,
        targetLocalURL: URL,
        discoveredTotalSize: inout Int64,
        accumulatedTransferred: inout Int64,
        progress: ((Int64, Int64) -> Bool)?
    ) -> Bool {
        let fileName = (remotePath as NSString).lastPathComponent
        // 过滤跳过配置的文件
        guard !filterFiles.contains(fileName) else {
            return true
        }

        guard let remoteStat = sftpLstat(path: remotePath) else {
            return false
        }

        // 跳过软链接文件/目录，避免死循环及体积偏差
        if remoteStat.isSymlink {
            return true
        }

        let fileManager = FileManager.default

        if remoteStat.isDirectory {
            if !fileManager.fileExists(atPath: targetLocalURL.path) {
                try? fileManager.createDirectory(at: targetLocalURL, withIntermediateDirectories: true)
            }

            let items = sftpOpendir(path: remotePath)
            for item in items {
                guard !filterFiles.contains(item.name) else {
                    continue
                }

                let subRemotePath = (remotePath as NSString).appendingPathComponent(item.name)
                let subLocalURL = targetLocalURL.appendingPathComponent(item.name)

                if !_sftpDownloadRecursive(
                    remotePath: subRemotePath,
                    targetLocalURL: subLocalURL,
                    discoveredTotalSize: &discoveredTotalSize,
                    accumulatedTransferred: &accumulatedTransferred,
                    progress: progress
                ) {
                    return false
                }
            }
            return true
        } else {
            let parentDir = targetLocalURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            guard let output = OutputStream(url: targetLocalURL, append: false) else {
                return false
            }

            let fileSize = remoteStat.size.int64

            // 实时将发现的新文件大小加到 discoveredTotalSize 中
            discoveredTotalSize += fileSize
            let currentTotal = max(discoveredTotalSize, 1)

            let startOffset = accumulatedTransferred

            let success = sftpReadFile(
                path: remotePath,
                output: output,
                totalSize: fileSize,
                progress: { currentFileTransferred, _ in
                    let globalTransferred = startOffset + currentFileTransferred
                    return progress?(globalTransferred, currentTotal) ?? true
                }
            )

            if success {
                accumulatedTransferred += fileSize
                _ = progress?(accumulatedTransferred, currentTotal)
            }
            return success
        }
    }

    /// 计算本地目录总字节大小(显式剔除 filterFiles 和 软链接)
    private func calculateLocalDirectorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard !filterFiles.contains(fileURL.lastPathComponent) else { continue }

            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]) {
                if resourceValues.isSymbolicLink == true {
                    continue
                }
                if let isDir = resourceValues.isDirectory, !isDir,
                   let size = resourceValues.fileSize
                {
                    total += size.int64
                }
            }
        }
        return total
    }

    /// 内部辅助方法：向输出流完整写入缓冲区数据
    private func writeAll(_ bytesToWrite: Int, to stream: OutputStream, buffer: Buffer<UInt8>) -> Bool {
        var offset = 0
        while offset < bytesToWrite {
            let written = stream.write(buffer.buffer.advanced(by: offset), maxLength: bytesToWrite - offset)
            if written < 0 {
                return false
            }
            offset += written
        }
        return true
    }

    /// 内部辅助方法：向 SFTP 文件句柄完整写入缓冲区数据
    private func writeAllToSFTP(file: sftp_file, buffer: Buffer<UInt8>, length: Int) -> Bool {
        var offset = 0
        while offset < length {
            let currentPtr = buffer.buffer.advanced(by: offset)
            let bytesRemaining = length - offset

            let written: Int = mutex.withLock {
                sftp_write(file, currentPtr, bytesRemaining).int
            }
            if written <= 0 {
                return false
            }
            offset += written
        }
        return true
    }

    // MARK: - 文件系统容量统计

    /// 获取远程路径挂载点文件系统的磁盘空间统计信息
    /// - Parameter path: 远程服务器上的文件路径或挂载点路径(例如 `"/"` 或 `"/var/www"`)
    /// - Returns: (totalBytes: 总容量, freeBytes: 物理空闲字节, availableBytes: 用户可用字节)，失败返回 nil
    func sftpStatVFS(path: String) -> (totalBytes: Int64, freeBytes: Int64, availableBytes: Int64)? {
        wait.add()
        defer {
            wait.done()
        }
        return mutex.withLock {
            guard let rawSFTP else { return nil }
            guard let statPtr = sftp_statvfs(rawSFTP, path.bytesArray) else {
                return nil
            }
            defer { sftp_statvfs_free(statPtr) }

            let vfs = statPtr.pointee

            let blockSize = (vfs.f_frsize > 0 ? vfs.f_frsize : vfs.f_bsize).int64
            let total = vfs.f_blocks.int64 * blockSize
            let free = vfs.f_bfree.int64 * blockSize
            let available = vfs.f_bavail.int64 * blockSize

            return (total, free, available)
        }
    }
}
