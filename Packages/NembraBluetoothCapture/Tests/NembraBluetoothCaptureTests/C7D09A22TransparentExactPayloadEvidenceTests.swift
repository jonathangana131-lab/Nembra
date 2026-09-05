import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22TransparentExactPayloadEvidenceTests {
    @Test
    func retainsExactWholeCallbackBytesWithoutGrantingProtocolAuthority() throws {
        let startedAt: UInt64 = 1_000
        var ledger = try #require(TuyaSmartLifeTransparentReceiveObservationLedger(
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: startedAt
        ))
        let payload = Data([0xAA, 0x55, 0x00, 0x7F, 0xFF])
        let receipt = try #require(TuyaSmartLifeTransparentReceiveReceipt(
            payload: payload,
            callbackDeviceID: "demo",
            expectedDeviceID: "demo",
            receivedAtUptimeNanoseconds: startedAt + 10
        ))

        let recorded = ledger.record(receipt)
        #expect(recorded)
        let snapshot = ledger.snapshot
        #expect(snapshot.retainedPayloads.count == 1)
        #expect(snapshot.retainedPayloads[0].payload == payload)
        #expect(snapshot.retainedPayloads[0].hex == "aa55007fff")
        #expect(snapshot.retainedPayloads[0].receivedAtUptimeNanoseconds == startedAt + 10)
        #expect(snapshot.retainedPayloadByteCount == payload.count)
        #expect(snapshot.omittedPayloadCount == 0)
        #expect(!snapshot.retainedPayloads[0].authorizesRawFD50CharacteristicCustody)
        #expect(!snapshot.retainedPayloads[0].authorizesPhysicalFirstAcceptance)
        #expect(!snapshot.retainedPayloads[0].authorizesTelemetrySemantics)
        #expect(!snapshot.retainedPayloads[0].authorizesControlWrites)
        #expect(!snapshot.authorizesRawFD50CharacteristicCustody)
        #expect(!snapshot.authorizesPhysicalFirstAcceptance)
        #expect(!snapshot.authorizesStationaryMapping)
        #expect(!snapshot.authorizesTelemetrySemantics)
        #expect(!snapshot.authorizesControlWrites)
        #expect(!snapshot.authorizesPairingResetOrUnbind)
    }

    @Test
    func boundedEvidenceNeverTruncatesAnOversizedCallback() throws {
        let startedAt: UInt64 = 5_000
        var ledger = try #require(TuyaSmartLifeTransparentReceiveObservationLedger(
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: startedAt
        ))
        let oversized = Data(repeating: 0xAB, count: TuyaSmartLifeTransparentReceiveObservationLedger.maximumRetainedPayloadBytes + 1)
        let receipt = try #require(TuyaSmartLifeTransparentReceiveReceipt(
            payload: oversized,
            callbackDeviceID: "demo",
            expectedDeviceID: "demo",
            receivedAtUptimeNanoseconds: startedAt + 1
        ))

        let recorded = ledger.record(receipt)
        #expect(recorded)
        let snapshot = ledger.snapshot
        #expect(snapshot.payloadCount == 1)
        #expect(snapshot.totalByteCount == oversized.count)
        #expect(snapshot.retainedPayloads.isEmpty)
        #expect(snapshot.retainedPayloadByteCount == 0)
        #expect(snapshot.omittedPayloadCount == 1)
    }

    @Test
    func boundedEvidenceStopsAtPayloadCountWithoutChangingTransportCounts() throws {
        let startedAt: UInt64 = 10_000
        var ledger = try #require(TuyaSmartLifeTransparentReceiveObservationLedger(
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: startedAt
        ))

        let total = TuyaSmartLifeTransparentReceiveObservationLedger.maximumRetainedPayloadCount + 3
        for index in 0..<total {
            let receipt = try #require(TuyaSmartLifeTransparentReceiveReceipt(
                payload: Data([UInt8(index & 0xFF)]),
                callbackDeviceID: "demo",
                expectedDeviceID: "demo",
                receivedAtUptimeNanoseconds: startedAt + UInt64(index + 1)
            ))
            let recorded = ledger.record(receipt)
            #expect(recorded)
        }

        let snapshot = ledger.snapshot
        #expect(snapshot.payloadCount == total)
        #expect(snapshot.totalByteCount == total)
        #expect(snapshot.retainedPayloads.count == TuyaSmartLifeTransparentReceiveObservationLedger.maximumRetainedPayloadCount)
        #expect(snapshot.retainedPayloadByteCount == TuyaSmartLifeTransparentReceiveObservationLedger.maximumRetainedPayloadCount)
        #expect(snapshot.omittedPayloadCount == 3)
    }
}
