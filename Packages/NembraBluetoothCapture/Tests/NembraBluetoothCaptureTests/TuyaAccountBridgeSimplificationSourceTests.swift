import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture account bridge simplification")
struct TuyaAccountBridgeSimplificationSourceTests {
    @Test("account bridge stays domain and export only after the real Capture root moved")
    func obsoletePrototypeSurfaceIsAbsent() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("final class TuyaAccountBridge: ObservableObject"))
        #expect(bridge.contains("struct TuyaQRCodeExport: Transferable"))
        #expect(bridge.contains("struct TuyaMetadataExport: Transferable"))

        #expect(!bridge.contains("struct NembraCaptureRootView"))
        #expect(!bridge.contains("func captureCard()"))
        #expect(!bridge.contains("ES80OneTimeBluetoothDumpView"))
        #expect(!bridge.contains("We already proved this scooter uses Tuya FD50"))
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
