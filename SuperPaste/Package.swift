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
    dependencies: [],
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
