// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FoundationChat",
    platforms: [
        .macOS(.v27),
        .iOS(.v27)
    ],
    targets: [
        .executableTarget(
            name: "FoundationChat",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FoundationChatTests",
            dependencies: ["FoundationChat"]
        )
    ]
)
