// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "cLockIn",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CLockInCore"),
        .executableTarget(name: "cLockIn", dependencies: ["CLockInCore"]),
        .testTarget(name: "CLockInCoreTests", dependencies: ["CLockInCore"]),
    ]
)
