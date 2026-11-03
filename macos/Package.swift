// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Seamless",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Seamless", targets: ["SeamlessApp"])],
    targets: [
        .target(name: "SeamlessCore"),
        .executableTarget(name: "SeamlessApp", dependencies: ["SeamlessCore"]),
        .testTarget(name: "SeamlessCoreTests", dependencies: ["SeamlessCore"]),
        .testTarget(name: "SeamlessAppTests", dependencies: ["SeamlessApp", "SeamlessCore"])
    ]
)
