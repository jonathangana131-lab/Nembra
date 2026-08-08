import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth controlled capture comparison")
struct PassiveBluetoothCaptureComparisonTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("comparison surfaces added services and changed raw payload streams")
    func controlledStateDiff() throws {
        var baseline = try makeSession()
        try appendService("A201", sequence: 1, to: &baseline)
        try appendValue(service: "A201", characteristic: "2B10", payload: [0x10], sequence: 2, to: &baseline)
        try appendValue(service: "A201", characteristic: "2B10", payload: [0x11], sequence: 3, to: &baseline)
        try appendValue(service: "A201", characteristic: "SAME", payload: [0xAA], sequence: 4, to: &baseline)

        var comparison = try makeSession()
        try appendService("A201", sequence: 1, to: &comparison)
        try appendService("180F", sequence: 2, to: &comparison)
        try appendValue(service: "A201", characteristic: "2B10", payload: [0x10], sequence: 3, to: &comparison)
        try appendValue(service: "A201", characteristic: "2B10", payload: [0x20], sequence: 4, to: &comparison)
        try appendValue(service: "A201", characteristic: "SAME", payload: [0xAA], sequence: 5, to: &comparison)

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselinePeripheralIdentifier == "physical-es80-placeholder")
        #expect(report.comparisonPeripheralIdentifier == "physical-es80-placeholder")
        #expect(report.peripheralRelationship == .sameObservedIdentifier)
        #expect(report.addedServices == ["180F"])
        #expect(report.removedServices.isEmpty)
        #expect(report.sharedServices == ["A201"])

        let changed = try #require(report.streamComparisons.first { $0.key.characteristicUUID == "2B10" })
        #expect(changed.presence == .both)
        #expect(changed.sharedPayloadCount == 1)
        #expect(changed.baselineOnlyPayloadCount == 1)
        #expect(changed.comparisonOnlyPayloadCount == 1)
        #expect(changed.lastPayloadChanged == true)
        #expect(changed.rawDifferenceScore == 3)

        let same = try #require(report.streamComparisons.first { $0.key.characteristicUUID == "SAME" })
        #expect(same.sharedPayloadCount == 1)
        #expect(same.baselineOnlyPayloadCount == 0)
        #expect(same.comparisonOnlyPayloadCount == 0)
        #expect(same.lastPayloadChanged == false)
        #expect(same.rawDifferenceScore == 0)
    }

    @Test("different resolved peripheral identifiers are called out and streams are not conflated")
    func differentPeripheralIdentifiers() throws {
        var baseline = try makeSession()
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            payload: [0x10],
            sequence: 1,
            peripheral: "baseline-peripheral",
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            payload: [0x20],
            sequence: 1,
            peripheral: "comparison-peripheral",
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselinePeripheralIdentifier == "baseline-peripheral")
        #expect(report.comparisonPeripheralIdentifier == "comparison-peripheral")
        #expect(report.peripheralRelationship == .differentObservedIdentifiers)
        #expect(report.streamComparisons.count == 2)
        #expect(Set(report.streamComparisons.map(\.presence)) == [.baselineOnly, .comparisonOnly])
    }

    @Test("ambiguous/no GATT identity makes peripheral relationship unresolved")
    func unresolvedPeripheralRelationship() throws {
        var baseline = try makeSession()
        try baseline.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "nearby-only",
                serviceUUIDs: ["FD50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        var comparison = try makeSession()
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            payload: [0x20],
            sequence: 1,
            peripheral: "selected-es80",
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )
        #expect(report.baselinePeripheralIdentifier == nil)
        #expect(report.comparisonPeripheralIdentifier == "selected-es80")
        #expect(report.peripheralRelationship == .unresolved)
        #expect(report.baselineServices.isEmpty)
    }

    @Test("streams present in only one capture remain explicit rather than fabricated")
    func oneSidedStreams() throws {
        var baseline = try makeSession()
        try appendValue(service: "TEST", characteristic: "BASE", payload: [0x01], sequence: 1, to: &baseline)

        var comparison = try makeSession()
        try appendValue(service: "TEST", characteristic: "NEW", payload: [0x02], sequence: 1, to: &comparison)

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        let baseOnly = try #require(report.streamComparisons.first { $0.key.characteristicUUID == "BASE" })
        #expect(baseOnly.presence == .baselineOnly)
        #expect(baseOnly.baseline != nil)
        #expect(baseOnly.comparison == nil)
        #expect(baseOnly.lastPayloadChanged == nil)

        let newOnly = try #require(report.streamComparisons.first { $0.key.characteristicUUID == "NEW" })
        #expect(newOnly.presence == .comparisonOnly)
        #expect(newOnly.baseline == nil)
        #expect(newOnly.comparison != nil)
        #expect(newOnly.lastPayloadChanged == nil)
    }

    @Test("comparison does not count stock-app marker text as a raw value stream")
    func markersDoNotManufactureStreams() throws {
        var baseline = try makeSession()
        try baseline.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(
                field: "voltage",
                displayedValue: "39.8 V"
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        var comparison = try makeSession()
        try comparison.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(
                field: "voltage",
                displayedValue: "38.9 V"
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )
        #expect(report.streamComparisons.isEmpty)
        #expect(report.peripheralRelationship == .unresolved)
    }

    @Test("raw difference sorting is deterministic when scores tie")
    func deterministicOrdering() throws {
        var baseline = try makeSession()
        var comparison = try makeSession()
        try appendValue(service: "B", characteristic: "1", payload: [0x00], sequence: 1, to: &baseline)
        try appendValue(service: "A", characteristic: "1", payload: [0x00], sequence: 2, to: &baseline)
        try appendValue(service: "B", characteristic: "1", payload: [0x01], sequence: 1, to: &comparison)
        try appendValue(service: "A", characteristic: "1", payload: [0x01], sequence: 2, to: &comparison)

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )
        #expect(report.streamComparisons.map(\.key.serviceUUID) == ["A", "B"])
    }

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
    }

    private func appendService(
        _ uuid: String,
        sequence: UInt64,
        peripheral: String = "physical-es80-placeholder",
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: uuid,
                isPrimary: true
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }

    private func appendValue(
        service: String,
        characteristic: String,
        payload: [UInt8],
        sequence: UInt64,
        peripheral: String = "physical-es80-placeholder",
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: service,
                characteristicUUID: characteristic,
                origin: .subscriptionUpdate,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }
}
