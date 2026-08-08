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

    @Test("comparison surfaces hosted GATT service and same-origin raw payload differences")
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
        #expect(report.baselineContinuityBreakCount == 0)
        #expect(report.comparisonContinuityBreakCount == 0)
        #expect(report.differenceAvailability == .comparable)
        #expect(report.addedServices == Set(["180F"]))
        #expect(report.removedServices == Set<String>())
        #expect(report.sharedServices == Set(["A201"]))

        let changed = try #require(report.streamComparisons.first {
            $0.key.characteristicUUID == "2B10" && $0.origin == .subscriptionUpdate
        })
        #expect(changed.presence == .both)
        #expect(changed.differenceAvailability == .comparable)
        #expect(changed.baseline?.continuitySegmentCount == 1)
        #expect(changed.comparison?.continuitySegmentCount == 1)
        #expect(changed.sharedPayloadCount == 1)
        #expect(changed.baselineOnlyPayloadCount == 1)
        #expect(changed.comparisonOnlyPayloadCount == 1)
        #expect(changed.lastPayloadChanged == true)
        #expect(changed.rawDifferenceScore == 3)

        let same = try #require(report.streamComparisons.first {
            $0.key.characteristicUUID == "SAME" && $0.origin == .subscriptionUpdate
        })
        #expect(same.sharedPayloadCount == 1)
        #expect(same.baselineOnlyPayloadCount == 0)
        #expect(same.comparisonOnlyPayloadCount == 0)
        #expect(same.lastPayloadChanged == false)
        #expect(same.rawDifferenceScore == 0)
    }

    @Test("value origin is part of comparison identity instead of manufacturing a state delta")
    func isolatesValueOrigins() throws {
        var baseline = try makeSession()
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            origin: .readResponse,
            payload: [0xAA],
            sequence: 1,
            to: &baseline
        )
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            origin: .subscriptionUpdate,
            payload: [0xBB],
            sequence: 2,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            origin: .subscriptionUpdate,
            payload: [0xBB],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )
        #expect(report.streamComparisons.count == 2)

        let subscription = try #require(report.streamComparisons.first {
            $0.key.characteristicUUID == "2B10" && $0.origin == .subscriptionUpdate
        })
        #expect(subscription.presence == .both)
        #expect(subscription.sharedPayloadCount == 1)
        #expect(subscription.baselineOnlyPayloadCount == 0)
        #expect(subscription.comparisonOnlyPayloadCount == 0)
        #expect(subscription.lastPayloadChanged == false)
        #expect(subscription.rawDifferenceScore == 0)

        let read = try #require(report.streamComparisons.first {
            $0.key.characteristicUUID == "2B10" && $0.origin == .readResponse
        })
        #expect(read.presence == .baselineOnly)
        #expect(read.sharedPayloadCount == 0)
        #expect(read.baselineOnlyPayloadCount == 1)
        #expect(read.comparisonOnlyPayloadCount == 0)
        #expect(read.lastPayloadChanged == nil)
        #expect(read.rawDifferenceScore == 3)
    }

    @Test("same bytes from different origins remain separate evidence strata")
    func sameBytesDifferentOriginsDoNotBecomeSharedPayload() throws {
        var baseline = try makeSession()
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            origin: .readResponse,
            payload: [0xAA],
            sequence: 1,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            service: "A201",
            characteristic: "2B10",
            origin: .subscriptionUpdate,
            payload: [0xAA],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )
        #expect(report.streamComparisons.count == 2)
        #expect(report.streamComparisons.allSatisfy { $0.sharedPayloadCount == 0 })
        #expect(Set(report.streamComparisons.map(\.origin.rawValue)) == Set([
            PassiveBluetoothValueOrigin.readResponse.rawValue,
            PassiveBluetoothValueOrigin.subscriptionUpdate.rawValue
        ]))
    }

    @Test("known interruption withholds direct payload and topology difference metrics")
    func interruptionMakesComparisonContinuityAmbiguous() throws {
        var baseline = try makeSession()
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xAA], sequence: 1, to: &baseline)
        try appendInterruption(sequence: 2, to: &baseline)
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xBB], sequence: 3, to: &baseline)

        var comparison = try makeSession()
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xBB], sequence: 1, to: &comparison)

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselineContinuityBreakCount == 1)
        #expect(report.comparisonContinuityBreakCount == 0)
        #expect(report.differenceAvailability == .continuityAmbiguous)
        #expect(report.addedServices == nil)
        #expect(report.removedServices == nil)
        #expect(report.sharedServices == nil)

        let stream = try #require(report.streamComparisons.first)
        #expect(stream.origin == .subscriptionUpdate)
        #expect(stream.presence == .both)
        #expect(stream.differenceAvailability == .continuityAmbiguous)
        #expect(stream.baseline?.continuitySegmentCount == 2)
        #expect(stream.comparison?.continuitySegmentCount == 1)
        #expect(stream.baseline?.uniquePayloads == Set([Data([0xAA]), Data([0xBB])]))
        #expect(stream.comparison?.uniquePayloads == Set([Data([0xBB])]))
        #expect(stream.sharedPayloadCount == nil)
        #expect(stream.baselineOnlyPayloadCount == nil)
        #expect(stream.comparisonOnlyPayloadCount == nil)
        #expect(stream.lastPayloadChanged == nil)
        #expect(stream.rawDifferenceScore == nil)
    }

    @Test("every structured disconnect is a capture-wide comparison boundary")
    func structuredDisconnectAlwaysBreaksComparisonContinuity() throws {
        var baseline = try makeSession()
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xAA], sequence: 1, to: &baseline)
        try appendDisconnect(peripheral: "noise-device", sequence: 2, to: &baseline)
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xBB], sequence: 3, to: &baseline)

        var comparison = try makeSession()
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xBB], sequence: 1, to: &comparison)

        var report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )
        #expect(report.baselinePeripheralIdentifier == "physical-es80-placeholder")
        #expect(report.baselineContinuityBreakCount == 1)
        #expect(report.differenceAvailability == .continuityAmbiguous)
        let unrelatedBreak = try #require(report.streamComparisons.first)
        #expect(unrelatedBreak.baseline?.continuitySegmentCount == 2)
        #expect(unrelatedBreak.sharedPayloadCount == nil)
        #expect(unrelatedBreak.baselineOnlyPayloadCount == nil)
        #expect(unrelatedBreak.rawDifferenceScore == nil)

        baseline = try makeSession()
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xAA], sequence: 1, to: &baseline)
        try appendDisconnect(peripheral: "physical-es80-placeholder", sequence: 2, to: &baseline)
        try appendValue(service: "A201", characteristic: "2B10", payload: [0xBB], sequence: 3, to: &baseline)

        report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )
        #expect(report.baselinePeripheralIdentifier == "physical-es80-placeholder")
        #expect(report.baselineContinuityBreakCount == 1)
        #expect(report.differenceAvailability == .continuityAmbiguous)
        #expect(report.streamComparisons.first?.baseline?.continuitySegmentCount == 2)
        #expect(report.streamComparisons.first?.rawDifferenceScore == nil)
    }

    @Test("advertisement-only service UUIDs never become GATT topology deltas")
    func advertisementServicesStayOutOfGATTTopology() throws {
        var baseline = try makeSession()
        try appendService("a201", sequence: 1, to: &baseline)
        try appendAdvertisement(
            serviceUUIDs: ["180F"],
            sequence: 2,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendService("A201", sequence: 1, to: &comparison)

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselineServices == Set(["A201"]))
        #expect(report.comparisonServices == Set(["A201"]))
        #expect(report.addedServices == Set<String>())
        #expect(report.removedServices == Set<String>())
        #expect(report.sharedServices == Set(["A201"]))
    }

    @Test("hosted GATT topology across a known gap remains descriptive but is not directly differenced")
    func topologyAcrossGapIsUnscored() throws {
        var baseline = try makeSession()
        try appendService("OLD", sequence: 1, to: &baseline)
        try appendInterruption(sequence: 2, to: &baseline)
        try appendService("NEW", sequence: 3, to: &baseline)

        var comparison = try makeSession()
        try appendService("NEW", sequence: 1, to: &comparison)

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselineServices == Set(["OLD", "NEW"]))
        #expect(report.comparisonServices == Set(["NEW"]))
        #expect(report.differenceAvailability == .continuityAmbiguous)
        #expect(report.addedServices == nil)
        #expect(report.removedServices == nil)
        #expect(report.sharedServices == nil)
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
        #expect(baseOnly.origin == .subscriptionUpdate)
        #expect(baseOnly.presence == .baselineOnly)
        #expect(baseOnly.baseline != nil)
        #expect(baseOnly.comparison == nil)
        #expect(baseOnly.lastPayloadChanged == nil)

        let newOnly = try #require(report.streamComparisons.first { $0.key.characteristicUUID == "NEW" })
        #expect(newOnly.origin == .subscriptionUpdate)
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

    private func appendAdvertisement(
        serviceUUIDs: [String],
        sequence: UInt64,
        peripheral: String = "physical-es80-placeholder",
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: peripheral,
                serviceUUIDs: serviceUUIDs
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }

    private func appendInterruption(
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "test observation gap")),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }

    private func appendDisconnect(
        peripheral: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: .disconnected
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }

    private func appendValue(
        service: String,
        characteristic: String,
        origin: PassiveBluetoothValueOrigin = .subscriptionUpdate,
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
                origin: origin,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }
}
