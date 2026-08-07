import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth repeated-correlation batch")
struct PassiveBluetoothRepeatedCorrelationBatchTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("all observed fields are grouped case-insensitively and analyzed deterministically")
    func allObservedFieldsAreBatched() throws {
        var session = try makeSession()
        try appendValue(to: &session, sequence: 1, uptime: 950, characteristic: "BAT", payload: [0x01])
        try appendMarker(to: &session, sequence: 2, uptime: 1_000, field: "Battery", value: "73%")
        try appendValue(to: &session, sequence: 3, uptime: 1_950, characteristic: "BAT", payload: [0x02])
        try appendMarker(to: &session, sequence: 4, uptime: 2_000, field: "battery", value: "72%")
        try appendValue(to: &session, sequence: 5, uptime: 2_950, characteristic: "VOLT", payload: [0x03])
        try appendMarker(to: &session, sequence: 6, uptime: 3_000, field: "Voltage", value: "39.8 V")

        let reports = PassiveBluetoothRepeatedCorrelationBatch.analyzeAllObservedFields(
            in: session,
            lookbackNanoseconds: 100,
            lookaheadNanoseconds: 100
        )

        #expect(reports.map(\.field) == ["Battery", "Voltage"])
        #expect(reports.map(\.markerCount) == [2, 1])
        #expect(reports[0].distinctDisplayedValues == ["73%", "72%"])
        #expect(reports[0].streamEvidence.first?.key.characteristicUUID == "BAT")
        #expect(reports[0].streamEvidence.first?.markerSupportCount == 2)
        #expect(reports[1].streamEvidence.first?.key.characteristicUUID == "VOLT")
    }

    @Test("batch explicit target scope filters every field consistently")
    func explicitTargetBatchFiltersMixedCapture() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 950,
            characteristic: "TARGET-BAT",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendMarker(to: &session, sequence: 2, uptime: 1_000, field: "Battery", value: "73%")
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 1_050,
            characteristic: "OTHER-BAT",
            payload: [0x02],
            peripheralIdentifier: "unrelated-b"
        )
        try appendValue(
            to: &session,
            sequence: 4,
            uptime: 1_950,
            characteristic: "TARGET-POWER",
            payload: [0x03],
            peripheralIdentifier: "target-a"
        )
        try appendMarker(to: &session, sequence: 5, uptime: 2_000, field: "Power", value: "167 W")
        try appendValue(
            to: &session,
            sequence: 6,
            uptime: 2_050,
            characteristic: "OTHER-POWER",
            payload: [0x04],
            peripheralIdentifier: "unrelated-b"
        )

        let reports = PassiveBluetoothRepeatedCorrelationBatch.analyzeAllObservedFields(
            in: session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 100,
            lookaheadNanoseconds: 100
        )

        #expect(reports.map(\.field) == ["Battery", "Power"])
        #expect(reports.allSatisfy { $0.disposition == .analyzed })
        #expect(reports.flatMap(\.streamEvidence).allSatisfy {
            $0.key.peripheralIdentifier == "target-a"
        })
        #expect(reports[0].streamEvidence.map(\.key.characteristicUUID) == ["TARGET-BAT"])
        #expect(reports[1].streamEvidence.map(\.key.characteristicUUID) == ["TARGET-POWER"])
    }

    @Test("mixed unscoped capture fails closed for every observed field")
    func ambiguousBatchFailsClosed() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 950,
            characteristic: "A",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendMarker(to: &session, sequence: 2, uptime: 1_000, field: "Battery", value: "73%")
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 1_050,
            characteristic: "B",
            payload: [0x02],
            peripheralIdentifier: "unrelated-b"
        )
        try appendMarker(to: &session, sequence: 4, uptime: 2_000, field: "Voltage", value: "39.8 V")

        let reports = PassiveBluetoothRepeatedCorrelationBatch.analyzeAllObservedFields(in: session)
        #expect(reports.map(\.field) == ["Battery", "Voltage"])
        #expect(reports.allSatisfy { $0.disposition == .ambiguousPeripheralScope })
        #expect(reports.allSatisfy(\.streamEvidence.isEmpty))
    }

    @Test("capture without markers produces no fabricated field reports")
    func noMarkersProducesNoReports() throws {
        var session = try makeSession()
        try appendValue(to: &session, sequence: 1, uptime: 950, characteristic: "A", payload: [0x01])

        #expect(PassiveBluetoothRepeatedCorrelationBatch.analyzeAllObservedFields(in: session).isEmpty)
    }

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func appendMarker(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        field: String,
        value: String
    ) throws {
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: field, displayedValue: value)),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        characteristic: String,
        payload: [UInt8],
        peripheralIdentifier: String = "physical-es80-placeholder"
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheralIdentifier,
                serviceUUID: "TEST",
                characteristicUUID: characteristic,
                origin: .subscriptionUpdate,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }
}
