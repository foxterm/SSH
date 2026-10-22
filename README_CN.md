# SSH

[English](README.md) | [中文文档](README_CN.md)

FoxTerm APP 专用 SSH 核心库，基于 libssh 的 Swift 封装，支持 SSH 会话管理、SFTP/SCP 文件传输、端口转发及远程主机监控。

> 本库为 [FoxTerm](https://foxterm.app/) APP 专用核心组件，欢迎下载使用：[https://foxterm.app/](https://foxterm.app/)

## 功能

- **SSH 会话** — 连接、握手、已知主机校验、Keepalive
- **身份认证** — 密码、公钥、键盘交互式、None
- **Shell / Terminal** — 交互式终端，stdout/stderr 实时流，窗口尺寸调整
- **SFTP** — 目录浏览、文件上传下载、权限管理、断点续传
- **SCP** — 文件与目录递归上传下载，进度回调
- **端口转发** — Direct TCP/IP 本地端口转发
- **远程监控** — CPU、内存、磁盘、网络、GPU、进程、容器（Docker/Podman）、传感器
- **压缩传输** — zlib 压缩，可配置压缩级别（1-9）
- **归档解压** — 支持 tar.gz / tar.bz2 / tar.xz / tar / zip / 7z

## 环境要求

| 平台 | 最低版本 |
|------|---------|
| iOS  | 17.0    |
| macOS | 14.0   |
| Swift | 5.10   |

## 安装

### Swift Package Manager

```swift
.package(url: "https://github.com/foxterm/SSH.git", branch: "main"),
```

```swift
.product(name: "SSH", package: "SSH"),
```

### CocoaPods

```ruby
pod 'SSH', :git => 'https://github.com/foxterm/SSH.git'
```

### 依赖

- [libetos](https://github.com/foxterm/libetos) — 底层 Socket 与缓冲区
- [Sync](https://github.com/foxterm/Sync) — 原子操作、互斥锁、等待组
- [Proxy](https://github.com/foxterm/Proxy) — 网络代理支持
- [Extension](https://github.com/foxterm/Extension) — Foundation 扩展
- [libssh](https://www.libssh.org) — SSH 协议实现（上游）
- [OpenSSL](https://github.com/foxterm/OpenSSL) — OpenSSL 加密工具库

## 使用

> `SSH` 是 Swift actor，所有方法与可变属性均为 actor 隔离，需在异步上下文中使用 `await` 调用。

### 建立连接

```swift
let ssh = SSH(host: "192.168.1.100", port: 22, timeout: 10)
await ssh.authUser(user: "root")

// 注册代理
await ssh.registerSessionDelegate(self)
await ssh.registerShellDelegate(self)

// 1. TCP Socket 连接
guard await ssh.connect() else { return }

// 或通过代理连接
// guard await ssh.connect(proxy: proxyConfig) else { return }

// 或绑定指定网卡
// guard await ssh.connect(ifname: "en0") else { return }

// 2. SSH 握手
guard await ssh.handshake() else { return }

// 3. 查询可用认证方式
let methods = await ssh.authList()

// 4. 认证
// 密码认证
await ssh.authPassword(password: "password")

// 或公钥认证
// await ssh.authPublickey(privkey: privateKeyBase64, passphrase: "")
```

### Shell 终端

```swift
await ssh.shell(term: "xterm-256color", cols: 120, rows: 40)
await ssh.write(data: Data("ls -la\n".utf8))
await ssh.requestPtySize(cols: 160, rows: 50) // 防抖版本：await ssh.debouncedRequestPtySize(cols:rows:)
```

### SFTP 文件操作

```swift
await ssh.sftpInit()

// 列出目录
let entries = await ssh.sftpOpendir(path: "/home/user")

// 下载文件
await ssh.sftpDownload(remotePath: "/remote/file.txt", localURL: localURL, progress: { received, total in
    return true // 返回 false 取消传输
})

// 上传文件
await ssh.sftpUpload(localURL: localURL, remotePath: "/remote/file.txt")
```

### SCP 传输

```swift
await ssh.scpUpload(localURL: localURL, remotePath: "/remote/dir", recursive: true, progress: { received, total in
    return true
})

await ssh.scpDownload(remotePath: "/remote/file.txt", localDirectoryURL: localURL)
```

### 端口转发

```swift
await ssh.sshOpenDirectTCPIP(
    remoteHost: "db.internal",
    remotePort: 3306,
    outputStream: output,
    inputStream: input
)
```

### 远程主机监控

```swift
let machine = await ssh.machine

let cpu = await machine.getCPUTimesStat()
let mem = await machine.getMemoryStat()
let disk = await machine.getDiskUsageStat()
let net = await machine.getNetIOCountersStat()
let load = await machine.getAvgStat()
let process = await machine.getSystemProcess()
let container = await machine.getDockerStat()
let gpu = await machine.getGPUTimesStat()
let sensors = await machine.getTemp()
```

### 代理回调

```swift
extension ViewController: SessionDelegate {
    func disconnect() { /* 连接断开 */ }

    func knownState(info: HostInfo, state: ssh_known_hosts_e) -> Bool {
        // 校验主机指纹，返回是否信任
        return true
    }

    func keyboardInteractive(name: String, instruction: String, prompt: String) -> String {
        return "用户输入"
    }
}

extension ViewController: ShellDelegate {
    func stdout(data: Data) { /* 标准输出 */ }
    func stderr(data: Data) { /* 标准错误 */ }
    func shell() { /* Shell 已启动 */ }
}
```

## 项目结构

```
Sources/SSH/
├── SSH.swift              # 核心客户端（actor）
├── Session.swift          # 握手、会话管理
├── Auth.swift             # 身份认证
├── Socket.swift           # TCP 连接
├── Terminal.swift         # Shell 终端
├── SFTP.swift             # SFTP 文件操作
├── SCP.swift              # SCP 传输
├── Direct.swift           # 端口转发
├── Archive.swift          # 远程归档解压
├── SSHKey.swift           # 密钥管理
├── Protocol.swift         # SessionDelegate / ShellDelegate
├── Types.swift            # 枚举与数据模型
├── Extension.swift        # 内部扩展
├── FilePermissions.swift  # 文件权限
├── TerminalMode.swift     # 终端模式配置
├── LocalPortForwarder.swift # 本地端口转发封装
├── ClosureOutputStream.swift
└── Machine/               # 远程主机监控
    ├── Machine.swift      # 监控入口
    ├── CPU.swift
    ├── Mem.swift
    ├── Disk.swift
    ├── Net.swift
    ├── Load.swift
    ├── GPU.swift
    ├── Process.swift
    ├── Container.swift
    ├── ContainerDTO.swift
    ├── Host.swift
    ├── Sensors.swift
    ├── LinuxStats.swift
    └── StreamStats.swift
libssh.xcframework/        # 预编译 libssh（iOS + macOS）
```

## 许可证

MIT
