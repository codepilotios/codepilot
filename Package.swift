// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexAccountSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "149.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CodexAccountSwitcher",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ]
        ),
        .testTarget(
            name: "CodexAccountSwitcherTests",
            dependencies: ["CodexAccountSwitcher"]
        )
    ]
)
