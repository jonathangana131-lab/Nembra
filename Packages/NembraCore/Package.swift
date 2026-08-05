// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NembraCore",
    products: [
        .library(name: "NembraCore", targets: ["NembraCore"])
    ],
    targets: [
        .target(name: "NembraCore"),
        .testTarget(name: "NembraCoreTests", dependencies: ["NembraCore"])
    ]
)
