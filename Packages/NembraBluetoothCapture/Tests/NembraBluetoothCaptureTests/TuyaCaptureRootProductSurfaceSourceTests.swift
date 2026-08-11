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

        #expect(body.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(body.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(body.contains("NEMBRA CAPTURE"))
        #expect(body.contains("Set up Capture"))
        #expect(body.contains("Prepare the scooter link"))
        #expect(body.contains("Bluetooth stays off until account and device checks are complete."))
        #expect(body.contains("Nembra verifies the account and device again before any passive Bluetooth correlation begins."))
        #expect(!body.contains("One guided setup establishes the account and bound-device context Nembra will use before passive target correlation begins."))
        #expect(!body.contains("proves the account and scooter"))
        #expect(body.contains("Engineering details"))
        #expect(!body.contains("P0 · TUYA AUTHENTICATION"))
        #expect(!body.contains("Prove the secure scooter link first."))
        #expect(!body.contains("Read-only control boundary"))
        #expect(!body.contains("local_key"))
        #expect(!body.contains("No DP query"))
        #expect(!body.contains(".card()"))
    }

    @Test("Accessibility layout keeps account action ahead of verbose provider status")
    func accessibilityLayoutPrioritizesPrimaryAction() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let account = String(
            try section(
                in: app,
                from: "private var accountSection: some View",
                to: "private var statusText: some View"
            )
        )

        #expect(account.contains("if !isAccessibilityLayout"))
        #expect(account.contains("TextField(\"Tuya Smart User Code\""))
        #expect(account.contains("tuya.requestApproval()"))
        #expect(account.contains("Label(\"Create approval QR\", systemImage: \"qrcode\")"))
        #expect(account.contains("frame(maxWidth: .infinity, minHeight: 50)"))
        #expect(account.contains("Bluetooth remains off."))
        #expect(account.contains("if isAccessibilityLayout"))

        let actionRange = try #require(account.range(of: "tuya.requestApproval()"))
        let accessibilityStatusRange = try #require(
            account.range(
                of: "if isAccessibilityLayout {\n                        statusText",
                range: actionRange.upperBound..<account.endIndex
            )
        )
        #expect(actionRange.lowerBound < accessibilityStatusRange.lowerBound)
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
        #expect(body.contains("if isAccessibilityLayout"))
        #expect(body.contains("scooterSelectionButton(for: device)"))
        #expect(body.contains("continueButton(for: device)"))
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
        #expect(!bridge.contains("ES80OneTimeBluetoothDumpView()"))
        #expect(!bridge.contains("We already proved this scooter uses Tuya FD50."))
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
