// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "SSH",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
    ],
    products: [
        .library(name: "SSH", targets: ["SSH"]),
        .library(name: "Crypto", targets: ["Crypto"]),
        .library(name: "Extension", targets: ["Extension"]),
        .library(name: "Sync", targets: ["Sync"]),
        .library(name: "libetos", targets: ["libetos"]),
        .library(name: "Proxy", targets: ["libetos"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/krzyzanowskim/OpenSSL.git", .upToNextMajor(from: "3.6.0001")
        ),
        .package(url: "https://github.com/foxterm/libssh2.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Crypto",
            dependencies: [
                .target(name: "Extension"),
                .product(name: "OpenSSL", package: "OpenSSL"),
                .target(name: "libetos"),
            ]
        ),
        .target(
            name: "SSH",
            dependencies: [
                .target(name: "Extension"),
                .target(name: "Proxy"),
                .target(name: "Sync"),
                .product(name: "CSSH2", package: "libssh2"),
            ]
        ),
        .target(
            name: "Extension"
        ),
        .target(
            name: "Proxy",
            dependencies: [
                .target(name: "Extension"),
                .target(name: "libetos"),
            ]
        ),
        .target(
            name: "Sync",
            dependencies: [
                .target(name: "libetos"),
            ]
        ),
        .target(
            name: "libetos"
        ),
        .target(
            name: "libtracked",
            dependencies: [
                .product(name: "OpenSSL", package: "OpenSSL"),
                .product(name: "CSSH2", package: "libssh2"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
