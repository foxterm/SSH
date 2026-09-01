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
        .library(name: "Socket", targets: ["Socket"]),
        .library(name: "Proxy", targets: ["Proxy"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/krzyzanowskim/OpenSSL.git", .upToNextMajor(from: "3.6.0001")
        ),
        .package(url: "https://github.com/foxterm/libssh2.git", branch: "main"),
        .package(
            url: "https://github.com/apple/swift-atomics.git",
            .upToNextMajor(from: "1.2.0")
        ),
    ],
    targets: [
        .target(
            name: "Crypto",
            dependencies: [
                .target(name: "Extension"),
                .product(name: "OpenSSL", package: "OpenSSL"),
            ]
        ),
        .target(
            name: "SSH",
            dependencies: [
                .target(name: "Proxy"),
                .target(name: "Socket"),
                .target(name: "Extension"),
                .product(name: "CSSH2", package: "libssh2"),
            ]
        ),
        .target(
            name: "Extension",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
            ]
        ),
        .target(
            name: "Socket",
            dependencies: [
                .target(name: "Extension"),
            ]
        ),
        .target(
            name: "Proxy",
            dependencies: [
                .target(name: "Socket"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
