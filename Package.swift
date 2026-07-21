// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Convey",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ConveyCore", targets: ["ConveyCore"]),
        .executable(name: "convey", targets: ["convey"]),
    ],
    targets: [
        .target(
            name: "ConveyCore",
            resources: [.copy("Resources/web")]
        ),
        .executableTarget(
            name: "convey",
            dependencies: ["ConveyCore"]
        ),
        .testTarget(
            name: "ConveyCoreTests",
            dependencies: ["ConveyCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
