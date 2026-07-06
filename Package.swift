// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalTalk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalTalk", targets: ["LocalTalk"])
    ],
    targets: [
        .executableTarget(name: "LocalTalk")
    ]
)
