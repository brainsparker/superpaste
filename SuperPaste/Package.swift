// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperPaste",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SuperPaste", targets: ["SuperPaste"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "SuperPaste",
            dependencies: ["HotKey"],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
