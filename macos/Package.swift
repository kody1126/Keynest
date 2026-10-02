// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Keynest",
    platforms: [.macOS(.v14)],
    products: [.library(name: "KeynestCore", targets: ["KeynestCore"]), .executable(name: "Keynest", targets: ["KeynestApp"])],
    targets: [
        .target(name: "KeynestCore"),
        .executableTarget(name: "KeynestApp", dependencies: ["KeynestCore"]),
        .testTarget(name: "KeynestCoreTests", dependencies: ["KeynestCore"])
    ]
)
