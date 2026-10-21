// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "SSH",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SSH", targets: ["SSH"]),
        .library(name: "OpenSSL", targets: ["OpenSSL"]),
    ],
    dependencies: [
        .package(url: "https://github.com/foxterm/libetos.git", branch: "main"),
        .package(url: "https://github.com/foxterm/Sync.git", branch: "main"),
        .package(url: "https://github.com/foxterm/Proxy.git", branch: "main"),
        .package(url: "https://github.com/foxterm/Extension.git", branch: "main"),
        .package(
            url: "https://github.com/krzyzanowskim/OpenSSL.git",
            from: "3.6.5000"
        ),
    ],
    targets: [
        .binaryTarget(
            name: "libssh",
            path: "libssh.xcframework"
        ),
        .target(
            name: "SSH",
            dependencies: [
                .product(name: "libetos", package: "libetos"),
                .product(name: "Sync", package: "Sync"),
                .product(name: "Proxy", package: "Proxy"),
                .product(name: "Extension", package: "Extension"),
                .product(name: "OpenSSL", package: "OpenSSL"),
                "libssh",
            ],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
    ]
)
