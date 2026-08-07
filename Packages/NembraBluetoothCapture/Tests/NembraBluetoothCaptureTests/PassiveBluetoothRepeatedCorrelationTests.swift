import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth repeated stock-app correlation")
struct PassiveBluetoothRepeatedCorrelationTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("repeated marker support outranks an isolated nearby stream without decoding payloads")
    func repeatedSupportRanksFirst() throws {
        var session = try makeSession()
        try appendValue(to: &session, sequence: 1, uptime: 900_000_000, characteristic: "A", payload: [0x10])
        try appendValue(to: &session, sequence: 2, uptime: 950_000_000, characteristic: "B", payload: [0x20])
        try appendMarker(to: &session, sequence: 3, uptime: 1_000_000_000, field: "Battery", value: "73%")

        try appendValue(to: &session, sequence: 4, uptime: 1_900_000_000, characteristic: "A", payload: [0x11])
        try appendMarker(to: &session, sequence: 5, uptime: 2_000_000_000, field: "Battery", value: "72%")

        try appendMarker(to: &session, sequence: 6, uptime: 3_000_000_000, field: "Battery", value: "71%")
        try appendValue(to: &session, sequence: 7, uptime: 3_050_000_000, characteristic: "A", payload: [0x12])

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "battery",
            lookbackNanoseconds: 200_000_000,
            lookaheadNanoseconds: 200_000_000
        )

        #expect(report.disposition == .analyzed)
        #expect(report.markerCount == 3)
        #expect(report.distinctDisplayedValues == ["73%", "72%", "71%"])
        #expect(report.streamEvidence.map(\.key.characteristicUUID) == ["A", "B"])

        let repeated = try #require(report.streamEvidence.first)
        #expect(repeated.markerSupportCount == 3)
        #expect(repeated.markerSupportFraction == 1)
        #expect(repeated.rawCandidateCount == 3)
        #expect(repeated.hits.map(\.markerSequenceNumber) == [3, 5, 6])
        #expect(repeated.hits.map(\.candidateSequenceNumber) == [1, 4, 7])
        #expect(repeated.representedDisplayedValues == ["73%", "72%", "71%"])
        #expect(repeated.isRepeatedAcrossMarkers)
        #expect(repeated.isRepeatedAcrossDisplayedValues)
        #expect(abs((repeated.medianNearestAbsoluteOffsetSeconds ?? -1) - 0.1) < 0.000_000_001)
        #expect(abs((repeated.maximumNearestAbsoluteOffsetSeconds ?? -1) - 0.1) < 0.000_000_001)

        let isolated = try #require(report.streamEvidence.last)
        #expect(isolated.key.characteristicUUID == "B")
        #expect(isolated.markerSupportCount == 1)
        #expect(!isolated.isRepeatedAcrossMarkers)
    }

    @Test("high callback rate contributes one nearest support hit per marker")
    func highCadenceStreamCountsMarkerOnce() throws {
        var session = try makeSession()
        try appendValue(to: &session, sequence: 1, uptime: 990_000_000, characteristic: "FAST", payload: [0x01])
        try appendValue(to: &session, sequence: 2, uptime: 995_000_000, characteristic: "FAST", payload: [0x02])
        try appendMarker(to: &session, sequence: 3, uptime: 1_000_000_000, field: "Power", value: "180 W")
        try appendValue(to: &session, sequence: 4, uptime: 1_002_000_000, characteristic: "FAST", payload: [0x03])

        let evidence = try #require(PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "Power",
            lookbackNanoseconds: 20_000_000,
            lookaheadNanoseconds: 20_000_000
        ).streamEvidence.first)

        #expect(evidence.markerSupportCount == 1)
        #expect(evidence.rawCandidateCount == 3)
        #expect(evidence.hits.count == 1)
        #expect(evidence.hits[0].candidateSequenceNumber == 4)
        #expect(abs(evidence.hits[0].candidateOffsetSeconds - 0.002) < 0.000_000_001)
        #expect(evidence.hits[0].payloadByteCount == 1)
    }

    @Test("unscoped mixed-peripheral GATT evidence fails closed before ranking")
    func mixedPeripheralScopeFailsClosed() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 990_000_000,
            characteristic: "A",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendMarker(to: &session, sequence: 2, uptime: 1_000_000_000, field: "Voltage", value: "39.8 V")
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 1_010_000_000,
            characteristic: "B",
            payload: [0x02],
            peripheralIdentifier: "unrelated-b"
        )

        let report = PassiveBluetoothRepeatedCorrelation.analyze(session, field: "Voltage")
        #expect(report.disposition == .ambiguousPeripheralScope)
        #expect(report.markerCount == 1)
        #expect(report.distinctDisplayedValues == ["39.8 V"])
        #expect(report.streamEvidence.isEmpty)
    }

    @Test("explicit target scope filters mixed imported evidence")
    func explicitTargetScopeFiltersMixedCapture() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 990_000_000,
            characteristic: "TARGET",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendMarker(to: &session, sequence: 2, uptime: 1_000_000_000, field: "Current", value: "4.2 A")
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 1_010_000_000,
            characteristic: "OTHER",
            payload: [0x02],
            peripheralIdentifier: "unrelated-b"
        )

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            peripheralIdentifier: "target-a",
            field: "Current",
            lookbackNanoseconds: 50_000_000,
            lookaheadNanoseconds: 50_000_000
        )

        #expect(report.disposition == .analyzed)
        #expect(report.streamEvidence.map(\.key.peripheralIdentifier) == ["target-a"])
        #expect(report.streamEvidence.map(\.key.characteristicUUID) == ["TARGET"])
    }

    @Test("known continuity breaks cannot create repeated support across the gap")
    func interruptionRemainsHardBoundary() throws {
        var session = try makeSession()
        try appendValue(to: &session, sequence: 1, uptime: 900, characteristic: "OLD", payload: [0xAA])
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "disconnect")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 950,
            receivedAtDate: .now
        )
        try appendMarker(to: &session, sequence: 3, uptime: 1_000, field: "Power", value: "0 W")
        try appendValue(to: &session, sequence: 4, uptime: 1_050, characteristic: "NEW", payload: [0xBB])

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "Power",
            lookbackNanoseconds: 500,
            lookaheadNanoseconds: 500
        )

        #expect(report.streamEvidence.map(\.key.characteristicUUID) == ["NEW"])
        #expect(report.streamEvidence.first?.hits.map(\.candidateSequenceNumber) == [4])
    }

    @Test("missing field markers are explicit rather than an empty analyzed report")
    func noMatchingMarkersIsExplicit() throws {
        var session = try makeSession()
        try appendMarker(to: &session, sequence: 1, uptime: 1_000, field: "Battery", value: "73%")

        let report = PassiveBluetoothRepeatedCorrelation.analyze(session, field: "Voltage")
        #expect(report.disposition == .noMatchingMarkers)
        #expect(report.markerCount == 0)
        #expect(report.distinctDisplayedValues.isEmpty)
        #expect(report.streamEvidence.isEmpty)
    }

    @Test("blank explicit peripheral scope fails closed")
    func blankExplicitPeripheralIsInvalid() throws {
        var session = try makeSession()
        try appendMarker(to: &session, sequence: 1, uptime: 1_000, field: "Battery", value: "73%")

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            peripheralIdentifier: "   ",
            field: "Battery"
        )
        #expect(report.disposition == .invalidPeripheralScope)
        #expect(report.markerCount == 1)
        #expect(report.streamEvidence.isEmpty)
    }

    @Test("advertisement-only noise does not fabricate GATT attribution ambiguity")
    func advertisementNoiseDoesNotCreateAmbiguity() throws {
        var session = try makeSession()
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "nearby-unrelated",
                localName: "Nearby"
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 900,
            receivedAtDate: .now
        )
        try appendValue(
            to: &session,
            sequence: 2,
            uptime: 950,
            characteristic: "TARGET",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendMarker(to: &session, sequence: 3, uptime: 1_000, field: "Battery", value: "73%")

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "Battery",
            lookbackNanoseconds: 100,
            lookaheadNanoseconds: 100
        )
        #expect(report.disposition == .analyzed)
        #expect(report.streamEvidence.map(\.key.peripheralIdentifier) == ["target-a"])
    }

    @Test("field matching is case-insensitive while observed display strings stay untouched")
    func fieldMatchingPreservesObservedStrings() throws {
        var session = try makeSession()
        try appendValue(to: &session, sequence: 1, uptime: 950, characteristic: "A", payload: [0x01])
        try appendMarker(to: &session, sequence: 2, uptime: 1_000, field: "Voltage", value: "39.8 V")

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "VOLTAGE",
            lookbackNanoseconds: 100,
            lookaheadNanoseconds: 100
        )
        #expect(report.markerCount == 1)
        #expect(report.distinctDisplayedValues == ["39.8 V"])
        #expect(report.streamEvidence.first?.hits.first?.markerDisplayedValue == "39.8 V")
    }

    @Test("fully tied stream evidence uses deterministic stream identity ordering")
    func deterministicTieOrdering() throws {
        var session = try makeSession()
        try appendValue(to: &session, sequence: 1, uptime: 990, characteristic: "A", payload: [0x01])
        try appendMarker(to: &session, sequence: 2, uptime: 1_000, field: "Battery", value: "73%")
        try appendValue(to: &session, sequence: 3, uptime: 1_010, characteristic: "B", payload: [0x02])

        let report = PassiveBluetoothRepeatedCorrelation.analyze(
            session,
            field: "Battery",
            lookbackNanoseconds: 20,
            lookaheadNanoseconds: 20
        )
        #expect(report.streamEvidence.map(\.key.characteristicUUID) == ["A", "B"])
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
