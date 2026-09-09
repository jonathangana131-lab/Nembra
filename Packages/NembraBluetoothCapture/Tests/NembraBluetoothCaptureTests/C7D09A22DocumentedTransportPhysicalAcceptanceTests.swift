import Foundation
import XCTest
@testable import NembraBluetoothCapture

final class C7D09A22DocumentedTransportPhysicalAcceptanceTests: XCTestCase {
    private let generation: UInt64 = 7
    private let authenticatedAt: UInt64 = 10_000_000_000
    private let deviceID = "6815A5F5-4D1E-E004-BAE8-6DF924123907"

    func testQualifyingSameGenerationDocumentedTransportReachesCanonicalPhysicalAcceptanceGate() throws {
        let artifact = try qualifyingArtifact()
        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: artifact
        )

        XCTAssertEqual(
            C7D09A22DocumentedTransportPhysicalAcceptance.verdict(
                authenticatedPreflight: readyPreflight(),
                fieldAttempt: fieldAttempt
            ),
            .readyForPhysicalFirstAcceptance
        )
    }

    func testFieldAttemptConvenienceAcceptanceRejectsZeroGenerationAndForgedArtifactKind() throws {
        let artifact = try qualifyingArtifact()
        let zeroGeneration = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: 0,
            milestone: .satisfied,
            artifact: artifact
        )
        XCTAssertFalse(zeroGeneration.satisfiesDocumentedAuthenticatedTransportAcceptance)

        let forgedArtifact = C7D09A22DocumentedTransparentEvidenceArtifact(
            kind: "forged-transport-kind",
            tuyaDeviceID: artifact.tuyaDeviceID,
            sdkConnectionStartedAtUptimeNanoseconds: artifact.sdkConnectionStartedAtUptimeNanoseconds,
            payloadCount: artifact.payloadCount,
            totalByteCount: artifact.totalByteCount,
            latestPayloadAtUptimeNanoseconds: artifact.latestPayloadAtUptimeNanoseconds,
            hasPayloadStrictlyBeyondHistoricalRejectionHorizon: artifact.hasPayloadStrictlyBeyondHistoricalRejectionHorizon,
            retainedPayloads: artifact.retainedPayloads,
            retainedPayloadByteCount: artifact.retainedPayloadByteCount,
            omittedPayloadCount: artifact.omittedPayloadCount
        )
        let forged = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: forgedArtifact
        )
        XCTAssertFalse(forged.satisfiesDocumentedAuthenticatedTransportAcceptance)

        let valid = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: artifact
        )
        XCTAssertTrue(valid.satisfiesDocumentedAuthenticatedTransportAcceptance)
    }

    func testStaleGenerationFailsClosedBeforeEvidenceCanBePromoted() throws {
        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation - 1,
            milestone: .satisfied,
            artifact: try qualifyingArtifact()
        )

        XCTAssertEqual(
            C7D09A22DocumentedTransportPhysicalAcceptance.verdict(
                authenticatedPreflight: readyPreflight(),
                fieldAttempt: fieldAttempt
            ),
            .blocked(reason: "Documented transport evidence does not belong to the current authenticated connection generation.")
        )
    }

    func testDifferentSDKConnectionInstanceFailsClosedEvenWhenGenerationMatches() throws {
        var ledger = try XCTUnwrap(TuyaSmartLifeTransparentReceiveObservationLedger(
            expectedDeviceID: deviceID,
            sdkConnectionStartedAtUptimeNanoseconds: authenticatedAt - 2
        ))
        let early = try XCTUnwrap(TuyaSmartLifeTransparentReceiveReceipt(
            payload: Data([0x01]),
            callbackDeviceID: deviceID,
            expectedDeviceID: deviceID,
            receivedAtUptimeNanoseconds: authenticatedAt + 1_000_000_000
        ))
        let survived = try XCTUnwrap(TuyaSmartLifeTransparentReceiveReceipt(
            payload: Data([0x02]),
            callbackDeviceID: deviceID,
            expectedDeviceID: deviceID,
            receivedAtUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1
        ))
        XCTAssertTrue(ledger.record(early))
        XCTAssertTrue(ledger.record(survived))

        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: C7D09A22DocumentedTransparentEvidenceArtifact(snapshot: ledger.snapshot)
        )

        XCTAssertEqual(
            C7D09A22DocumentedTransportPhysicalAcceptance.verdict(
                authenticatedPreflight: readyPreflight(),
                fieldAttempt: fieldAttempt
            ),
            .blocked(reason: "Documented transport artifact does not belong to the exact authenticated SDK connection instance.")
        )
    }

    func testUnsatisfiedMilestoneCannotBypassCanonicalReceiveRequirement() {
        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .waitingForFirstPayload,
            artifact: nil
        )

        XCTAssertEqual(
            C7D09A22DocumentedTransportPhysicalAcceptance.verdict(
                authenticatedPreflight: readyPreflight(),
                fieldAttempt: fieldAttempt
            ),
            .blocked(reason: "Documented authenticated device-to-app receive evidence is required.")
        )
    }

    func testBridgeNeverGrantsRawCustodySemanticsOrMutationAuthority() {
        XCTAssertFalse(C7D09A22DocumentedTransportPhysicalAcceptance.authorizesRawFD50CharacteristicCustody)
        XCTAssertFalse(C7D09A22DocumentedTransportPhysicalAcceptance.authorizesStationaryMapping)
        XCTAssertFalse(C7D09A22DocumentedTransportPhysicalAcceptance.authorizesTelemetrySemantics)
        XCTAssertFalse(C7D09A22DocumentedTransportPhysicalAcceptance.authorizesControlWrites)
        XCTAssertFalse(C7D09A22DocumentedTransportPhysicalAcceptance.authorizesPairingResetOrUnbind)
    }

    private func qualifyingArtifact() throws -> C7D09A22DocumentedTransparentEvidenceArtifact {
        var ledger = try XCTUnwrap(TuyaSmartLifeTransparentReceiveObservationLedger(
            expectedDeviceID: deviceID,
            sdkConnectionStartedAtUptimeNanoseconds: authenticatedAt - 1
        ))
        let early = try XCTUnwrap(TuyaSmartLifeTransparentReceiveReceipt(
            payload: Data([0x01]),
            callbackDeviceID: deviceID,
            expectedDeviceID: deviceID,
            receivedAtUptimeNanoseconds: authenticatedAt + 1_000_000_000
        ))
        let survived = try XCTUnwrap(TuyaSmartLifeTransparentReceiveReceipt(
            payload: Data([0x02]),
            callbackDeviceID: deviceID,
            expectedDeviceID: deviceID,
            receivedAtUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1
        ))
        XCTAssertTrue(ledger.record(early))
        XCTAssertTrue(ledger.record(survived))
        return C7D09A22DocumentedTransparentEvidenceArtifact(snapshot: ledger.snapshot)
    }

    private func readyPreflight() -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: authenticatedAt - 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
                + 1,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1,
            connectionGeneration: generation
        )
    }
}
