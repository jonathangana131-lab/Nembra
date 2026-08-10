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

        #expect(body.contains("CAPTURE COMPLETE"))
        #expect(body.contains("Ready for analysis"))
        #expect(body.contains("Label(\"Share Capture\""))
        let seal = try #require(app.range(of: "self.sealedAcceptedExport = self.makeExport("))
        let prepare = try #require(app.range(of: "self.prepareExport()", range: seal.upperBound..<app.endIndex))
        #expect(seal.lowerBound < prepare.lowerBound)
        #expect(body.contains("if let data = test.exportData"))
        #expect(body.contains("ShareLink(item: SecureTransfer(data: data, name: test.exportName)"))
        #expect(body.contains("Button(showEngineeringDetails ? \"Hide details\" : \"View details\")"))
        #expect(body.contains("accepted artifact is sealed"))
    }

    @Test("truth gates remain visible without promoting correlation heuristics into rider jargon")
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
        #expect(body.contains("No DP query or scooter command is authorized by this surface."))
        #expect(!body.contains("Historical UUID, name, RSSI, FD50, and Tuya hints never authorize the target."))
        #expect(app.contains("Do not guess from name, RSSI, FD50, or Tuya hints"))
        #expect(app.contains("Do not fall back to the historical capture UUID"))
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

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \\(start) ... \\(end)")
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