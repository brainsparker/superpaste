// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SuperPaste",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SuperPaste", targets: ["SuperPaste"])
    ],
    targets: [
        .executableTarget(
            name: "SuperPaste",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
