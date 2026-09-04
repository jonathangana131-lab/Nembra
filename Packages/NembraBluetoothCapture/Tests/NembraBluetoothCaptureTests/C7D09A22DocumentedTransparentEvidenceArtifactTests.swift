import Foundation
import XCTest
@testable import NembraBluetoothCapture

final class C7D09A22DocumentedTransparentEvidenceArtifactTests: XCTestCase {
    func testArtifactPreservesExactWholePayloadsAndPostThirtySecondTransportEvidence() throws {
        let deviceID = "6815A5F5-4D1E-E004-BAE8-6DF924123907"
        let started: UInt64 = 10_000_000_000
        var ledger = try XCTUnwrap(TuyaSmartLifeTransparentReceiveObservationLedger(
            expectedDeviceID: deviceID,
            sdkConnectionStartedAtUptimeNanoseconds: started
        ))

        let first = try XCTUnwrap(TuyaSmartLifeTransparentReceiveReceipt(
            payload: Data([0xaa, 0x55, 0x00, 0x7f, 0xff]),
            callbackDeviceID: deviceID,
            expectedDeviceID: deviceID,
            receivedAtUptimeNanoseconds: started + 2_000_000_000
        ))
        let survived = try XCTUnwrap(TuyaSmartLifeTransparentReceiveReceipt(
            payload: Data([0x01, 0x02, 0xfe]),
            callbackDeviceID: deviceID,
            expectedDeviceID: deviceID,
            receivedAtUptimeNanoseconds: started + 30_000_000_001
        ))

        XCTAssertTrue(ledger.record(first))
        XCTAssertTrue(ledger.record(survived))

        let artifact = C7D09A22DocumentedTransparentEvidenceArtifact(snapshot: ledger.snapshot)
        XCTAssertEqual(artifact.kind, C7D09A22DocumentedTransparentEvidenceArtifact.evidenceKind)
        XCTAssertEqual(artifact.tuyaDeviceID, deviceID)
        XCTAssertEqual(artifact.payloadCount, 2)
        XCTAssertEqual(artifact.totalByteCount, 8)
        XCTAssertTrue(artifact.hasPayloadStrictlyBeyondHistoricalRejectionHorizon)
        XCTAssertEqual(artifact.retainedPayloads.map(\.sequence), [1, 2])
        XCTAssertEqual(artifact.retainedPayloads.map(\.hex), ["aa55007fff", "0102fe"])
        XCTAssertEqual(artifact.retainedPayloads.map(\.byteCount), [5, 3])
        XCTAssertEqual(artifact.retainedPayloads[0].elapsedSinceSDKConnectionNanoseconds, 2_000_000_000)
        XCTAssertEqual(artifact.retainedPayloads[1].elapsedSinceSDKConnectionNanoseconds, 30_000_000_001)
        XCTAssertEqual(artifact.retainedPayloadByteCount, 8)
        XCTAssertEqual(artifact.omittedPayloadCount, 0)

        XCTAssertFalse(artifact.authorizesRawFD50CharacteristicCustody)
        XCTAssertFalse(artifact.authorizesPhysicalFirstAcceptance)
        XCTAssertFalse(artifact.authorizesStationaryMapping)
        XCTAssertFalse(artifact.authorizesTelemetrySemantics)
        XCTAssertFalse(artifact.authorizesControlWrites)
        XCTAssertFalse(artifact.authorizesPairingResetOrUnbind)
    }

    func testArtifactJSONIsDeterministicAndDoesNotInventProtocolSemantics() throws {
        let deviceID = "demo"
        let started: UInt64 = 100
        var ledger = try XCTUnwrap(TuyaSmartLifeTransparentReceiveObservationLedger(
            expectedDeviceID: deviceID,
            sdkConnectionStartedAtUptimeNanoseconds: started
        ))
        let receipt = try XCTUnwrap(TuyaSmartLifeTransparentReceiveReceipt(
            payload: Data([0xde, 0xad, 0xbe, 0xef]),
            callbackDeviceID: deviceID,
            expectedDeviceID: deviceID,
            receivedAtUptimeNanoseconds: 200
        ))
        XCTAssertTrue(ledger.record(receipt))

        let artifact = C7D09A22DocumentedTransparentEvidenceArtifact(snapshot: ledger.snapshot)
        let first = try artifact.encodedJSON()
        let second = try artifact.encodedJSON()
        XCTAssertEqual(first, second)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, C7D09A22DocumentedTransparentEvidenceArtifact.evidenceKind)
        XCTAssertNil(object["speed"])
        XCTAssertNil(object["battery"])
        XCTAssertNil(object["mode"])
        XCTAssertNil(object["light"])
        XCTAssertNil(object["brake"])
        XCTAssertNil(object["power"])
    }
}
