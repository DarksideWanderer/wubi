// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WubiCoach",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WubiCoach", targets: ["WubiCoach"])],
    targets: [
        .target(name: "WubiCore"),
        .executableTarget(name: "WubiCoach", dependencies: ["WubiCore"]),
        .testTarget(name: "WubiCoreTests", dependencies: ["WubiCore"])
    ]
)
