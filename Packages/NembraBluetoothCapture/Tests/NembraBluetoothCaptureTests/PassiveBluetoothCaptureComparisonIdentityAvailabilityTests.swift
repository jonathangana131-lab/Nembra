import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth controlled comparison identity availability")
struct PassiveBluetoothCaptureComparisonIdentityAvailabilityTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("different observed GATT identifiers withhold direct state-difference metrics")
    func differentTargetsAreIdentityAmbiguous() throws {
        var baseline = try makeSession()
        try appendValue(
            peripheral: "baseline-target",
            payload: [0x10],
            sequence: 1,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            peripheral: "comparison-target",
            payload: [0x20],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.peripheralRelationship == .differentObservedIdentifiers)
        #expect(report.differenceAvailability == .identityAmbiguous)
        #expect(report.addedServices == nil)
        #expect(report.removedServices == nil)
        #expect(report.sharedServices == nil)
        #expect(report.streamComparisons.count == 2)
        #expect(report.streamComparisons.allSatisfy {
            $0.differenceAvailability == .identityAmbiguous &&
            $0.sharedPayloadCount == nil &&
            $0.baselineOnlyPayloadCount == nil &&
            $0.comparisonOnlyPayloadCount == nil &&
            $0.lastPayloadChanged == nil &&
            $0.rawDifferenceScore == nil
        })
    }

    @Test("unresolved GATT identity withholds direct state-difference metrics")
    func unresolvedTargetIsIdentityAmbiguous() throws {
        var baseline = try makeSession()
        try baseline.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "nearby-advertisement-only",
                serviceUUIDs: ["FD50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        var comparison = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            payload: [0x20],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselinePeripheralIdentifier == nil)
        #expect(report.comparisonPeripheralIdentifier == "selected-target")
        #expect(report.peripheralRelationship == .unresolved)
        #expect(report.differenceAvailability == .identityAmbiguous)
        #expect(report.addedServices == nil)
        #expect(report.removedServices == nil)
        #expect(report.sharedServices == nil)
        let stream = try #require(report.streamComparisons.first)
        #expect(stream.presence == .comparisonOnly)
        #expect(stream.differenceAvailability == .identityAmbiguous)
        #expect(stream.rawDifferenceScore == nil)
    }

    @Test("same observed GATT identifier remains directly comparable when uninterrupted")
    func sameTargetWithoutGapRemainsComparable() throws {
        var baseline = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            payload: [0x10],
            sequence: 1,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            payload: [0x20],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.peripheralRelationship == .sameObservedIdentifier)
        #expect(report.differenceAvailability == .comparable)
        let stream = try #require(report.streamComparisons.first)
        #expect(stream.differenceAvailability == .comparable)
        #expect(stream.baselineOnlyPayloadCount == 1)
        #expect(stream.comparisonOnlyPayloadCount == 1)
        #expect(stream.lastPayloadChanged == true)
        #expect(stream.rawDifferenceScore == 3)
    }

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
    }

    private func appendValue(
        peripheral: String,
        payload: [UInt8],
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: "A201",
                characteristicUUID: "2B10",
                origin: .subscriptionUpdate,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }
}
