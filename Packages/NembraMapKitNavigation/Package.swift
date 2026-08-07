// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NembraMapKitNavigation",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "NembraMapKitNavigation", targets: ["NembraMapKitNavigation"]),
        .library(name: "NembraMapKitNavigationSimulation", targets: ["NembraMapKitNavigationSimulation"]),
    ],
    dependencies: [
        .package(path: "../NembraCore")
    ],
    targets: [
        .target(
            name: "NembraMapKitNavigation",
            dependencies: [.product(name: "NembraCore", package: "NembraCore")]
        ),
        .target(
            name: "NembraMapKitNavigationSimulation",
            dependencies: [
                "NembraMapKitNavigation",
                .product(name: "NembraCore", package: "NembraCore"),
            ]
        ),
        .testTarget(
            name: "NembraMapKitNavigationTests",
            dependencies: ["NembraMapKitNavigation"]
        ),
        .testTarget(
            name: "NembraMapKitNavigationSimulationTests",
            dependencies: ["NembraMapKitNavigationSimulation"]
        ),
    ]
)
