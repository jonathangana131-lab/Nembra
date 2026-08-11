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

    private func interruptionRecord(
        sequenceNumber: UInt64,
        uptime: UInt64,
        date: Date
    ) throws -> PassiveBluetoothCaptureRecord {
        PassiveBluetoothCaptureRecord(
            sequenceNumber: sequenceNumber,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: date,
            event: .interruption(
                try PassiveBluetoothCaptureInterruption(reason: "test evidence")
            )
        )
    }

    @Test("schema v3 round trips a quiet 60-second observation interval")
    func roundTripsQuietObservationHorizon() throws {
        let readyUptime: UInt64 = 10_000_000_000
        let horizonUptime = readyUptime + 60_000_000_000
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_000)
        )
        try session.append(
            interruptionRecord(
                sequenceNumber: 1,
                uptime: readyUptime - 1,
                date: Date(timeIntervalSince1970: 5_000.5)
            )
        )
        try session.appendObservationBoundary(
            PassiveBluetoothObservationBoundary(
                kind: .finiteAcquisitionReady,
                recordSequenceWatermark: 1,
                observedAtUptimeNanoseconds: readyUptime,
                observedAtDate: Date(timeIntervalSince1970: 5_001)
            )
        )
        // Deliberately no Bluetooth record exists during this minute. The
        // horizon is Nembra observation-session evidence beside the raw stream,
        // not a synthetic periodic BLE callback inserted to lengthen it.
        try session.appendObservationBoundary(
            PassiveBluetoothObservationBoundary(
                kind: .observationHorizon,
                recordSequenceWatermark: 1,
                observedAtUptimeNanoseconds: horizonUptime,
                observedAtDate: Date(timeIntervalSince1970: 5_061)
            )
        )

        let data = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 3)

        let decoded = try PassiveBluetoothCaptureJSON.decode(data)
        #expect(decoded == session)
        #expect(decoded.records.count == 1)
        #expect(decoded.observationBoundaries.count == 2)
        #expect(
            decoded.observationBoundaries[1].observedAtUptimeNanoseconds
                - decoded.observationBoundaries[0].observedAtUptimeNanoseconds
                == 60_000_000_000
        )
        #expect(decoded.observationBoundaries[0].kind == .finiteAcquisitionReady)
        #expect(decoded.observationBoundaries[1].kind == .observationHorizon)
        #expect(decoded.observationBoundaries[0].recordSequenceWatermark == 1)
        #expect(decoded.observationBoundaries[1].recordSequenceWatermark == 1)
    }

    @Test("quiet boundaries do not become raw Bluetooth records or byte gaps")
    func boundariesStayOutsideBluetoothRecordStream() throws {
        let value = try PassiveBluetoothValueObservation(
            peripheralIdentifier: "observed-target",
            serviceUUID: "FD50",
            characteristicUUID: "FFE1",
            origin: .notification,
            payload: Data([0x01])
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(
            .value(value),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: .now
        )
        try session.appendObservationBoundary(
            .init(
                kind: .finiteAcquisitionReady,
                recordSequenceWatermark: 1,
                observedAtUptimeNanoseconds: 101,
                observedAtDate: .now
            )
        )
        try session.appendObservationBoundary(
            .init(
                kind: .observationHorizon,
                recordSequenceWatermark: 1,
                observedAtUptimeNanoseconds: 60_000_000_101,
                observedAtDate: .now
            )
        )

        #expect(session.records.count == 1)
        #expect(!session.records[0].event.breaksByteContinuity)
        #expect(session.observationBoundaries.count == 2)
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
        // Historical v2 payloads had no observationBoundaries key at all.
        json = json.replacingOccurrences(
            of: ",\"observationBoundaries\":[]",
            with: ""
        )

        #expect(try PassiveBluetoothCaptureJSON.decode(Data(json.utf8)) == session)
    }

    @Test("schema v2 cannot relabel schema v3 observation boundaries")
    func schemaV2RejectsObservationBoundaries() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_200)
        )
        try session.appendObservationBoundary(
            .init(
                kind: .observationHorizon,
                recordSequenceWatermark: 0,
                observedAtUptimeNanoseconds: 1,
                observedAtDate: Date(timeIntervalSince1970: 5_201)
            )
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        var json = String(decoding: encoded, as: UTF8.self)
        json = json.replacingOccurrences(
            of: "\"schemaVersion\":3",
            with: "\"schemaVersion\":2"
        )

        #expect(
            throws: PassiveBluetoothCaptureValidationError.observationBoundaryNotSupportedBySchemaVersion(2)
        ) {
            _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
        }
    }

    @Test("schema v1 cannot relabel schema v3 observation boundaries")
    func schemaV1RejectsObservationBoundaries() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 5_300)
        )
        try session.appendObservationBoundary(
            .init(
                kind: .finiteAcquisitionReady,
                recordSequenceWatermark: 0,
                observedAtUptimeNanoseconds: 1,
                observedAtDate: Date(timeIntervalSince1970: 5_301)
            )
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        var json = String(decoding: encoded, as: UTF8.self)
        json = json.replacingOccurrences(
            of: "\"schemaVersion\":3",
            with: "\"schemaVersion\":1"
        )

        #expect(
            throws: PassiveBluetoothCaptureValidationError.observationBoundaryNotSupportedBySchemaVersion(1)
        ) {
            _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
        }
    }

    @Test("boundary watermark must name an accepted raw-record prefix")
    func rejectsUnknownWatermark() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(
            interruptionRecord(sequenceNumber: 7, uptime: 100, date: .now)
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.invalidObservationBoundaryWatermark) {
            try session.appendObservationBoundary(
                .init(
                    kind: .finiteAcquisitionReady,
                    recordSequenceWatermark: 6,
                    observedAtUptimeNanoseconds: 101,
                    observedAtDate: .now
                )
            )
        }
    }

    @Test("boundary watermark cannot skip already-received raw evidence")
    func rejectsWatermarkBehindReceiptTime() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(
            interruptionRecord(sequenceNumber: 1, uptime: 100, date: .now)
        )
        try session.append(
            interruptionRecord(sequenceNumber: 2, uptime: 200, date: .now)
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.invalidObservationBoundaryWatermark) {
            try session.appendObservationBoundary(
                .init(
                    kind: .finiteAcquisitionReady,
                    recordSequenceWatermark: 1,
                    observedAtUptimeNanoseconds: 250,
                    observedAtDate: .now
                )
            )
        }
    }

    @Test("observation boundary uptime cannot move backward")
    func rejectsBoundaryUptimeRegression() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.appendObservationBoundary(
            .init(
                kind: .finiteAcquisitionReady,
                recordSequenceWatermark: 0,
                observedAtUptimeNanoseconds: 100,
                observedAtDate: .now
            )
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.nonMonotonicReceiptTime) {
            try session.appendObservationBoundary(
                .init(
                    kind: .observationHorizon,
                    recordSequenceWatermark: 0,
                    observedAtUptimeNanoseconds: 99,
                    observedAtDate: Date(timeIntervalSince1970: 9_999)
                )
            )
        }
    }

    @Test("observation horizon is terminal and cannot precede retained raw evidence")
    func horizonIsTerminal() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(
            interruptionRecord(sequenceNumber: 1, uptime: 100, date: .now)
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.invalidObservationBoundaryWatermark) {
            try session.appendObservationBoundary(
                .init(
                    kind: .observationHorizon,
                    recordSequenceWatermark: 0,
                    observedAtUptimeNanoseconds: 101,
                    observedAtDate: .now
                )
            )
        }

        try session.appendObservationBoundary(
            .init(
                kind: .observationHorizon,
                recordSequenceWatermark: 1,
                observedAtUptimeNanoseconds: 101,
                observedAtDate: .now
            )
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.evidenceAfterObservationHorizon) {
            try session.append(
                interruptionRecord(sequenceNumber: 2, uptime: 102, date: .now)
            )
        }
        #expect(throws: PassiveBluetoothCaptureValidationError.evidenceAfterObservationHorizon) {
            try session.appendObservationBoundary(
                .init(
                    kind: .finiteAcquisitionReady,
                    recordSequenceWatermark: 1,
                    observedAtUptimeNanoseconds: 102,
                    observedAtDate: .now
                )
            )
        }
    }
}
