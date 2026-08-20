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
        .library(
            name: "NembraCaptureAppAuthorization",
            targets: ["NembraCaptureAppAuthorization"]
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
        .target(
            name: "NembraCaptureAppAuthorization",
            dependencies: ["NembraBluetoothCapture"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "NembraBluetoothCaptureTests",
            dependencies: [
                "NembraBluetoothCapture",
                .product(name: "NembraCore", package: "NembraCore")
            ]
        ),
        .testTarget(
            name: "NembraCaptureAppAuthorizationTests",
            dependencies: [
                "NembraCaptureAppAuthorization",
                "NembraBluetoothCapture"
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        )
    ]
)
