// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "P31nInsight",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "P31nInsight", targets: ["P31nInsight"]),
        .library(name: "P31nInsightCore", targets: ["P31nInsightCore"]),
    ],
    targets: [
        .target(
            name: "P31nInsightCore",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "P31nInsight",
            dependencies: ["P31nInsightCore"]
        ),
        .testTarget(
            name: "P31nInsightTests",
            dependencies: ["P31nInsightCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
