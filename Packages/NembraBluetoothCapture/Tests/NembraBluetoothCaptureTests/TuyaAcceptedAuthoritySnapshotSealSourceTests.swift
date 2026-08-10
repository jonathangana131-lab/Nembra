import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted export authority seal")
struct TuyaAcceptedAuthoritySnapshotSealSourceTests {
    @Test("canonical seal snapshots mutable app authority before the next suspension point")
    func canonicalSealFreezesMutableAuthoritySynchronously() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("sealedAcceptedAuthoritySnapshot"))

        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let frozenAuthority = body.range(of: "sealedAcceptedAuthoritySnapshot =", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Successful package seal must immediately freeze the app-owned authority used by accepted export.")
            throw SourceContractError.sectionMissing
        }

        if let nextAwait = body.range(of: "await ", range: packageSeal.upperBound..<body.endIndex) {
            #expect(frozenAuthority.lowerBound < nextAwait.lowerBound)
        }
    }

    @Test("accepted export authority cannot be recomputed from mutable post-seal controller state")
    func acceptedExportUsesFrozenAuthorityEvenAfterPresentationStateChanges() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )
        let body = String(export)

        #expect(body.contains("sealedAcceptedAuthoritySnapshot"))
        #expect(!body.contains("if phase == .accepted"))

        // These values are mutable after canonical acceptance (for example after SDK logout or
        // membership invalidation). An accepted-attempt envelope must project them from the frozen
        // acceptance snapshot rather than silently mixing current presentation state with sealed
        // historical application evidence.
        #expect(!body.contains("sdkAccountLoggedIn: sdkAccountLoggedIn"))
        #expect(!body.contains("sdkDeviceMembershipVerified: sdkDeviceMembershipVerified"))
        #expect(!body.contains("sdkLocalBLEOnline: sdkLocalBLEOnline"))
        #expect(!body.contains("phase: phase"))
        #expect(!body.contains("selectedPeripheralID: selectedID?.uuidString"))
        #expect(!body.contains("targetCorrelationProvenance: correlationProvenance"))
    }

    @Test("fresh correlation life clears every accepted export snapshot")
    func freshAttemptCannotReusePriorAuthoritySnapshot() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly",
            to: "private func failLocally"
        )

        #expect(reset.contains("sealedAcceptedAuthoritySnapshot = nil"))
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
