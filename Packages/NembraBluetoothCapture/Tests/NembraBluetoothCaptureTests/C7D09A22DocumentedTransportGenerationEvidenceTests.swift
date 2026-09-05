import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransportGenerationEvidenceTests {
    @Test
    @MainActor
    func coherentFieldEvidenceIsBoundToExactAuthenticatedGeneration() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )

        let blocked = await preflight.fieldAttemptEvidence()
        #expect(blocked.connectionGeneration == nil)
        #expect(blocked.milestone == .blockedUnauthenticated)
        #expect(!blocked.satisfiesDocumentedAuthenticatedTransportAcceptance)

        let first = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: first)
        try await ledger.markAuthenticated(for: first, method: .smartLifeAppSDK)
        let firstAuthenticated = await ledger.currentPreflightSnapshot()

        #expect(await preflight.arm(
            connectionToken: first,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: firstAuthenticated
        ))

        let firstEvidence = await preflight.fieldAttemptEvidence()
        #expect(firstEvidence.connectionGeneration == first.diagnosticGeneration)
        #expect(firstEvidence.artifact?.tuyaDeviceID == "demo")
        #expect(!firstEvidence.satisfiesDocumentedAuthenticatedTransportAcceptance)

        #expect(await preflight.retire(connectionToken: first))
        let retired = await preflight.fieldAttemptEvidence()
        #expect(retired.connectionGeneration == nil)
        #expect(retired.artifact == nil)
        #expect(retired.milestone == .blockedUnauthenticated)

        let second = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: second)
        try await ledger.markAuthenticated(for: second, method: .smartLifeAppSDK)
        let secondAuthenticated = await ledger.currentPreflightSnapshot()

        #expect(await preflight.arm(
            connectionToken: second,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: secondAuthenticated
        ))

        let secondEvidence = await preflight.fieldAttemptEvidence()
        #expect(secondEvidence.connectionGeneration == second.diagnosticGeneration)
        #expect(secondEvidence.connectionGeneration != first.diagnosticGeneration)

        // A stale terminal callback cannot erase evidence custody for the newer generation.
        #expect(!(await preflight.retire(connectionToken: first)))
        let afterStaleRetire = await preflight.fieldAttemptEvidence()
        #expect(afterStaleRetire.connectionGeneration == second.diagnosticGeneration)
        #expect(afterStaleRetire.artifact?.tuyaDeviceID == "demo")

        #expect(!afterStaleRetire.authorizesRawFD50CharacteristicCustody)
        #expect(!afterStaleRetire.authorizesPhysicalFirstAcceptance)
        #expect(!afterStaleRetire.authorizesStationaryMapping)
        #expect(!afterStaleRetire.authorizesTelemetrySemantics)
        #expect(!afterStaleRetire.authorizesControlWrites)
        #expect(!afterStaleRetire.authorizesPairingResetOrUnbind)
    }
}
