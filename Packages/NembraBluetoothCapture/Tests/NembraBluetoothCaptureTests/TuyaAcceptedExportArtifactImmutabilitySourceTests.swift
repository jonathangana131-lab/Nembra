import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted export artifact immutability")
struct TuyaAcceptedExportArtifactImmutabilitySourceTests {
    @Test("current-attempt acceptance cut freezes the complete export before another post-seal suspension")
    func cutFreezesWholeAcceptedEnvelopeBeforeAcceptedPhase() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let accepted = try section(
            in: String(watchdog),
            from: "self.acceptanceCutIsClosed = true",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed"
        )
        let body = String(accepted)

        guard let cutPrefix = body.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))"),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: cutPrefix.upperBound..<body.endIndex),
              let sourceRecheck = body.range(of: "guard self.buildIdentity.isAuthoritativeFieldBuild,", range: packageSeal.upperBound..<body.endIndex),
              let envelopeFreeze = body.range(of: "self.sealedAcceptedExport = self.makeExport(", range: sourceRecheck.upperBound..<body.endIndex),
              let acceptedPhase = body.range(of: "self.phase = .accepted", range: envelopeFreeze.upperBound..<body.endIndex) else {
            Issue.record("Accepted path must freeze the current-attempt cut, seal the package, re-check source authority, then freeze the complete export before accepted UI.")
            throw SourceContractError.sectionMissing
        }

        #expect(cutPrefix.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < sourceRecheck.lowerBound)
        #expect(sourceRecheck.lowerBound < envelopeFreeze.lowerBound)
        #expect(envelopeFreeze.lowerBound < acceptedPhase.lowerBound)
        #expect(body.contains("self.accountIdentityLeaseIsAuthorized"))
        #expect(body.contains("source_authority_changed_during_acceptance_seal"))
        #expect(body.contains("self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut"))
        #expect(body.contains("phase: .accepted"))
        #expect(body.contains("events: acceptedEventPrefixAtCut"))
        #expect(body.contains("self.exportData = nil"), Comment(rawValue: "Any diagnostic JSON prepared before acceptance must be retired before accepted Share is shown."))

        let afterSeal = body[packageSeal.upperBound..<envelopeFreeze.lowerBound]
        #expect(!afterSeal.contains("await "), Comment(rawValue: "No suspension may let mutable app authority drift between package seal and full accepted artifact freeze."))
    }

    @Test("accepted Prepare uses only the sealed envelope and not mutable post-seal authority")
    func acceptedPrepareUsesSealedEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let prepare = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )
        let body = String(prepare)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let sealedAcceptedExport else"))
        #expect(body.contains("envelope = sealedAcceptedExport"))
        #expect(body.contains("envelope = makeExport("))
        #expect(body.contains("phase: phase"))
        #expect(body.contains("events: events"))
    }

    @Test("mutable pre-terminal evidence retires any previously prepared diagnostic JSON")
    func mutableEvidenceInvalidatesPreparedExport() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let refresh = try function(in: app, startingAt: "private func refreshLedgerSnapshot()")
        let log = try function(in: app, startingAt: "private func log(")
        let invalidator = try function(in: app, startingAt: "private func invalidatePreparedMutableExport()")

        #expect(refresh.contains("invalidatePreparedMutableExport()"))
        #expect(log.contains("invalidatePreparedMutableExport()"))
        #expect(invalidator.contains("guard phase != .accepted else { return }"))
        #expect(invalidator.contains("exportData = nil"))
    }

    @Test("fresh correlation life clears every accepted export snapshot")
    func freshCorrelationClearsAcceptedArtifact() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(reset.contains("sealedAcceptedExport = nil"))
        #expect(reset.contains("exportData = nil"))
    }

    private func function(in source: String, startingAt marker: String) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source function missing: \(marker)")
            throw SourceContractError.sectionMissing
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[markerRange.lowerBound...index] }
            default: break
            }
            index = source.index(after: index)
        }

        Issue.record("Expected balanced source function body: \(marker)")
        throw SourceContractError.sectionMissing
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
