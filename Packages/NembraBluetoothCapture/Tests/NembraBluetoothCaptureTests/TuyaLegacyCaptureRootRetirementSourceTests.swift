import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture legacy root retirement")
struct TuyaLegacyCaptureRootRetirementSourceTests {
    @Test("metadata bridge cannot retain the superseded Capture product root")
    func legacyRootIsRetired() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(!bridge.contains("struct NembraCaptureRootView: View"))
        #expect(!bridge.contains("func captureCard() -> some View"))
        #expect(!bridge.contains("ES80OneTimeBluetoothDumpView()"))
        #expect(!bridge.contains("We already proved this scooter uses Tuya FD50."))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}