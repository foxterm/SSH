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
    ],
    dependencies: [
        .package(url: "https://github.com/foxterm/libetos.git", from: "1.0.1"),
        .package(url: "https://github.com/foxterm/Sync.git", from: "1.0.1"),
        .package(url: "https://github.com/foxterm/Proxy.git", from: "1.0.1"),
        .package(url: "https://github.com/foxterm/Extension.git", from: "1.0.1"),
        .package(url: "https://github.com/foxterm/OpenSSL.git", from: "1.0.1"),
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
