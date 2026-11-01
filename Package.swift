// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SonosCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SonosCore", targets: ["SonosCore"]),
        .library(name: "SonosDesign", targets: ["SonosDesign"]),
    ],
    targets: [
        .target(
            name: "SonosCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "SonosDesign",
            dependencies: ["SonosCore"]
        ),
        .testTarget(
            name: "SonosCoreTests",
            dependencies: ["SonosCore"]
        ),
    ]
)
