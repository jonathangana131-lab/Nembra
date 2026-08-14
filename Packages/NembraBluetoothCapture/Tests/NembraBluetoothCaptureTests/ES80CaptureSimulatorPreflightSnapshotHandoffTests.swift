import Foundation
import Testing

@Suite("ES80 Capture Simulator preflight authority boundary")
struct ES80CaptureSimulatorPreflightSnapshotHandoffTests {
    private static func captureEntrypointSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    @Test("authenticated field entrypoint admits no synthetic Simulator preflight authority")
    func fieldEntrypointRejectsSyntheticSnapshotAuthority() throws {
        let source = try Self.captureEntrypointSource()

        #expect(!source.contains("PassiveBluetoothExperimentOneSimulatorQAFixture"))
        #expect(!source.contains("simulatorQASnapshot"))
        #expect(!source.contains("simulatorQAEvidenceLabel"))
        #expect(!source.contains("targetEnvironment(simulator)"))
    }

    @Test("field correlation is minted by fresh package-owned power-cycle observations")
    func correlationRequiresFreshPackageOwnedObservationAuthority() throws {
        let source = try Self.captureEntrypointSource()

        #expect(source.contains("correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(source.contains("try session.startCurrentWindow()"))
        #expect(source.contains("let final = try session.finishCurrentWindow()"))
        #expect(source.contains("correlationProvenance = CorrelationProvenance(result: result)"))
        #expect(source.contains("candidate.freshlyCorrelated"))
        #expect(source.contains("targetCorrelationOperatorConfirmed = true"))
    }

    @Test("canonical acceptance comes from package-owned authenticated receipts and an immutable seal")
    func acceptedCaptureCannotBeMintedFromSyntheticSnapshotState() throws {
        let source = try Self.captureEntrypointSource()

        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: ledgerSnapshot)"))

        // Simulator fixture state must never substitute for the real callback edge. Application
        // occurrence/chronology is admitted synchronously by the exact ledger, then the async
        // receiver consumes that opaque receipt without re-supplying an `isNonEmpty` truth bit.
        #expect(source.contains("self.sessionLedger.captureApplicationDelivery("))
        #expect(source.contains("receipt: applicationReceipt"))
        #expect(source.contains("try await sessionLedger.recordApplicationUpdate("))
        #expect(source.contains("receipt: receipt"))
        #expect(!source.contains("recordApplicationUpdate(isNonEmpty:"))

        // Watchdog liveness uses the same package-owned receipt authority rather than actor-entry
        // time, while immutable acceptance remains downstream of the canonical package seal.
        #expect(source.contains("captureLivenessReceipt(for: token)"))
        #expect(source.contains("self.sessionLedger.observeCurrentConnection("))
        #expect(source.contains("receipt: livenessReceipt"))
        #expect(!source.contains("sessionLedger.observeCurrentConnection(for: token)"))
        #expect(source.contains("try await sessionLedger.sealAcceptedObservation(for: token)"))
        #expect(source.contains("self.sealedAcceptedExport = self.makeExport("))
        #expect(source.contains("self.phase = .accepted"))
        #expect(!source.contains("simulatorQASnapshot"))
    }
}