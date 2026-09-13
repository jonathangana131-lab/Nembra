import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentAcceptedEvidenceTests {
    private let linkedIdentity = C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
        deviceID: "demo",
        uuid: "6815A5F5-4D1E-E004-BAE8-6DF924123907",
        productID: "fd50-product"
    )!

    @Test
    @MainActor
    func acceptanceScopedExportStaysNilBeforeTransportAcceptance() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let authenticated = await ledger.currentPreflightSnapshot()

        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await ledger.currentPreflightSnapshot() }
        )
        #expect(await preflight.arm(
            connectionToken: token,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: authenticated
        ))

        // Exact documented callback bytes are useful diagnostic evidence immediately, but they
        // must not become an acceptance-scoped portable artifact before the independently observed
        // authenticated session and repeated receive stream survive the post-auth rejection window.
        preflight.receiveDocumentedSmartLifeCallback(
            payload: Data([0xc7, 0xd0, 0x9a, 0x22]),
            deviceID: "demo"
        )
        await Task.yield()

        #expect(await preflight.evidenceArtifact() != nil)
        #expect(await preflight.acceptedDocumentedTransportEvidenceArtifact() == nil)
        #expect(await preflight.acceptedDocumentedTransportProofArtifact(linkedDeviceIdentity: linkedIdentity) == nil)

        let cut = await preflight.fieldAttemptEvidence()
        #expect(!cut.satisfiesDocumentedAuthenticatedTransportAcceptance)
        #expect(C7D09A22DocumentedTransportAcceptanceProof(
            fieldAttempt: cut,
            linkedDeviceIdentity: linkedIdentity
        ) == nil)
        #expect(!cut.authorizesRawFD50CharacteristicCustody)
        #expect(!cut.authorizesTelemetrySemantics)
        #expect(!cut.authorizesControlWrites)
        #expect(!cut.authorizesPairingResetOrUnbind)
    }

    @Test
    @MainActor
    func acceptanceFenceDistinguishesIndependentTokensWithSameDiagnosticGeneration() async throws {
        let firstLedger = TuyaAuthenticatedReadOnlySessionLedger()
        let firstToken = try await firstLedger.beginConnection()
        try await firstLedger.markAuthenticationStarted(for: firstToken)
        try await firstLedger.markAuthenticated(for: firstToken, method: .smartLifeAppSDK)
        let firstSnapshot = await firstLedger.currentPreflightSnapshot()

        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger()
        let secondToken = try await secondLedger.beginConnection()
        try await secondLedger.markAuthenticationStarted(for: secondToken)
        try await secondLedger.markAuthenticated(for: secondToken, method: .smartLifeAppSDK)
        let secondSnapshot = await secondLedger.currentPreflightSnapshot()

        // Independent package ledgers can both legitimately call their first connection generation 1.
        // Generation equality must therefore never be the reconnect/export authority fence.
        #expect(firstToken.diagnosticGeneration == secondToken.diagnosticGeneration)
        #expect(firstToken != secondToken)

        var activeLedger = firstLedger
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { await activeLedger.currentPreflightSnapshot() }
        )
        #expect(await preflight.arm(
            connectionToken: firstToken,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: firstSnapshot
        ))
        let firstFenceToken = try #require(preflight.activeConnectionTokenForAcceptanceFence)
        #expect(preflight.activeDiagnosticGeneration == firstToken.diagnosticGeneration)
        #expect(firstFenceToken == firstToken)

        activeLedger = secondLedger
        #expect(await preflight.arm(
            connectionToken: secondToken,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: secondSnapshot
        ))

        // The presentation/debug generation did not change, but exact connection authority did.
        // Acceptance export must fence on this token rather than on the shared number.
        #expect(preflight.activeDiagnosticGeneration == firstToken.diagnosticGeneration)
        #expect(preflight.activeConnectionTokenForAcceptanceFence == secondToken)
        #expect(preflight.activeConnectionTokenForAcceptanceFence != firstFenceToken)
        #expect(!preflight.authorizesRawFD50CharacteristicCustody)
        #expect(!preflight.authorizesTelemetrySemantics)
        #expect(!preflight.authorizesControlWrites)
        #expect(!preflight.authorizesPairingResetOrUnbind)
    }

    @Test
    @MainActor
    func satisfiedTransportProofRejectsDifferentLinkedScooterIdentity() throws {
        let generation: UInt64 = 7
        let postHorizon = TuyaSmartLifeTransparentReceiveObservationLedger.c7d09a22HistoricalRejectionNanoseconds + 1
        let snapshot = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 0,
            payloadCount: 2,
            totalByteCount: 5,
            latestPayloadAtUptimeNanoseconds: postHorizon,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0xc7]), receivedAtUptimeNanoseconds: 1),
                .init(payload: Data([0xd0, 0x9a, 0x22, 0x01]), receivedAtUptimeNanoseconds: postHorizon)
            ],
            retainedPayloadByteCount: 5,
            omittedPayloadCount: 0
        )
        let artifact = C7D09A22DocumentedTransparentEvidenceArtifact(
            snapshot: snapshot,
            connectionGeneration: generation
        )
        let cut = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: artifact
        )

        let exact = try #require(C7D09A22DocumentedTransportAcceptanceProof(
            fieldAttempt: cut,
            linkedDeviceIdentity: linkedIdentity
        ))
        #expect(exact.linkedDeviceIdentity.deviceID == "demo")
        #expect(exact.linkedDeviceIdentity.uuid == "6815A5F5-4D1E-E004-BAE8-6DF924123907")
        #expect(exact.evidence.tuyaDeviceID == exact.linkedDeviceIdentity.deviceID)
        #expect(exact.embeddedReceiveEvidenceIsSelfConsistent)
        #expect(!exact.authorizesRawFD50CharacteristicCustody)
        #expect(!exact.authorizesTelemetrySemantics)
        #expect(!exact.authorizesControlWrites)
        #expect(!exact.authorizesPairingResetOrUnbind)

        let differentLinkedScooter = try #require(
            C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
                deviceID: "other-linked-tuya-device",
                uuid: "00000000-0000-0000-0000-000000000001",
                productID: "fd50-product"
            )
        )
        #expect(C7D09A22DocumentedTransportAcceptanceProof(
            fieldAttempt: cut,
            linkedDeviceIdentity: differentLinkedScooter
        ) == nil)
    }
}
