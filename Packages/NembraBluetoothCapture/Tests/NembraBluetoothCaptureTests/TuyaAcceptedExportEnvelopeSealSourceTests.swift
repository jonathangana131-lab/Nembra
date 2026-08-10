import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted export envelope immutability")
struct TuyaAcceptedExportEnvelopeSealSourceTests {
    @Test("the quiescent acceptance cut freezes a candidate envelope before the package seal")
    func acceptanceCutFreezesCandidateEnvelopeBeforeSeal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = String(watchdog)

        guard let closeCut = body.range(of: "self.acceptanceCutIsClosed = true"),
              let eventCut = body.range(of: "let acceptedEventPrefixAtCut = self.events", range: closeCut.upperBound..<body.endIndex),
              let envelopeCut = body.range(of: "let acceptedExportSnapshotAtCut = self.makeExportSnapshot(", range: eventCut.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: envelopeCut.upperBound..<body.endIndex),
              let sourceRecheck = body.range(of: "guard self.acceptanceSourceAuthorityIsStillAuthorized", range: packageSeal.upperBound..<body.endIndex),
              let publishPrefix = body.range(of: "self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut", range: sourceRecheck.upperBound..<body.endIndex),
              let publishEnvelope = body.range(of: "self.sealedAcceptedExportSnapshot = acceptedExportSnapshotAtCut", range: publishPrefix.upperBound..<body.endIndex) else {
            Issue.record("Acceptance must freeze one candidate envelope at the quiescent cut, package-seal it, recheck source authority, then publish that exact frozen envelope.")
            throw SourceContractError.sectionMissing
        }

        #expect(closeCut.lowerBound < eventCut.lowerBound)
        #expect(eventCut.lowerBound < envelopeCut.lowerBound)
        #expect(envelopeCut.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < sourceRecheck.lowerBound)
        #expect(sourceRecheck.lowerBound < publishPrefix.lowerBound)
        #expect(publishPrefix.lowerBound < publishEnvelope.lowerBound)
    }

    @Test("source authority is rechecked after the package seal suspension before UI acceptance")
    func packageSealCannotPromoteAChangedSDKLease() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: app, from: "private final class SecureLinkController", to: "private protocol OfficialTuyaDriver")

        #expect(controller.contains("private var acceptanceSourceAuthorityIsStillAuthorized: Bool"))
        #expect(controller.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(controller.contains("sdkAccountLoggedIn"))
        #expect(controller.contains("sdkDeviceMembershipVerified"))
        #expect(controller.contains("accountIdentityLeaseIsAuthorized"))
        #expect(controller.contains("source_authority_changed_during_acceptance_seal"))
    }

    @Test("accepted export serializes the sealed envelope and mutates only share time")
    func acceptedExportUsesSealedEnvelopeSnapshot() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: app, from: "private final class SecureLinkController", to: "private protocol OfficialTuyaDriver")
        let export = try section(in: String(controller), from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)

        #expect(controller.contains("private var sealedAcceptedExportSnapshot: Export?"))
        #expect(body.contains("guard var acceptedSnapshot = self.sealedAcceptedExportSnapshot"))
        #expect(body.contains("acceptedSnapshot.exportedAt = Date()"))
        #expect(body.contains("envelope = acceptedSnapshot"))
        #expect(body.contains("makeExportSnapshot("))
        #expect(body.contains("events: sealedAcceptedEventPrefix"))
    }

    @Test("post-seal SDK logout cannot rewrite accepted authority metadata")
    func acceptedArtifactDoesNotDependOnLiveMembershipAfterSeal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let invalidation = try section(in: app, from: "func invalidateSDKMembership()", to: "func verifySDKMembership")
        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")

        #expect(invalidation.contains("sdkDeviceMembershipVerified = false"))
        #expect(!invalidation.contains(".accepted"))
        #expect(export.contains("sealedAcceptedExportSnapshot"))
    }

    @Test("fresh correlation clears both accepted artifact snapshots")
    func freshCorrelationClearsAcceptedSnapshots() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")

        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(reset.contains("sealedAcceptedExportSnapshot = nil"))
    }

    @Test("only export time is mutable inside the sealed value snapshot")
    func exportSnapshotMutabilityIsNarrow() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let exportType = try section(in: app, from: "struct Export: Codable", to: "struct Event: Codable")

        #expect(exportType.contains("var exportedAt: Date"))
        #expect(!exportType.contains("var sdkAccountLoggedIn:"))
        #expect(!exportType.contains("var sdkDeviceMembershipVerified:"))
        #expect(!exportType.contains("var selectedPeripheralID:"))
        #expect(!exportType.contains("var events:"))
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
