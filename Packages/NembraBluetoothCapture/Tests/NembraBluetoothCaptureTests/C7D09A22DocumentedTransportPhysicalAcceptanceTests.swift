import Foundation
import XCTest
@testable import NembraBluetoothCapture

final class C7D09A22DocumentedTransportPhysicalAcceptanceTests: XCTestCase {
    private let generation: UInt64 = 7
    private let authenticatedAt: UInt64 = 10_000_000_000
    private let deviceID = "6815A5F5-4D1E-E004-BAE8-6DF924123907"

    func testQualifyingSameGenerationDocumentedTransportRemainsBelowPhysicalFirstAcceptance() throws {
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
            .blocked(reason: "Authenticated documented transport survived the rejection window; raw FD50 characteristic notify custody is still required for physical first acceptance.")
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

        var forgedJSON = try JSONSerialization.jsonObject(with: artifact.encodedJSON()) as! [String: Any]
        forgedJSON["kind"] = "forged-transport-kind"
        let forgedArtifact = try JSONDecoder().decode(
            C7D09A22DocumentedTransparentEvidenceArtifact.self,
            from: JSONSerialization.data(withJSONObject: forgedJSON, options: [.sortedKeys])
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

    func testPortableSummaryMetadataCannotMintPhysicalAcceptanceWithoutMatchingRetainedBytes() throws {
        let artifact = try qualifyingArtifact()
        var forgedJSON = try JSONSerialization.jsonObject(with: artifact.encodedJSON()) as! [String: Any]
        forgedJSON["payloadCount"] = 200
        forgedJSON["omittedPayloadCount"] = 198
        forgedJSON["latestPayloadAtUptimeNanoseconds"] = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
            + 9_000_000_000
        forgedJSON["hasPayloadStrictlyBeyondHistoricalRejectionHorizon"] = true

        var retained = try XCTUnwrap(forgedJSON["retainedPayloads"] as? [[String: Any]])
        retained[1]["receivedAtUptimeNanoseconds"] = authenticatedAt + 2_000_000_000
        retained[1]["elapsedSinceSDKConnectionNanoseconds"] = 2_000_000_001
        forgedJSON["retainedPayloads"] = retained

        let forgedArtifact = try JSONDecoder().decode(
            C7D09A22DocumentedTransparentEvidenceArtifact.self,
            from: JSONSerialization.data(withJSONObject: forgedJSON, options: [.sortedKeys])
        )
        let fieldAttempt = C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence(
            connectionGeneration: generation,
            milestone: .satisfied,
            artifact: forgedArtifact
        )

        XCTAssertNil(forgedArtifact.validatedReceiveEvidence(connectionGeneration: generation))
        XCTAssertFalse(fieldAttempt.satisfiesDocumentedAuthenticatedTransportAcceptance)
        XCTAssertEqual(
            C7D09A22DocumentedTransportPhysicalAcceptance.verdict(
                authenticatedPreflight: readyPreflight(),
                fieldAttempt: fieldAttempt
            ),
            .blocked(reason: "Documented transport artifact does not contain self-consistent retained receive bytes and chronology.")
        )
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

    func testBridgeNeverGrantsRawCustodyPhysicalAcceptanceSemanticsOrMutationAuthority() {
        XCTAssertFalse(C7D09A22DocumentedTransportPhysicalAcceptance.authorizesRawFD50CharacteristicCustody)
        XCTAssertFalse(C7D09A22DocumentedTransportPhysicalAcceptance.authorizesPhysicalFirstAcceptance)
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
        return C7D09A22DocumentedTransparentEvidenceArtifact(
            snapshot: ledger.snapshot,
            connectionGeneration: generation
        )
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
