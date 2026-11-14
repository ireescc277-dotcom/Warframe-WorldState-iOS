// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DamageKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "DamageKit", targets: ["DamageKit"]),
        .executable(name: "damagekit-cli", targets: ["damagekit-cli"])
    ],
    targets: [
        .target(
            name: "DamageKit",
            resources: [
                .copy("Resources/mods.json"),
                .copy("Resources/conditional-effects.json"),
                .copy("Resources/stance-combo-order.json"),
                .copy("Resources/default-melee-stances.json")
            ]
        ),
        .executableTarget(
            name: "damagekit-cli",
            dependencies: ["DamageKit"]
        ),
        .testTarget(
            name: "DamageKitTests",
            dependencies: ["DamageKit"]
        )
    ]
)
