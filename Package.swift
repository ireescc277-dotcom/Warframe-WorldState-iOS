// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WarframeWatch",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "WarframeWatch",
            targets: ["WarframeWatch"]
        ),
    ],
    dependencies: [
        .package(path: "Packages/DamageKit")
    ],
    targets: [
        .target(
            name: "WarframeWatch",
            dependencies: [
                .product(name: "DamageKit", package: "DamageKit")
            ],
            path: "WarframeWatch",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
