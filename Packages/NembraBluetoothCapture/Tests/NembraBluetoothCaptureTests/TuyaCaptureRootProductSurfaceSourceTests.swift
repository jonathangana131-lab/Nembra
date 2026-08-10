import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root product surface")
struct TuyaCaptureRootProductSurfaceSourceTests {
    @Test("public unprovisioned launch is guided Capture preflight, not an engineering console")
    func publicRootIsGuidedPreflight() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        )
        let body = String(root)

        #expect(body.contains("NEMBRA CAPTURE"))
        #expect(body.contains("One guided setup establishes the account and bound-device context Nembra will use before passive target correlation begins."))
        #expect(!body.contains("proves the account and scooter"))
        #expect(body.contains("Engineering details"))
        #expect(!body.contains("P0 · TUYA AUTHENTICATION"))
        #expect(!body.contains("Prove the secure scooter link first."))
        #expect(!body.contains("Read-only control boundary"))
        #expect(!body.contains("local_key"))
        #expect(!body.contains("No DP query"))
        #expect(!body.contains(".card()"))
    }

    @Test("premium root preserves the real account and device authority path")
    func accountAndDeviceAuthorityRemainReachable() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        )
        let body = String(root)

        #expect(body.contains("tuya.requestApproval()"))
        #expect(body.contains("tuya.checkApprovalNow()"))
        #expect(body.contains("tuya.refreshDevices()"))
        #expect(body.contains("tuya.selectDevice(device)"))
        #expect(body.contains("SecureLinkView(device: device)"))
        #expect(app.contains("No DP query or scooter command is authorized by this surface."))
    }

    @Test("legacy card-based Capture root is retired from the metadata bridge")
    func legacyCardRootIsRetired() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("final class TuyaAccountBridge: ObservableObject"))
        #expect(bridge.contains("struct TuyaQRCodeExport: Transferable"))
        #expect(bridge.contains("struct TuyaMetadataExport: Transferable"))
        #expect(!bridge.contains("struct NembraCaptureRootView: View"))
        #expect(!bridge.contains("func captureCard() -> some View"))
        #expect(!bridge.contains("Link Tuya first"))
        #expect(!bridge.contains("Continue to Bluetooth Capture"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
