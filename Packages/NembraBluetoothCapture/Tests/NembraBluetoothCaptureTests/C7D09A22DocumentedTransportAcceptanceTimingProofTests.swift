import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransportAcceptanceTimingProofTests {
    private let linkedIdentity = C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
        deviceID: "demo",
        uuid: "6815A5F5-4D1E-E004-BAE8-6DF924123907",
        productID: "fd50-product"
    )!

    @Test
    @MainActor
    func acceptedTimingProofPreservesIndependentPostAuthenticationLivenessCut() throws {
        let generation: UInt64 = 9
        let connectionStarted: UInt64 = 1_000_000_000
        let authenticatedAt: UInt64 = 5_000_000_000
        let firstPayload: UInt64 = 6_000_000_000
        let postAuthPayload = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1
        let independentLiveness = postAuthPayload + 2_000_000_000

        let snapshot = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: connectionStarted,
            payloadCount: 2,
            totalByteCount: 5,
            latestPayloadAtUptimeNanoseconds: postAuthPayload,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0xc7]), receivedAtUptimeNanoseconds: firstPayload),
                .init(payload: Data([0xd0, 0x9a, 0x22, 0x01]), receivedAtUptimeNanoseconds: postAuthPayload)
            ],
            retainedPayloadByteCount: 5,
            omittedPayloadCount: 0
        )
        let artifact = C7D09A22DocumentedTransparentEvidenceArtifact(
            snapshot: snapshot,
            connectionGeneration: generation
        )
        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: artifact
        )
        let liveness = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: connectionStarted,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: independentLiveness,
            applicationPayloadCount: 0,
            connectionGeneration: generation,
            hasActiveCallbackAuthority: true
        )

        let proof = try #require(C7D09A22DocumentedTransportAcceptanceTimingProof(
            fieldAttempt: fieldAttempt,
            linkedDeviceIdentity: linkedIdentity,
            livenessSnapshot: liveness
        ))

        #expect(proof.authenticatedAtUptimeNanoseconds == authenticatedAt)
        #expect(proof.latestRetainedDocumentedReceiveAtUptimeNanoseconds == postAuthPayload)
        #expect(proof.independentLivenessObservedAtUptimeNanoseconds == independentLiveness)
        #expect(proof.postAuthenticationReceiveSurvivalNanoseconds == postAuthPayload - authenticatedAt)
        #expect(proof.postAuthenticationLivenessSurvivalNanoseconds == independentLiveness - authenticatedAt)
        #expect(proof.embeddedTimingAndReceiveEvidenceIsSelfConsistent)
        #expect(!proof.authorizesRawFD50CharacteristicCustody)
        #expect(!proof.authorizesTelemetrySemantics)
        #expect(!proof.authorizesControlWrites)
        #expect(!proof.authorizesPairingResetOrUnbind)
    }

    @Test
    @MainActor
    func timingProofRejectsLivenessExactlyAtHistoricalPostAuthenticationBoundary() {
        let generation: UInt64 = 10
        let connectionStarted: UInt64 = 0
        let authenticatedAt: UInt64 = 1_000_000_000
        let horizon = TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        let postBoundaryPayload = authenticatedAt + horizon + 1

        let snapshot = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: connectionStarted,
            payloadCount: 2,
            totalByteCount: 2,
            latestPayloadAtUptimeNanoseconds: postBoundaryPayload,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0x01]), receivedAtUptimeNanoseconds: 1),
                .init(payload: Data([0x02]), receivedAtUptimeNanoseconds: postBoundaryPayload)
            ],
            retainedPayloadByteCount: 2,
            omittedPayloadCount: 0
        )
        let artifact = C7D09A22DocumentedTransparentEvidenceArtifact(
            snapshot: snapshot,
            connectionGeneration: generation
        )
        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: artifact
        )
        let liveness = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: connectionStarted,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + horizon,
            applicationPayloadCount: 0,
            connectionGeneration: generation,
            hasActiveCallbackAuthority: true
        )

        #expect(C7D09A22DocumentedTransportAcceptanceTimingProof(
            fieldAttempt: fieldAttempt,
            linkedDeviceIdentity: linkedIdentity,
            livenessSnapshot: liveness
        ) == nil)
    }

    @Test
    @MainActor
    func timingProofRejectsConnectionChronologyFromAnotherSession() {
        let generation: UInt64 = 11
        let connectionStarted: UInt64 = 2_000_000_000
        let authenticatedAt: UInt64 = 3_000_000_000
        let postHorizon = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1

        let snapshot = TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot(
            tuyaDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: connectionStarted,
            payloadCount: 2,
            totalByteCount: 2,
            latestPayloadAtUptimeNanoseconds: postHorizon,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: true,
            retainedPayloads: [
                .init(payload: Data([0x01]), receivedAtUptimeNanoseconds: authenticatedAt + 1),
                .init(payload: Data([0x02]), receivedAtUptimeNanoseconds: postHorizon)
            ],
            retainedPayloadByteCount: 2,
            omittedPayloadCount: 0
        )
        let artifact = C7D09A22DocumentedTransparentEvidenceArtifact(
            snapshot: snapshot,
            connectionGeneration: generation
        )
        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: artifact
        )
        let foreignChronology = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: connectionStarted + 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: postHorizon,
            applicationPayloadCount: 0,
            connectionGeneration: generation,
            hasActiveCallbackAuthority: true
        )

        #expect(C7D09A22DocumentedTransportAcceptanceTimingProof(
            fieldAttempt: fieldAttempt,
            linkedDeviceIdentity: linkedIdentity,
            livenessSnapshot: foreignChronology
        ) == nil)
    }
}
