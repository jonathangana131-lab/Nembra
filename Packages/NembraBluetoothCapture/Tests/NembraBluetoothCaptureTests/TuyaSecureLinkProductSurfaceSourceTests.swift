import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Secure Link product surface")
struct TuyaSecureLinkProductSurfaceSourceTests {
    @Test("primary flow is a guided premium instrument rather than an engineering card stack")
    func guidedPrimaryFlowHidesEngineeringJargon() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("NEMBRA CAPTURE"))
        #expect(body.contains("stageLabels = [\"Target\", \"Secure link\", \"Observe\", \"Seal\"]"))
        #expect(body.contains("private var engineeringDisclosure"))
        #expect(body.contains("Label(\"Engineering details\""))
        #expect(body.contains("Connection generation"))
        #expect(!body.contains("Canonical acceptance"))
        #expect(!body.contains("Prepare sanitized diagnostic JSON"))
        #expect(!body.contains("Share diagnostic JSON"))
        #expect(body.contains("navigationTitle(\"Capture\")"))
        #expect(body.contains(".inputSurface()"))
        #expect(app.contains("func inputSurface() -> some View"))
        #expect(!app.contains("func card() -> some View"))
    }

    @Test("accepted experience prepares the immutable sealed artifact before Share Capture becomes primary")
    func acceptedExperienceIsCaptureCompleteShareFlow() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)
        let controller = String(try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))

        #expect(body.contains("CAPTURE COMPLETE"))
        #expect(body.contains("Ready for analysis"))
        #expect(body.contains("Label(\"Share Capture\""))
        #expect(body.contains("Button(showEngineeringDetails ? \"Hide details\" : \"View details\")"))
        #expect(body.contains("accepted artifact is sealed"))

        #expect(controller.contains("self.sealedAcceptedExport = self.makeExport("))
        #expect(controller.contains("phase: .accepted"))
        #expect(controller.contains("self.exportData = nil"))
        #expect(controller.contains("self.phase = .accepted"))
        #expect(controller.contains("self.prepareExport()"))
        #expect(appearsInOrder(
            [
                "self.sealedAcceptedExport = self.makeExport(",
                "self.exportData = nil",
                "self.phase = .accepted",
                "self.prepareExport()"
            ],
            in: controller
        ))
    }

    @Test("truth gates remain visible in the guided product surface")
    func truthGatesRemainProductVisible() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("test.fieldBuildIsAuthoritative"))
        #expect(body.contains("test.accountIdentityLeaseIsAuthorized"))
        #expect(body.contains("test.correlationWindowIsScanning"))
        #expect(body.contains("test.confirmCorrelatedTarget()"))
        #expect(body.contains("test.authenticate()"))
        #expect(body.contains("test.sdkLocalBLEOnline"))
        #expect(body.contains("test.applicationUpdateCount > 0"))
        #expect(body.contains("Only the full OFF → ON → OFF → ON pattern can authorize the nearby signal for this attempt."))
        #expect(body.contains("Nembra can now open the secure Tuya link. Capture stays read-only and cannot send scooter commands."))
        #expect(body.contains("Application values are sanitized SDK-level projections, not raw FD50 bytes. No DP query or scooter command is authorized by this surface."))
    }

    @Test("large Dynamic Type receives a recomposed stage indicator")
    func accessibilityStageRailRecomposes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(body.contains("Step \\(currentStageIndex + 1) of 4"))
        #expect(body.contains("accessibilityHint"))
        #expect(body.contains("accessibilityLabel"))
    }

    private func appearsInOrder(_ needles: [String], in source: String) -> Bool {
        var cursor = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: cursor..<source.endIndex) else { return false }
            cursor = range.upperBound
        }
        return true
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
