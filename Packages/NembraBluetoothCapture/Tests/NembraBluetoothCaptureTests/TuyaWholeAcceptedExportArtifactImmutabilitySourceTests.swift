import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture whole accepted export artifact immutability")
struct TuyaWholeAcceptedExportArtifactImmutabilitySourceTests {
    @Test("accepted Share must use one fully frozen envelope instead of rebuilding from live state")
    func acceptedShareCannotRebuildAcceptedEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedExport: Export?"))

        let prepare = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )
        let body = String(prepare)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let sealedAcceptedExport"))
        #expect(body.contains("envelope = sealedAcceptedExport"))

        guard let acceptedBranch = body.range(of: "if phase == .accepted"),
              let mutableBranch = body.range(of: "else", range: acceptedBranch.upperBound..<body.endIndex) else {
            Issue.record("prepareExport must separate accepted immutable export from mutable diagnostic export")
            throw SourceContractError.sectionMissing
        }
        let acceptedBody = body[acceptedBranch.lowerBound..<mutableBranch.lowerBound]
        #expect(!acceptedBody.contains("Date()"))
        #expect(!acceptedBody.contains("buildIdentity."))
        #expect(!acceptedBody.contains("sdkAccountLoggedIn"))
        #expect(!acceptedBody.contains("sdkDeviceMembershipVerified"))
        #expect(!acceptedBody.contains("sdkLocalBLEOnline"))
        #expect(!acceptedBody.contains("ledgerSnapshot"))
        #expect(!acceptedBody.contains("candidates"))
    }

    @Test("whole accepted envelope must freeze after package seal and before accepted UI")
    func canonicalSealFreezesWholeEnvelopeBeforeAcceptedPhase() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let envelopeFreeze = body.range(of: "self.sealedAcceptedExport = self.makeExport(", range: packageSeal.upperBound..<body.endIndex),
              let acceptedPhase = body.range(of: "self.phase = .accepted", range: envelopeFreeze.upperBound..<body.endIndex) else {
            Issue.record("Successful package seal must freeze the complete accepted Export before presenting accepted UI")
            throw SourceContractError.sectionMissing
        }

        #expect(packageSeal.lowerBound < envelopeFreeze.lowerBound)
        #expect(envelopeFreeze.lowerBound < acceptedPhase.lowerBound)

        let between = body[packageSeal.upperBound..<envelopeFreeze.lowerBound]
        #expect(!between.contains("await "), Comment(rawValue: "Mutable authority must not suspend between package seal and complete accepted-envelope freeze."))
        #expect(body.contains("phase: .accepted"))
        #expect(body.contains("events: acceptedEventPrefixAtCut"))
    }

    @Test("fresh attempt clears the prior whole accepted artifact")
    func freshAttemptClearsWholeAcceptedArtifact() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(
            in: app,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries"
        )
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(start.contains("sealedAcceptedExport = nil") || reset.contains("sealedAcceptedExport = nil"))
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
