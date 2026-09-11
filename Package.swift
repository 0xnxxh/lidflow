// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LidFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LidFlow", targets: ["LidFlow"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.3")
    ],
    targets: [
        .target(name: "FoldCore"),
        .executableTarget(name: "LidFlow", dependencies: ["FoldCore", .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.copy("Shaders.metal")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "FoldCoreTests", dependencies: ["FoldCore"])
    ]
)
