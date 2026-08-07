import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth repeated correlation independent support")
struct PassiveBluetoothRepeatedCorrelationIndependentSupportTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("one raw callback shared by overlapping marker windows cannot manufacture recurrence")
    func oneSharedCallbackCannotBecomeRepeatedEvidence() throws {
        var session = try makeSession()
        try appendMarker(
            to: &session,
            sequence: 1,
            uptime: 1_000_000_000,
            field: "Battery",
            value: "73%"
        )
        try appendValue(
            to: &session,
            sequence: 2,
            uptime: 1_500_000_000,
            characteristic: "BAT"
        )
        try appendMarker(
            to: &session,
            sequence: 3,
            uptime: 2_000_000_000,
            field: "Battery",
            value: "72%"
        )

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "Battery",
            lookbackNanoseconds: 600_000_000,
            lookaheadNanoseconds: 600_000_000
        )
        let evidence = try #require(report.streamEvidence.first)

        #expect(report.markerCount == 2)
        #expect(evidence.rawCandidateCount == 1)
        #expect(evidence.markerSupportCount == 1)
        #expect(evidence.hits.map(\.candidateSequenceNumber) == [2])
        #expect(!evidence.isRepeatedAcrossMarkers)
        #expect(!evidence.isRepeatedAcrossDisplayedValues)
    }

    @Test("matching reassigns an earlier marker when that preserves two independent callbacks")
    func augmentingPathPreservesMaximumIndependentSupport() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 800_000_000,
            characteristic: "BAT",
            payload: [0xB0]
        )
        try appendMarker(
            to: &session,
            sequence: 2,
            uptime: 1_000_000_000,
            field: "Battery",
            value: "73%"
        )
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 1_100_000_000,
            characteristic: "BAT",
            payload: [0xA0]
        )
        try appendMarker(
            to: &session,
            sequence: 4,
            uptime: 1_200_000_000,
            field: "Battery",
            value: "72%"
        )

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "Battery",
            lookbackNanoseconds: 300_000_000,
            lookaheadNanoseconds: 300_000_000
        )
        let evidence = try #require(report.streamEvidence.first)

        #expect(evidence.rawCandidateCount == 2)
        #expect(evidence.markerSupportCount == 2)
        #expect(evidence.hits.map(\.markerSequenceNumber) == [2, 4])
        #expect(evidence.hits.map(\.candidateSequenceNumber) == [1, 3])
        #expect(evidence.representedDisplayedValues == ["73%", "72%"])
        #expect(evidence.isRepeatedAcrossMarkers)
        #expect(evidence.isRepeatedAcrossDisplayedValues)

        let assignedOffsets = evidence.hits.map(\.absoluteOffsetSeconds)
        #expect(abs(assignedOffsets[0] - 0.2) < 0.000_000_001)
        #expect(abs(assignedOffsets[1] - 0.1) < 0.000_000_001)
        #expect(abs((evidence.medianNearestAbsoluteOffsetSeconds ?? -1) - 0.1) < 0.000_000_001)
        #expect(abs((evidence.maximumNearestAbsoluteOffsetSeconds ?? -1) - 0.1) < 0.000_000_001)
    }

    @Test("structured connection identity participates in unscoped ambiguity")
    func unrelatedConnectionIdentityFailsClosed() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 900,
            characteristic: "BAT",
            peripheralIdentifier: "target-a"
        )
        try appendMarker(
            to: &session,
            sequence: 2,
            uptime: 1_000,
            field: "Battery",
            value: "73%"
        )
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "unrelated-b",
                state: .connected
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 1_100,
            receivedAtDate: .now
        )

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "Battery",
            lookbackNanoseconds: 200,
            lookaheadNanoseconds: 200
        )

        #expect(report.disposition == .ambiguousPeripheralScope)
        #expect(report.markerCount == 1)
        #expect(report.streamEvidence.isEmpty)
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
            .stockAppState(try PassiveBluetoothStockAppObservation(
                field: field,
                displayedValue: value
            )),
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
        payload: [UInt8] = [0x01],
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
