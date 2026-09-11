// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LidFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LidFlow", targets: ["LidFlow"])],
    targets: [
        .target(name: "FoldCore"),
        .executableTarget(name: "LidFlow", dependencies: ["FoldCore"],
                          resources: [.copy("Shaders.metal")]),
        .testTarget(name: "FoldCoreTests", dependencies: ["FoldCore"])
    ]
)
