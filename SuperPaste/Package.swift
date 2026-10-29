// swift-tools-version: 5.10
import PackageDescription
import Foundation

// The Command Line Tools toolchain neither surfaces swift-testing to test
// targets ("no such module 'Testing'") nor links it, while the Xcode
// toolchain does both automatically. When the CLT toolchain is selected,
// point at and link the CLT's own Testing.framework -- exactly one runtime,
// so no mismatch. When Xcode is selected, add nothing: force-linking the
// CLT copy alongside Xcode's loads two Testing runtimes, which makes
// #expect misbehave and aborts the test runner (signal 6).
func selectedDeveloperDir() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["-p"]
    let pipe = Pipe()
    process.standardOutput = pipe
    guard let _ = try? process.run() else { return "" }
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let usingCommandLineTools = selectedDeveloperDir().hasPrefix("/Library/Developer/CommandLineTools")
    && FileManager.default.fileExists(atPath: cltFrameworks)

let testSwiftSettings: [SwiftSetting]? = usingCommandLineTools
    ? [.unsafeFlags(["-F", cltFrameworks])]
    : nil
let testLinkerSettings: [LinkerSetting]? = usingCommandLineTools
    ? [.unsafeFlags([
        "-F", cltFrameworks,
        "-framework", "Testing",
        "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
    ])]
    : nil

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
        ),
        .testTarget(
            name: "SuperPasteTests",
            dependencies: ["SuperPaste"],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        )
    ]
)
