import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture whole accepted export artifact immutability")
struct TuyaWholeAcceptedExportArtifactImmutabilitySourceTests {
    @Test("accepted Share uses one fully frozen envelope instead of rebuilding from live state")
    func acceptedShareCannotRebuildAcceptedEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedExport: Export?"))

        let prepare = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )
        let body = String(prepare)

        guard let acceptedBranch = body.range(of: "if phase == .accepted"),
              let sealedGuard = body.range(of: "guard let sealedAcceptedExport", range: acceptedBranch.upperBound..<body.endIndex),
              let sealedUse = body.range(of: "envelope = sealedAcceptedExport", range: sealedGuard.upperBound..<body.endIndex),
              let diagnosticBranch = body.range(of: "else", range: sealedUse.upperBound..<body.endIndex) else {
            Issue.record("prepareExport must separate accepted immutable export from mutable diagnostic export")
            throw SourceContractError.sectionMissing
        }

        let acceptedBody = body[acceptedBranch.lowerBound..<diagnosticBranch.lowerBound]
        #expect(!acceptedBody.contains("Date()"))
        #expect(!acceptedBody.contains("buildIdentity."))
        #expect(!acceptedBody.contains("sdkAccountLoggedIn"))
        #expect(!acceptedBody.contains("sdkDeviceMembershipVerified"))
        #expect(!acceptedBody.contains("sdkLocalBLEOnline"))
        #expect(!acceptedBody.contains("ledgerSnapshot"))
        #expect(!acceptedBody.contains("candidates"))
    }

    @Test("whole accepted envelope is captured at the quiescent cut and published immediately after package seal")
    func canonicalSealPublishesPrecomputedWholeEnvelopeWithoutSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let ready = try section(
            in: String(watchdog),
            from: "case .readyForStationaryMapping:",
            to: "case .blocked:"
        )
        let body = String(ready)

        guard let eventCut = body.range(of: "let acceptedEventPrefixAtCut ="),
              let envelopeCut = body.range(of: "let acceptedEnvelopeAtCut = self.makeExport(", range: eventCut.upperBound..<body.endIndex),
              let acceptedPhaseLiteral = body.range(of: "phase: .accepted", range: envelopeCut.upperBound..<body.endIndex),
              let acceptedEvents = body.range(of: "events: acceptedEventPrefixAtCut", range: acceptedPhaseLiteral.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: acceptedEvents.upperBound..<body.endIndex),
              let publishEnvelope = body.range(of: "self.sealedAcceptedExport = acceptedEnvelopeAtCut", range: packageSeal.upperBound..<body.endIndex),
              let acceptedPhase = body.range(of: "self.phase = .accepted", range: publishEnvelope.upperBound..<body.endIndex) else {
            Issue.record("Canonical seal must capture the complete accepted envelope at the quiescent cut and publish that exact value immediately after package seal succeeds.")
            throw SourceContractError.sectionMissing
        }

        let afterSealBeforePublish = body[packageSeal.upperBound..<publishEnvelope.lowerBound]
        #expect(!afterSealBeforePublish.contains("await "))
        #expect(publishEnvelope.lowerBound < acceptedPhase.lowerBound)
    }

    @Test("accepted envelope construction is centralized and diagnostic export may remain live")
    func acceptedAndDiagnosticExportsShareOneConstructorWithoutSharingAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(
            in: app,
            from: "private func makeExport(",
            to: "func prepareExport()"
        )
        let prepare = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )

        #expect(helper.contains("phase: Phase"))
        #expect(helper.contains("events: [Event]"))
        #expect(helper.contains("Export("))
        #expect(prepare.contains("makeExport(phase: phase, events: events)"))
    }

    @Test("fresh attempt clears the prior whole accepted artifact")
    func freshAttemptClearsWholeAcceptedArtifact() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(reset.contains("sealedAcceptedExport = nil"))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
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
