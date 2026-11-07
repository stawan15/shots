// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shots",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shots", targets: ["shots"]),
        .executable(name: "shots-selftest", targets: ["shots-selftest"]),
    ],
    targets: [
        .target(
            name: "ShotsCore",
            path: "Sources/ShotsCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "shots",
            dependencies: ["ShotsCore"],
            path: "Sources/shots",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The CommandLineTools toolchain here ships no XCTest, so the checks live
        // in a small executable instead of a test target.
        .executableTarget(
            name: "shots-selftest",
            dependencies: ["ShotsCore"],
            path: "Sources/shots-selftest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
