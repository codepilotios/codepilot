// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexAccountSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework-static.git", exact: "144.7559.10")
    ],
    targets: [
        .executableTarget(
            name: "CodexAccountSwitcher",
            dependencies: [
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework-static")
            ]
        ),
        .testTarget(
            name: "CodexAccountSwitcherTests",
            dependencies: ["CodexAccountSwitcher"]
        )
    ]
)
