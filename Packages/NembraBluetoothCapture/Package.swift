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
        ),
        .executable(
            name: "nembra-es80-capture-report",
            targets: ["NembraES80CaptureReport"]
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
        .executableTarget(
            name: "NembraES80CaptureReport",
            dependencies: [
                "NembraBluetoothCapture",
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
