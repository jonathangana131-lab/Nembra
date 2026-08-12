import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Secure Link product recovery truth")
struct TuyaSecureLinkProductRecoveryTruthSourceTests {
    @Test("failed product state only offers OFF1 retry after the exact session generation is retired")
    func failureRecoveryIsCapabilityDriven() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController: NSObject, ObservableObject",
            to: "private protocol OfficialTuyaDriver"
        )
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )

        let controllerBody = String(controller)
        let surfaceBody = String(surface)

        #expect(controllerBody.contains("var failedAttemptCanRestartFromOFF1: Bool"))
        #expect(controllerBody.contains("phase == .failed"))
        #expect(controllerBody.contains("currentConnectionToken == nil"))
        #expect(controllerBody.contains("var canRestartFromFreshOFF1: Bool { failedAttemptCanRestartFromOFF1 }"))
        #expect(surfaceBody.contains("test.canRestartFromFreshOFF1"))
        #expect(surfaceBody.contains("Restart from scooter OFF"))
        #expect(surfaceBody.contains("Relaunch Capture"))
    }

    @Test("analysis readiness is earned by a shareable sealed artifact, not accepted phase alone")
    func acceptedPhaseDoesNotOverclaimAnalysisReadiness() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let completion = try section(
            in: app,
            from: "private var completionPanel: some View",
            to: "private var sdkAuthorizationPanel: some View"
        )
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )

        let completionBody = String(completion)
        let surfaceBody = String(surface)

        guard let shareableBranch = completionBody.range(of: "if let data = test.exportData"),
              let readyForAnalysis = completionBody.range(of: "Ready for analysis") else {
            Issue.record("Completion must contain an explicit shareable-artifact branch and analysis-ready copy.")
            throw SourceContractError.requiredSourceMissing
        }

        #expect(readyForAnalysis.lowerBound > shareableBranch.lowerBound)
        #expect(completionBody.contains("test.message"))
        #expect(completionBody.localizedCaseInsensitiveContains("retry"))
        #expect(!completionBody.contains(".task { test.prepareExport() }"))
        #expect(!surfaceBody.contains("read-only evidence is sealed and ready to share for analysis."))
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
        case requiredSourceMissing
    }
}
