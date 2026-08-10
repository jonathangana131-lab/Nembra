import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture legacy root retirement")
struct TuyaCaptureLegacyRootRetirementSourceTests {
    @Test("standalone app entry owns the only Capture product root")
    func legacyTuyaPrototypeIsRetired() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(entrypoint.contains("WindowGroup { CaptureP0Root().preferredColorScheme(.dark) }"))
        #expect(!entrypoint.contains("NembraCaptureRootView()"))
        #expect(!bridge.contains("struct NembraCaptureRootView: View"))
        #expect(!bridge.contains("func captureCard() -> some View"))
        #expect(!bridge.contains("Continue to Bluetooth Capture"))
        #expect(!bridge.contains("ES80OneTimeBluetoothDumpView()"))
    }

    @Test("retirement preserves the live account bridge consumed by CaptureP0Root")
    func liveAccountBridgeRemainsOwnedByCurrentRoot() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(entrypoint.contains("@StateObject private var tuya = TuyaAccountBridge()"))
        #expect(entrypoint.contains("tuya.requestApproval()"))
        #expect(entrypoint.contains("tuya.selectDevice(device)"))
        #expect(bridge.contains("final class TuyaAccountBridge: ObservableObject"))
        #expect(bridge.contains("struct TuyaQRCodeExport: Transferable"))
        #expect(bridge.contains("struct TuyaMetadataExport: Transferable"))
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
