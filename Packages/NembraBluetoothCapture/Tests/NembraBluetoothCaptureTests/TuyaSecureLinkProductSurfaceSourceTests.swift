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

    @Test("accepted experience prepares the sealed artifact and makes Share Capture primary")
    func acceptedExperienceIsCaptureCompleteShareFlow() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)
        let seal = String(try section(
            in: app,
            from: "self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut",
            to: "self.log(\"acceptance_sealed\""
        ))

        #expect(body.contains("CAPTURE COMPLETE"))
        #expect(body.contains("Ready for analysis"))
        #expect(body.contains("Label(\"Share Capture\""))
        #expect(seal.contains("self.sealedAcceptedExport = self.makeExport("))
        #expect(seal.contains("phase: .accepted"))
        #expect(seal.contains("self.exportData = nil"))
        #expect(seal.contains("self.phase = .accepted"))
        #expect(seal.contains("self.prepareExport()"))
        #expect(body.contains("Button(showEngineeringDetails ? \"Hide details\" : \"View details\")"))
        #expect(body.contains("accepted artifact is sealed"))
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
        #expect(body.contains("test.applicationUpdateCount >= TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount"))
        #expect(body.contains("test.applicationEvidenceSurvivedHistoricalWindow"))
        #expect(!body.contains("test.applicationUpdateCount > 0"))
        #expect(body.contains("Text(test.message)"))
        #expect(app.contains("Correlation is current-session evidence, not permanent scooter identity."))
        #expect(app.contains("Do not guess from name, RSSI, FD50, or Tuya hints; restart from OFF1 after reducing nearby-device ambiguity."))
        #expect(body.contains("No DP query or scooter command is authorized by this surface."))
    }

    @Test("capture-stopped receipt failures use rider-facing scooter language")
    func captureStoppedReceiptFailuresAvoidEngineeringJargon() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receipt = String(try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))
        let surface = String(try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        ))

        #expect(surface.contains("Text(test.message)"))
        #expect(receipt.contains("mirrorAlreadyTerminalIncompleteObservationHorizon("))
        #expect(!receipt.contains("message: \"Application receipt"))
        #expect(!receipt.contains("package-owned"))
        #expect(receipt.contains("Scooter data did not become sufficient within 60 seconds."))
    }

    @Test("large Dynamic Type receives a recomposed stage indicator")
    func accessibilityStageRailRecomposes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(body.contains(#"Step \(currentStageIndex + 1) of 4"#))
        #expect(body.contains("accessibilityHint"))
        #expect(body.contains("accessibilityLabel"))
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
