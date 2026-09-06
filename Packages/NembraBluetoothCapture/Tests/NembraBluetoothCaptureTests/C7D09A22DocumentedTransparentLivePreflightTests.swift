import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentLivePreflightTests {
    private func authenticatedContext() async throws -> (
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        token: TuyaReadOnlyConnectionToken,
        snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return (ledger, token, await ledger.currentPreflightSnapshot())
    }

    @MainActor
    private func waitForPayloadCount(
        _ expectedCount: Int,
        in preflight: C7D09A22DocumentedTransparentLivePreflight
    ) async throws -> C7D09A22DocumentedTransparentEvidenceArtifact {
        for _ in 0..<100 {
            if let artifact = await preflight.evidenceArtifact(),
               artifact.payloadCount == expectedCount {
                return artifact
            }
            await Task.yield()
        }
        return try #require(await preflight.evidenceArtifact())
    }

    @Test
    @MainActor
    func livePreflightArmsOnlyAuthenticatedGenerationAndRetiresFailClosed() async throws {
        let context = try await authenticatedContext()
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await context.ledger.currentPreflightSnapshot() }
        )

        #expect(await preflight.transportMilestone() == .blockedUnauthenticated)
        #expect(await preflight.evidenceArtifact() == nil)
        #expect(await preflight.arm(
            connectionToken: context.token,
            expectedDeviceID: " demo ",
            authenticatedPreflightSnapshot: context.snapshot
        ))
        #expect(preflight.hasActiveAuthenticatedGeneration)
        #expect(preflight.activeDiagnosticGeneration == context.token.diagnosticGeneration)
        #expect(await preflight.transportMilestone() == .waitingForFirstPayload)

        let emptyArtifact = try #require(await preflight.evidenceArtifact())
        #expect(emptyArtifact.tuyaDeviceID == "demo")
        #expect(emptyArtifact.payloadCount == 0)
        #expect(emptyArtifact.retainedPayloads.isEmpty)
        #expect(!emptyArtifact.authorizesPhysicalFirstAcceptance)

        preflight.receive(payload: Data([0x01, 0x02]), callbackDeviceID: "demo")
        let artifact = try await waitForPayloadCount(1, in: preflight)
        #expect(await preflight.transportMilestone() == .waitingForHistoricalRejectionWindow)

        #expect(artifact.tuyaDeviceID == "demo")
        #expect(artifact.payloadCount == 1)
        #expect(artifact.totalByteCount == 2)
        #expect(artifact.retainedPayloads.map(\.hex) == ["0102"])
        #expect(!artifact.authorizesRawFD50CharacteristicCustody)
        #expect(!artifact.authorizesPhysicalFirstAcceptance)
        #expect(!artifact.authorizesStationaryMapping)
        #expect(!artifact.authorizesTelemetrySemantics)
        #expect(!artifact.authorizesControlWrites)
        #expect(!artifact.authorizesPairingResetOrUnbind)

        #expect(!preflight.authorizesRawFD50CharacteristicCustody)
        #expect(!preflight.authorizesPhysicalFirstAcceptance)
        #expect(!preflight.authorizesStationaryMapping)
        #expect(!preflight.authorizesTelemetrySemantics)
        #expect(!preflight.authorizesControlWrites)
        #expect(!preflight.authorizesPairingResetOrUnbind)

        #expect(await preflight.retire(connectionToken: context.token))
        #expect(!preflight.hasActiveAuthenticatedGeneration)
        #expect(preflight.activeDiagnosticGeneration == nil)
        #expect(await preflight.diagnosticSnapshot() == nil)
        #expect(await preflight.evidenceArtifact() == nil)
        #expect(await preflight.transportMilestone() == .blockedUnauthenticated)
    }

    @Test
    @MainActor
    func objectiveCCallbackShapeRejectsNilEmptyAndWrongDeviceBeforeRecording() async throws {
        let context = try await authenticatedContext()
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await context.ledger.currentPreflightSnapshot() }
        )
        #expect(await preflight.arm(
            connectionToken: context.token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: context.snapshot
        ))

        preflight.receiveDocumentedSmartLifeCallback(payload: nil, deviceID: "demo")
        preflight.receiveDocumentedSmartLifeCallback(payload: Data(), deviceID: "demo")
        preflight.receiveDocumentedSmartLifeCallback(payload: Data([0xaa]), deviceID: nil)
        preflight.receiveDocumentedSmartLifeCallback(payload: Data([0xbb]), deviceID: "   ")
        preflight.receiveDocumentedSmartLifeCallback(payload: Data([0xcc]), deviceID: "other-device")
        await Task.yield()

        let empty = try #require(await preflight.evidenceArtifact())
        #expect(empty.payloadCount == 0)
        #expect(empty.totalByteCount == 0)
        #expect(empty.retainedPayloads.isEmpty)

        preflight.receiveDocumentedSmartLifeCallback(payload: Data([0xaa, 0x55]), deviceID: " demo ")
        let admitted = try await waitForPayloadCount(1, in: preflight)
        #expect(admitted.payloadCount == 1)
        #expect(admitted.totalByteCount == 2)
        #expect(admitted.retainedPayloads.map(\.hex) == ["aa55"])
        #expect(!admitted.authorizesRawFD50CharacteristicCustody)
        #expect(!admitted.authorizesPhysicalFirstAcceptance)
        #expect(!admitted.authorizesTelemetrySemantics)
        #expect(!admitted.authorizesControlWrites)
        #expect(!admitted.authorizesPairingResetOrUnbind)
    }

    @Test
    @MainActor
    func staleTerminalCannotRetireNewerAuthenticatedGeneration() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let first = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: first)
        try await ledger.markAuthenticated(for: first, method: .smartLifeAppSDK)
        let firstSnapshot = await ledger.currentPreflightSnapshot()

        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )
        #expect(await preflight.arm(
            connectionToken: first,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: firstSnapshot
        ))

        try await ledger.endConnection(for: first)
        let second = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: second)
        try await ledger.markAuthenticated(for: second, method: .smartLifeAppSDK)
        let secondSnapshot = await ledger.currentPreflightSnapshot()
        #expect(second.diagnosticGeneration > first.diagnosticGeneration)
        #expect(await preflight.arm(
            connectionToken: second,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: secondSnapshot
        ))

        #expect(!(await preflight.retire(connectionToken: first)))
        #expect(preflight.hasActiveAuthenticatedGeneration)
        #expect(preflight.activeDiagnosticGeneration == second.diagnosticGeneration)
        #expect(await preflight.transportMilestone() == .waitingForFirstPayload)

        #expect(await preflight.retire(connectionToken: second))
        #expect(!preflight.hasActiveAuthenticatedGeneration)
    }

    @Test
    @MainActor
    func unauthenticatedSnapshotCannotArmLivePreflight() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        let snapshot = await ledger.currentPreflightSnapshot()
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )

        #expect(!(await preflight.arm(
            connectionToken: token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: snapshot
        )))
        #expect(!preflight.hasActiveAuthenticatedGeneration)
        #expect(preflight.activeDiagnosticGeneration == nil)
        #expect(await preflight.evidenceArtifact() == nil)
        #expect(await preflight.transportMilestone() == .blockedUnauthenticated)
    }
}
