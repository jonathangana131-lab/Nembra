// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NembraCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "NembraCore", targets: ["NembraCore"])
    ],
    targets: [
        .target(name: "NembraCore"),
        .testTarget(name: "NembraCoreTests", dependencies: ["NembraCore"])
    ]
)
