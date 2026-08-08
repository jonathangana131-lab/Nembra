import Foundation
import Testing
@testable import NembraCore

@Suite("Passive Bluetooth capture observation boundaries")
struct PassiveBluetoothCaptureObservationBoundaryTests {
    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("schema v3 round trips ready and quiet observation horizon boundaries")
    func roundTripsQuietObservationHorizon() throws {
        let readyUptime: UInt64 = 10_000_000_000
        let horizonUptime = readyUptime + 60_000_000_000
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_000)
        )

        try session.append(
            .captureBoundary(.init(kind: .finiteAcquisitionReady)),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: readyUptime,
            receivedAtDate: Date(timeIntervalSince1970: 5_001)
        )
        // Deliberately no Bluetooth callback record exists during this minute.
        // The horizon is Nembra observation-session evidence, not a synthetic
        // periodic BLE event inserted to make the timeline look longer.
        try session.append(
            .captureBoundary(.init(kind: .observationHorizon)),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: horizonUptime,
            receivedAtDate: Date(timeIntervalSince1970: 5_061)
        )

        let data = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 3)

        let decoded = try PassiveBluetoothCaptureJSON.decode(data)
        #expect(decoded == session)
        #expect(decoded.records.count == 2)
        #expect(
            decoded.records[1].receivedAtUptimeNanoseconds
                - decoded.records[0].receivedAtUptimeNanoseconds
                == 60_000_000_000
        )

        guard case let .captureBoundary(ready) = decoded.records[0].event,
              case let .captureBoundary(horizon) = decoded.records[1].event else {
            Issue.record("Expected two typed capture-boundary events")
            return
        }
        #expect(ready.kind == .finiteAcquisitionReady)
        #expect(horizon.kind == .observationHorizon)
    }

    @Test("capture boundaries never manufacture byte discontinuity")
    func captureBoundariesDoNotBreakByteContinuity() {
        #expect(
            !PassiveBluetoothCaptureEvent.captureBoundary(
                .init(kind: .finiteAcquisitionReady)
            ).breaksByteContinuity
        )
        #expect(
            !PassiveBluetoothCaptureEvent.captureBoundary(
                .init(kind: .observationHorizon)
            ).breaksByteContinuity
        )
    }

    @Test("schema v2 remains readable for pre-boundary capture evidence")
    func schemaV2RemainsReadable() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_100)
        )
        try session.append(
            .connection(
                try PassiveBluetoothConnectionObservation(
                    peripheralIdentifier: "observed-target",
                    state: .connected
                )
            ),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 5_101)
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        var json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"schemaVersion\":3"))
        json = json.replacingOccurrences(
            of: "\"schemaVersion\":3",
            with: "\"schemaVersion\":2"
        )

        #expect(try PassiveBluetoothCaptureJSON.decode(Data(json.utf8)) == session)
    }

    @Test("schema v2 cannot relabel schema v3 boundary evidence")
    func schemaV2RejectsCaptureBoundaryVocabulary() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_200)
        )
        try session.append(
            .captureBoundary(.init(kind: .observationHorizon)),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 5_201)
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        var json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"schemaVersion\":3"))
        json = json.replacingOccurrences(
            of: "\"schemaVersion\":3",
            with: "\"schemaVersion\":2"
        )

        #expect(
            throws: PassiveBluetoothCaptureValidationError.eventNotSupportedBySchemaVersion(2)
        ) {
            _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
        }
    }

    @Test("schema v1 cannot relabel schema v3 boundary evidence")
    func schemaV1RejectsCaptureBoundaryVocabulary() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_300)
        )
        try session.append(
            .captureBoundary(.init(kind: .finiteAcquisitionReady)),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 5_301)
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        var json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"schemaVersion\":3"))
        json = json.replacingOccurrences(
            of: "\"schemaVersion\":3",
            with: "\"schemaVersion\":1"
        )

        #expect(
            throws: PassiveBluetoothCaptureValidationError.eventNotSupportedBySchemaVersion(1)
        ) {
            _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
        }
    }

    @Test("capture boundary ordering remains governed by the immutable receipt clock")
    func boundaryStillRejectsReceiptRegression() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_400)
        )
        try session.append(
            .captureBoundary(.init(kind: .finiteAcquisitionReady)),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 5_401)
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.nonMonotonicReceiptTime) {
            try session.append(
                .captureBoundary(.init(kind: .observationHorizon)),
                sequenceNumber: 2,
                receivedAtUptimeNanoseconds: 99,
                receivedAtDate: Date(timeIntervalSince1970: 9_999)
            )
        }
    }
}
