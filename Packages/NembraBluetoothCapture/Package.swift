// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NembraBluetoothCapture",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NembraBluetoothCapture",
            targets: ["NembraBluetoothCapture"]
        )
    ],
    dependencies: [
        .package(path: "../NembraCore")
    ],
    targets: [
        .target(
            name: "NembraBluetoothCapture",
            dependencies: [
                .product(name: "NembraCore", package: "NembraCore")
            ]
        ),
        .testTarget(
            name: "NembraBluetoothCaptureTests",
            dependencies: [
                "NembraBluetoothCapture",
                .product(name: "NembraCore", package: "NembraCore")
            ]
        )
    ]
)
