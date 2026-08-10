import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted export envelope immutability")
struct TuyaAcceptedExportEnvelopeSealSourceTests {
    @Test("successful package seal freezes the full accepted envelope before another suspension point")
    func acceptanceSealFreezesExportEnvelopeSynchronously() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let seal = try section(
            in: String(watchdog),
            from: "try await sessionLedger.sealAcceptedObservation(for: token)",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed"
        )
        let body = String(seal)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let eventPrefix = body.range(of: "sealedAcceptedEventPrefix =", range: packageSeal.upperBound..<body.endIndex),
              let envelopeSnapshot = body.range(of: "sealedAcceptedExportSnapshot =", range: eventPrefix.upperBound..<body.endIndex) else {
            Issue.record("Successful package seal must synchronously freeze both the accepted event prefix and full accepted export envelope.")
            throw SourceContractError.sectionMissing
        }

        #expect(body[envelopeSnapshot.upperBound...].contains("makeExportSnapshot("))
        #expect(body[envelopeSnapshot.upperBound...].contains("phase: .accepted"))
        if let nextAwait = body.range(of: "await ", range: packageSeal.upperBound..<body.endIndex) {
            #expect(eventPrefix.lowerBound < nextAwait.lowerBound)
            #expect(envelopeSnapshot.lowerBound < nextAwait.lowerBound)
        }
    }

    @Test("accepted export uses only the sealed envelope except for share-time exportedAt")
    func acceptedExportUsesSealedEnvelopeSnapshot() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )
        let export = try section(
            in: String(controller),
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly()"
        )
        let body = String(export)

        #expect(controller.contains("private var sealedAcceptedExportSnapshot: Export?"))
        #expect(body.contains("guard var acceptedSnapshot = self.sealedAcceptedExportSnapshot"))
        #expect(body.contains("acceptedSnapshot.exportedAt = Date()"))
        #expect(body.contains("envelope = acceptedSnapshot"))
        #expect(body.contains("makeExportSnapshot("))
        #expect(body.contains("events: sealedAcceptedEventPrefix"))
    }

    @Test("post-seal SDK membership mutation cannot rewrite accepted authority metadata")
    func acceptedArtifactDoesNotDependOnLiveMembershipAfterSeal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let invalidation = try section(
            in: app,
            from: "func invalidateSDKMembership()",
            to: "func verifySDKMembership"
        )
        let export = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly()"
        )

        #expect(invalidation.contains("sdkDeviceMembershipVerified = false"))
        #expect(invalidation.contains("[.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase)"))
        #expect(export.contains("sealedAcceptedExportSnapshot"))
    }

    @Test("fresh correlation clears both accepted artifact snapshots")
    func freshCorrelationClearsAcceptedSnapshots() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(reset.contains("sealedAcceptedExportSnapshot = nil"))
    }

    @Test("only export time is mutable inside the sealed value snapshot")
    func exportSnapshotMutabilityIsNarrow() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let exportType = try section(
            in: app,
            from: "struct Export: Codable",
            to: "struct Event: Codable"
        )

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
