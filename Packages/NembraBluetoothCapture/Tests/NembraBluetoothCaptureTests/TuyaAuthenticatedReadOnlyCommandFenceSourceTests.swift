import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only command fence")
struct TuyaAuthenticatedReadOnlyCommandFenceSourceTests {
    @Test("authenticated preflight contains no scooter command, reset, unbind, DP query, or raw GATT write API")
    func authenticatedPreflightRemainsObservationOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let forbiddenFragments = [
            ".writeValue(",
            "writeValue(",
            "publishDps",
            "publishDps(",
            "getDps",
            "getDps(",
            "queryDps",
            "queryDps(",
            "resetFactory",
            "resetFactory(",
            "removeDevice",
            "removeDevice(",
            "unbindDevice",
            "unbindDevice(",
            "removeFromHome",
            "removeFromHome("
        ]

        for fragment in forbiddenFragments {
            #expect(
                !source.contains(fragment),
                "Authenticated Capture must remain read-only; forbidden API fragment found: \(fragment)"
            )
        }

        #expect(source.contains("connectBLE"))
        #expect(source.contains("dpsUpdate"))
        #expect(source.contains("sdkLocalBLEOnline"))
        #expect(source.contains("applicationUpdateCount"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
