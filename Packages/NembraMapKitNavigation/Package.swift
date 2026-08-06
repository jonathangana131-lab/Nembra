// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NembraMapKitNavigation",
    products: [
        .library(name: "NembraMapKitNavigation", targets: ["NembraMapKitNavigation"])
    ],
    dependencies: [
        .package(path: "../NembraCore")
    ],
    targets: [
        .target(
            name: "NembraMapKitNavigation",
            dependencies: [
                .product(name: "NembraCore", package: "NembraCore")
            ]
        ),
        .testTarget(
            name: "NembraMapKitNavigationTests",
            dependencies: ["NembraMapKitNavigation"]
        )
    ]
)
