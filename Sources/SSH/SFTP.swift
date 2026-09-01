// FoxTerm | SFTP.swift
// Copyright (c) 2025-2026 foxterm.app
// Created by foxterm@foxmail.com

import CSSH2
import Extension
import Foundation

/// SFTP 客户端类，封装了基于 libssh2 的文件传输协议操作
public class SFTP {
    let mutex: NSLock = .init()
    /// 内部持有的 libssh2 SFTP 会话原始指针
    public internal(set) var _rawSFTP: OpaquePointer?
    public internal(set) var handle: OpaquePointer?

    /// SFTP 列表显示时默认忽略的文件名
    public var ignoredfiles: [String] = [".", ".."]

    /// 关联的 SSH 会话实例
    let ssh: SSH

    init(ssh: SSH) {
        self.ssh = ssh
    }

    deinit {
        #if DEBUG
            print("♻️", "SFTP 实例已释放")
        #endif
    }
}

public extension SFTP {
    /// 获取底层的 SSH 会话指针
    internal var rawSession: OpaquePointer? {
        ssh.rawSession
    }

    /// 获取或初始化 SFTP 会话指针
    internal var rawSFTP: OpaquePointer? {
        mutex.lock()
        defer {
            mutex.unlock()
        }
        guard rawSession != nil else { return nil }
        if _rawSFTP != nil {
            return _rawSFTP
        }

        // 如果未初始化，则调用 libssh2_sftp_init
        _rawSFTP = ssh.callSSH2 { [self] in
            libssh2_sftp_init(rawSession)
        }
        return _rawSFTP
    }

    /// 检查最近一次 SFTP 操作是否出错
    var isSFTPError: Bool {
        guard rawSFTP != nil else { return true }
        return libssh2_sftp_last_error(rawSFTP) != LIBSSH2_FX_OK
    }

    /// 读取符号链接指向的目标路径
    /// - Parameter path: 链接文件路径
    /// - Returns: 目标路径字符串，失败返回 nil
    func readlink(path: String) async -> String? {
        guard rawSFTP != nil else { return nil }
        let buf: Buffer<CChar> = .init(0x400)
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_symlink_ex(
                rawSFTP,
                path,
                path.count.uint32,
                buf.buffer,
                buf.count.uint32,
                LIBSSH2_SFTP_READLINK
            )
        }
        guard rc > 0 else { return nil }
        return buf.data(rc.int).string
    }

    /// 获取远程路径的规范化绝对路径
    /// - Parameter path: 需要转换的路径
    /// - Returns: 规范化的绝对路径，失败返回 nil
    func realpath(path: String) async -> String? {
        guard rawSFTP != nil else { return nil }
        let buf: Buffer<CChar> = .init(0x400)
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_symlink_ex(
                rawSFTP,
                path,
                path.count.uint32,
                buf.buffer,
                buf.count.uint32,
                LIBSSH2_SFTP_REALPATH
            )
        }
        guard rc > 0 else { return nil }
        return buf.data(rc.int).string
    }

    /// 重命名或移动远程文件/目录
    /// - Parameters:
    ///   - orig: 源路径
    ///   - newname: 目标路径
    /// - Returns: 是否成功
    func rename(orig: String, newname: String) async -> Bool {
        guard rawSFTP != nil else { return false }
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_rename_ex(
                rawSFTP,
                orig,
                orig.count.uint32,
                newname,
                newname.count.uint32,
                Int(
                    LIBSSH2_SFTP_RENAME_OVERWRITE | LIBSSH2_SFTP_RENAME_ATOMIC
                        | LIBSSH2_SFTP_RENAME_NATIVE
                )
            )
        }
        return rc == LIBSSH2_ERROR_NONE
    }

    /// 创建远程目录
    /// - Parameters:
    ///   - path: 目录路径
    ///   - permissions: 文件权限（默认为 0755）
    /// - Returns: 是否成功
    func mkdir(path: String, permissions: FilePermissions = .default) async -> Bool {
        guard rawSFTP != nil else { return false }
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_mkdir_ex(rawSFTP, path, path.count.uint32, permissions.rawInt)
        }
        return rc == LIBSSH2_ERROR_NONE
    }

    /// 递归创建远程目录（类似 mkdir -p）
    /// - Parameter path: 完整的目录路径
    func mkdirAll(path: String) async {
        let components = path.components(separatedBy: "/")
        var currentPath = ""
        // 处理绝对路径开头
        if path.hasPrefix("/") {
            currentPath = "/"
        }

        for component in components where !component.isEmpty {
            if currentPath == "/" {
                currentPath += component
            } else {
                currentPath += (currentPath.isEmpty ? "" : "/") + component
            }

            // 检查目录是否存在，不存在则创建
            if await stat(path: currentPath) == nil {
                _ = await mkdir(path: currentPath)
            }
        }
    }

    /// 创建一个空的远程文件
    /// - Parameters:
    ///   - path: 文件路径
    ///   - permissions: 文件权限
    /// - Returns: 是否成功
    func mkfile(path: String, permissions: FilePermissions = .default) async -> Bool {
        await closeHandle()
        guard rawSFTP != nil else { return false }
        handle = await ssh.callSSH2 { [self] in
            libssh2_sftp_open_ex(
                rawSFTP,
                path,
                path.count.uint32,
                UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC),
                permissions.rawInt,
                LIBSSH2_SFTP_OPENFILE
            )
        }
        guard handle != nil else { return false }
        await closeHandle()
        return true
    }

    /// 删除远程目录
    /// - Parameter path: 目录路径
    /// - Returns: 是否成功
    func rmdir(path: String) async -> Bool {
        guard rawSFTP != nil else { return false }
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_rmdir_ex(rawSFTP, path, path.count.uint32)
        }
        return rc == LIBSSH2_ERROR_NONE
    }

    /// 删除远程文件
    /// - Parameter path: 文件路径
    /// - Returns: 是否成功
    func unlink(path: String) async -> Bool {
        guard rawSFTP != nil else { return false }
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_unlink_ex(rawSFTP, path, path.count.uint32)
        }
        return rc == LIBSSH2_ERROR_NONE
    }

    /// 创建符号链接
    /// - Parameters:
    ///   - orig: 原始文件路径
    ///   - linkpath: 链接文件路径
    /// - Returns: 是否成功
    func symlink(orig: String, linkpath: String) async -> Bool {
        guard rawSFTP != nil else { return false }
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_symlink_ex(
                rawSFTP,
                orig,
                orig.count.uint32,
                linkpath.bytes,
                linkpath.count.uint32,
                LIBSSH2_SFTP_SYMLINK
            )
        }
        return rc == LIBSSH2_ERROR_NONE
    }

    /// 修改远程文件/目录的所有者和所属组
    /// - Parameters:
    ///   - path: 目标路径
    ///   - uid: 用户 ID
    ///   - gid: 组 ID
    /// - Returns: 是否成功
    func chown(path: String, uid: UInt, gid: UInt) async -> Bool {
        guard rawSFTP != nil else { return false }
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()
        attrs.flags = UInt(LIBSSH2_SFTP_ATTR_UIDGID)
        attrs.uid = uid
        attrs.gid = gid
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_stat_ex(rawSFTP, path, path.count.uint32, LIBSSH2_SFTP_SETSTAT, &attrs)
        }
        return rc == LIBSSH2_ERROR_NONE
    }

    /// 修改远程文件/目录的权限
    /// - Parameters:
    ///   - path: 目标路径
    ///   - permissions: 权限对象
    /// - Returns: 是否成功
    func chown(path: String, permissions: FilePermissions) async -> Bool {
        guard rawSFTP != nil else { return false }
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()
        attrs.flags = UInt(LIBSSH2_SFTP_ATTR_PERMISSIONS)
        attrs.permissions = permissions.rawUInt
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_stat_ex(rawSFTP, path, path.count.uint32, LIBSSH2_SFTP_SETSTAT, &attrs)
        }
        return rc == LIBSSH2_ERROR_NONE
    }

    /// 获取远程文件系统的状态（剩余空间等）
    /// - Parameter path: 挂载点路径，默认 "/"
    /// - Returns: Statvfs 结构体，失败返回 nil
    func statvfs(path: String = "/") async -> Statvfs? {
        guard rawSFTP != nil else { return nil }
        var st = LIBSSH2_SFTP_STATVFS()
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_statvfs(rawSFTP, path, path.count, &st)
        }
        guard rc == LIBSSH2_ERROR_NONE else { return nil }
        return Statvfs(statvfs: st)
    }

    /// 获取远程文件或目录的状态信息
    /// - Parameter path: 目标路径
    /// - Returns: FileStat 结构体，失败返回 nil
    func stat(path: String) async -> FileStat? {
        guard rawSFTP != nil else { return nil }
        var st = LIBSSH2_SFTP_ATTRIBUTES()
        let rc = await ssh.callSSH2 { [self] in
            libssh2_sftp_stat_ex(rawSFTP, path, path.count.uint32, LIBSSH2_SFTP_STAT, &st)
        }
        guard rc == LIBSSH2_ERROR_NONE else { return nil }
        return FileStat(attributes: st)
    }

    /// 列出远程目录下的所有文件和子目录
    /// - Parameter path: 目录路径，默认 "/"
    /// - Returns: 文件属性列表
    func openDir(path: String = "/") async -> [FileAttributes] {
        await closeHandle()
        guard rawSFTP != nil else {
            return []
        }
        handle = await ssh.callSSH2 { [self] in
            libssh2_sftp_open_ex(
                rawSFTP, path, path.count.uint32, UInt(LIBSSH2_FXF_READ), 0, LIBSSH2_SFTP_OPENDIR
            )
        }
        guard handle != nil else {
            return []
        }

        var data: [FileAttributes] = []
        var rc: Int32
        let buffer: Buffer<CChar> = .init(0x200)
        let longEntry: Buffer<CChar> = .init(0x400)
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()
        repeat {
            rc = await ssh.callSSH2 { [self] in
                libssh2_sftp_readdir_ex(
                    handle, buffer.buffer, buffer.count, longEntry.buffer, longEntry.count, &attrs
                )
            }
            if rc > 0 {
                let name = String(cString: buffer.buffer)
                let longname = String(cString: longEntry.buffer)
                guard !ignoredfiles.contains(name) else {
                    continue
                }
                data.append(FileAttributes(name: name, longname: longname, attributes: attrs))
            }
        } while rc > 0
        await closeHandle()
        return data
    }

    /// 上传本地文件到远程服务器
    /// - Parameters:
    ///   - localPath: 本地文件路径
    ///   - remotePath: 远程目标路径
    ///   - permissions: 设置远程文件权限（默认 0644）
    ///   - progress: 进度回调，返回已发送字节数。返回 `false` 可中止上传。
    /// - Returns: 是否上传成功
    func upload(
        localPath: String,
        remotePath: String,
        permissions: FilePermissions = .default,
        progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Bool {
        guard let stream = InputStream(fileAtPath: localPath) else {
            return false
        }
        guard
            let size = try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64
        else {
            return false
        }
        return await upload(
            stream: stream,
            size: size,
            remotePath: remotePath,
            permissions: permissions,
            progress: progress
        )
    }

    /// 将 Data 数据块上传到远程服务器
    /// - Parameters:
    ///   - data: 要上传的二进制数据
    ///   - remotePath: 远程目标路径
    ///   - permissions: 远程文件权限
    ///   - progress: 进度回调
    /// - Returns: 是否上传成功
    func upload(
        data: Data,
        remotePath: String,
        permissions: FilePermissions = .default,
        progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Bool {
        await upload(
            stream: .init(data: data),
            size: data.count.int64,
            remotePath: remotePath,
            permissions: permissions,
            progress: progress
        )
    }

    /// 通过输入流（InputStream）上传内容到远程服务器
    /// - Parameters:
    ///   - stream: 数据源流
    ///   - size: 预期上传的总字节数
    ///   - remotePath: 远程目标路径
    ///   - permissions: 远程文件权限
    ///   - progress: 进度回调
    /// - Returns: 是否完整上传成功
    func upload(
        stream: InputStream,
        size: Int64,
        remotePath: String,
        permissions: FilePermissions,
        progress: @escaping (_ send: Int) -> Bool = { _ in true }
    ) async -> Bool {
        await closeHandle()
        guard rawSFTP != nil else {
            return false
        }
        // 打开远程文件进行写入（创建/覆盖/截断）
        handle = await ssh.callSSH2 { [self] in
            libssh2_sftp_open_ex(
                rawSFTP,
                remotePath,
                remotePath.count.uint32,
                UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC),
                permissions.rawInt,
                LIBSSH2_SFTP_OPENFILE
            )
        }
        guard handle != nil else {
            return false
        }
        // 使用 io.Copy 进行流式传输
        guard await io.Copy(stream, write, ssh.bufferSize, progress) == size.int else {
            await closeHandle()
            return false
        }
        await closeHandle()
        return true
    }

    /// 下载远程文件到本地路径
    /// - Parameters:
    ///   - localPath: 本地存储路径
    ///   - remotePath: 远程源文件路径
    ///   - progress: 进度回调，包含 (已发送, 总大小)
    /// - Returns: 是否下载成功
    func download(
        localPath: String,
        remotePath: String,
        progress: @escaping (_ send: Int, _ size: Int) -> Bool = { _, _ in true }
    ) async -> Bool {
        guard let stream = OutputStream(toFileAtPath: localPath, append: false) else {
            return false
        }
        return await download(stream: stream, remotePath: remotePath, progress: progress)
    }

    /// 下载远程文件内容并返回 Data
    /// - Parameters:
    ///   - remotePath: 远程源文件路径
    ///   - progress: 进度回调
    /// - Returns: 文件二进制数据，失败返回 nil
    func download(
        remotePath: String,
        progress: @escaping (_ send: Int, _ size: Int) -> Bool = { _, _ in true }
    ) async -> Data? {
        let stream = OutputStream.toMemory()
        guard await download(stream: stream, remotePath: remotePath, progress: progress) else {
            return nil
        }
        return stream.data
    }

    /// 通过输出流（OutputStream）下载远程文件
    /// - Parameters:
    ///   - stream: 目标输出流
    ///   - remotePath: 远程源文件路径
    ///   - progress: 进度回调
    /// - Returns: 是否完整下载成功
    func download(
        stream: OutputStream,
        remotePath: String,
        progress: @escaping (_ send: Int, _ size: Int) -> Bool = { _, _ in true }
    ) async -> Bool {
        await closeHandle()
        guard rawSFTP != nil else {
            return false
        }
        // 获取文件状态以确定文件大小
        var fileinfo = LIBSSH2_SFTP_ATTRIBUTES()
        let stat = await ssh.callSSH2 { [self] in
            libssh2_sftp_stat_ex(
                rawSFTP, remotePath, remotePath.count.uint32, LIBSSH2_SFTP_STAT, &fileinfo
            )
        }
        guard stat == LIBSSH2_ERROR_NONE else {
            return false
        }

        // 打开远程文件进行读取
        handle = await ssh.callSSH2 { [self] in
            libssh2_sftp_open_ex(
                rawSFTP,
                remotePath,
                remotePath.count.uint32,
                UInt(LIBSSH2_FXF_READ),
                0,
                LIBSSH2_SFTP_OPENFILE
            )
        }
        guard handle != nil else {
            return false
        }
        let size = fileinfo.filesize.int
        let rc = await io.Copy(stream, read, ssh.bufferSize) { send in
            progress(send, size)
        }
        // 校验下载字节数是否与文件属性大小一致
        guard rc == size else {
            await closeHandle()
            return false
        }
        await closeHandle()
        return true
    }

    var read: InputStream {
        SSHInputStream(handle: handle, ssh: ssh, stream: .sftp)
    }

    var write: OutputStream {
        SSHOutputStream(handle: handle, ssh: ssh, stream: .sftp)
    }

    func closeHandle() async {
        guard handle != nil else {
            return
        }
        _ = await ssh.callSSH2 { [self] in
            libssh2_sftp_close_handle(handle)
        }
        handle = nil
    }

    /// 释放 SFTP 资源并关闭会话
    /// 使用互斥锁保证线程安全，防止多次释放
    func freeSFTP() {
        guard rawSFTP != nil else {
            return
        }
        libssh2_sftp_shutdown(rawSFTP)
        _rawSFTP = nil
    }
}
