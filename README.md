# SSH

[English](README.md) | [中文文档](README_CN.md)

A dedicated SSH core library for the FoxTerm app — a Swift wrapper built on libssh, supporting SSH session management, SFTP/SCP file transfer, port forwarding, and remote host monitoring.

> This library is a dedicated core component for the [FoxTerm](https://foxterm.app/) app. Download it here: [https://foxterm.app/](https://foxterm.app/)

## Features

- **SSH Sessions** — Connection, handshake, known host verification, keepalive
- **Authentication** — Password, public key, keyboard-interactive, none
- **Shell / Terminal** — Interactive terminal with real-time stdout/stderr streams and window resizing
- **SFTP** — Directory browsing, file upload/download, permission management, resume support
- **SCP** — Recursive file and directory upload/download with progress callbacks
- **Port Forwarding** — Direct TCP/IP local port forwarding
- **Remote Monitoring** — CPU, memory, disk, network, GPU, processes, containers (Docker/Podman), sensors
- **Compressed Transfer** — zlib compression with configurable levels (1–9)
- **Archive Extraction** — Supports tar.gz / tar.bz2 / tar.xz / tar / zip / 7z

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 17.0           |
| macOS    | 14.0           |
| Swift    | 5.10           |

## Installation

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

### Dependencies

- [libetos](https://github.com/foxterm/libetos) — Low-level socket and buffer management
- [Sync](https://github.com/foxterm/Sync) — Atomic operations, mutexes, wait groups
- [Proxy](https://github.com/foxterm/Proxy) — Network proxy support
- [Extension](https://github.com/foxterm/Extension) — Foundation extensions
- [libssh](https://www.libssh.org) — SSH protocol implementation (upstream)
- [OpenSSL](https://github.com/foxterm/OpenSSL) — OpenSSL cryptographic toolkit

## Usage

> `SSH` is a Swift actor — all methods and mutable properties are actor-isolated, so every call requires `await` from an async context.

### Establishing a Connection

```swift
let ssh = SSH(host: "192.168.1.100", port: 22, timeout: 10)
await ssh.authUser(user: "root")

// Register delegates
await ssh.registerSessionDelegate(self)
await ssh.registerShellDelegate(self)

// 1. TCP socket connection
guard await ssh.connect() else { return }

// Or connect through a proxy
// guard await ssh.connect(proxy: proxyConfig) else { return }

// Or bind to a specific network interface
// guard await ssh.connect(ifname: "en0") else { return }

// 2. SSH handshake
guard await ssh.handshake() else { return }

// 3. Query available authentication methods
let methods = await ssh.authList()

// 4. Authenticate
// Password authentication
await ssh.authPassword(password: "password")

// Or public key authentication
// await ssh.authPublickey(privkey: privateKeyBase64, passphrase: "")
```

### Shell Terminal

```swift
await ssh.shell(term: "xterm-256color", cols: 120, rows: 40)
await ssh.write(data: Data("ls -la\n".utf8))
await ssh.requestPtySize(cols: 160, rows: 50) // Debounced: await ssh.debouncedRequestPtySize(cols:rows:)
```

### SFTP File Operations

```swift
await ssh.sftpInit()

// List directory contents
let entries = await ssh.sftpOpendir(path: "/home/user")

// Download a file
await ssh.sftpDownload(remotePath: "/remote/file.txt", localURL: localURL, progress: { received, total in
    return true // Return false to cancel the transfer
})

// Upload a file
await ssh.sftpUpload(localURL: localURL, remotePath: "/remote/file.txt")
```

### SCP Transfer

```swift
await ssh.scpUpload(localURL: localURL, remotePath: "/remote/dir", recursive: true, progress: { received, total in
    return true
})

await ssh.scpDownload(remotePath: "/remote/file.txt", localDirectoryURL: localURL)
```

### Port Forwarding

```swift
await ssh.sshOpenDirectTCPIP(
    remoteHost: "db.internal",
    remotePort: 3306,
    outputStream: output,
    inputStream: input
)
```

### Remote Host Monitoring

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

### Delegate Callbacks

```swift
extension ViewController: SessionDelegate {
    func disconnect() { /* Connection lost */ }

    func knownState(info: HostInfo, state: ssh_known_hosts_e) -> Bool {
        // Verify host fingerprint, return whether to trust
        return true
    }

    func keyboardInteractive(name: String, instruction: String, prompt: String) -> String {
        return "User input"
    }
}

extension ViewController: ShellDelegate {
    func stdout(data: Data) { /* Standard output */ }
    func stderr(data: Data) { /* Standard error */ }
    func shell() { /* Shell started */ }
}
```

## Project Structure

```
Sources/SSH/
├── SSH.swift              # Core client (actor)
├── Session.swift          # Handshake and session management
├── Auth.swift             # Authentication
├── Socket.swift           # TCP connection
├── Terminal.swift         # Shell terminal
├── SFTP.swift             # SFTP file operations
├── SCP.swift              # SCP transfer
├── Direct.swift           # Port forwarding
├── Archive.swift          # Remote archive extraction
├── SSHKey.swift           # Key management
├── Protocol.swift         # SessionDelegate / ShellDelegate
├── Types.swift            # Enums and data models
├── Extension.swift        # Internal extensions
├── FilePermissions.swift  # File permissions
├── TerminalMode.swift     # Terminal mode configuration
├── LocalPortForwarder.swift # Local port forwarding wrapper
├── ClosureOutputStream.swift
└── Machine/               # Remote host monitoring
    ├── Machine.swift      # Monitoring entry point
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
libssh.xcframework/        # Precompiled libssh (iOS + macOS)
```

## License

MIT
