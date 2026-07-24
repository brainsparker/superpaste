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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "SuperPaste",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [
                .process("../Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        )
    ]
)
