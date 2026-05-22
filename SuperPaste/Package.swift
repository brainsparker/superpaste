// swift-tools-version: 5.10
import PackageDescription

// NOTE: builds must pass `-Xswiftc -swift-version -Xswiftc 5 -Xswiftc -enable-bare-slash-regex`
// to compile the mlx-swift-lm / swift-jinja transitive deps cleanly on Swift 6.x toolchains.
// See ./bin/spike.sh (and build.sh once MLX lands in the main target).
let package = Package(
    name: "SuperPaste",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SuperPaste", targets: ["SuperPaste"]),
        .executable(name: "MLXSpike", targets: ["MLXSpike"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3")
    ],
    targets: [
        .executableTarget(
            name: "SuperPaste",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        ),
        .executableTarget(
            name: "MLXSpike",
            dependencies: [
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "MLXSpike",
            exclude: ["test.jpg"]
        )
    ]
)
