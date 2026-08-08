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

    @Test("GATT UUID representation changes do not manufacture one-sided comparison streams")
    func canonicalizesGATTStreamIdentityAcrossCaptures() throws {
        var baseline = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            service: "  a201\n",
            characteristic: " 2b10 ",
            payload: [0xAA],
            sequence: 1,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            service: "A201",
            characteristic: "2B10",
            payload: [0xAA],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.differenceAvailability == .comparable)
        #expect(report.streamComparisons.count == 1)
        let stream = try #require(report.streamComparisons.first)
        #expect(stream.key.peripheralIdentifier == "selected-target")
        #expect(stream.key.serviceUUID == "A201")
        #expect(stream.key.characteristicUUID == "2B10")
        #expect(stream.presence == .both)
        #expect(stream.baseline?.key == stream.comparison?.key)
        #expect(stream.sharedPayloadCount == 1)
        #expect(stream.baselineOnlyPayloadCount == 0)
        #expect(stream.comparisonOnlyPayloadCount == 0)
        #expect(stream.rawDifferenceScore == 0)
    }

    @Test("equivalent GATT UUID spellings inside one capture collapse into one evidence stratum")
    func canonicalizesGATTStreamIdentityWithinCapture() throws {
        var baseline = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            service: "a201",
            characteristic: "2b10",
            payload: [0xAA],
            sequence: 1,
            to: &baseline
        )
        try appendValue(
            peripheral: "selected-target",
            service: " A201 ",
            characteristic: " 2B10\n",
            payload: [0xBB],
            sequence: 2,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            service: "A201",
            characteristic: "2B10",
            payload: [0xBB],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.streamComparisons.count == 1)
        let stream = try #require(report.streamComparisons.first)
        #expect(stream.presence == .both)
        #expect(stream.baseline?.sampleCount == 2)
        #expect(stream.baseline?.continuitySegmentCount == 1)
        #expect(stream.baseline?.uniquePayloads == Set([Data([0xAA]), Data([0xBB])]))
        #expect(stream.comparison?.sampleCount == 1)
        #expect(stream.sharedPayloadCount == 1)
        #expect(stream.baselineOnlyPayloadCount == 1)
        #expect(stream.comparisonOnlyPayloadCount == 0)
        #expect(stream.lastPayloadChanged == false)
        #expect(stream.rawDifferenceScore == 1)
    }

    @Test("GATT canonicalization never normalizes opaque peripheral identifiers")
    func preservesOpaquePeripheralIdentity() throws {
        var baseline = try makeSession()
        try appendValue(
            peripheral: "Selected-Target",
            service: " a201 ",
            characteristic: "2b10",
            payload: [0xAA],
            sequence: 1,
            to: &baseline
        )

        var comparison = try makeSession()
        try appendValue(
            peripheral: "selected-target",
            service: "A201",
            characteristic: "2B10",
            payload: [0xAA],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselinePeripheralIdentifier == "Selected-Target")
        #expect(report.comparisonPeripheralIdentifier == "selected-target")
        #expect(report.peripheralRelationship == .differentObservedIdentifiers)
        #expect(report.differenceAvailability == .identityAmbiguous)
        #expect(report.streamComparisons.count == 2)
        #expect(Set(report.streamComparisons.map(\.key.peripheralIdentifier)) == Set([
            "Selected-Target",
            "selected-target"
        ]))
        #expect(report.streamComparisons.allSatisfy {
            $0.key.serviceUUID == "A201" &&
            $0.key.characteristicUUID == "2B10" &&
            $0.rawDifferenceScore == nil
        })
    }

    @Test("contradictory capture vehicle context withholds otherwise-comparable direct metrics")
    func captureVehicleContextMismatchFailsClosed() throws {
        let baselineID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let comparisonID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let otherIdentity = VehicleIdentity(
            manufacturer: "MAXSHOT",
            model: "V1S Pro",
            displayName: "MAXSHOT V1S Pro",
            protocolFamily: "deferred-unverified"
        )

        var baseline = try makeSession(id: baselineID)
        try appendValue(
            peripheral: "selected-target",
            payload: [0xAA],
            sequence: 1,
            to: &baseline
        )

        var comparison = try makeSession(
            id: comparisonID,
            vehicleIdentity: otherIdentity
        )
        try appendValue(
            peripheral: "selected-target",
            payload: [0xAA],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselineCaptureSessionID == baselineID)
        #expect(report.comparisonCaptureSessionID == comparisonID)
        #expect(report.baselineVehicleIdentity == identity)
        #expect(report.comparisonVehicleIdentity == otherIdentity)
        #expect(report.peripheralRelationship == .sameObservedIdentifier)
        #expect(report.differenceAvailability == .captureContextMismatch)
        #expect(report.baselineServices == Set(["A201"]))
        #expect(report.comparisonServices == Set(["A201"]))
        #expect(report.addedServices == nil)
        #expect(report.removedServices == nil)
        #expect(report.sharedServices == nil)
        let stream = try #require(report.streamComparisons.first)
        #expect(stream.presence == .both)
        #expect(stream.differenceAvailability == .captureContextMismatch)
        #expect(stream.sharedPayloadCount == nil)
        #expect(stream.baselineOnlyPayloadCount == nil)
        #expect(stream.comparisonOnlyPayloadCount == nil)
        #expect(stream.lastPayloadChanged == nil)
        #expect(stream.rawDifferenceScore == nil)
    }

    @Test("reports retain exact source capture session identities")
    func reportsBindToExactCapturePair() throws {
        let firstBaselineID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let firstComparisonID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        let secondBaselineID = UUID(uuidString: "50000000-0000-0000-0000-000000000005")!
        let secondComparisonID = UUID(uuidString: "60000000-0000-0000-0000-000000000006")!

        var firstBaseline = try makeSession(id: firstBaselineID)
        try appendValue(
            peripheral: "selected-target",
            payload: [0xAA],
            sequence: 1,
            to: &firstBaseline
        )
        var firstComparison = try makeSession(id: firstComparisonID)
        try appendValue(
            peripheral: "selected-target",
            payload: [0xAA],
            sequence: 1,
            to: &firstComparison
        )

        var secondBaseline = try makeSession(id: secondBaselineID)
        try appendValue(
            peripheral: "selected-target",
            payload: [0xAA],
            sequence: 1,
            to: &secondBaseline
        )
        var secondComparison = try makeSession(id: secondComparisonID)
        try appendValue(
            peripheral: "selected-target",
            payload: [0xAA],
            sequence: 1,
            to: &secondComparison
        )

        let firstReport = PassiveBluetoothCaptureComparison.compare(
            baseline: firstBaseline,
            comparison: firstComparison
        )
        let secondReport = PassiveBluetoothCaptureComparison.compare(
            baseline: secondBaseline,
            comparison: secondComparison
        )

        #expect(firstReport.differenceAvailability == .comparable)
        #expect(secondReport.differenceAvailability == .comparable)
        #expect(firstReport.baselineCaptureSessionID == firstBaselineID)
        #expect(firstReport.comparisonCaptureSessionID == firstComparisonID)
        #expect(secondReport.baselineCaptureSessionID == secondBaselineID)
        #expect(secondReport.comparisonCaptureSessionID == secondComparisonID)
        #expect(firstReport.baselineVehicleIdentity == identity)
        #expect(firstReport.comparisonVehicleIdentity == identity)
        #expect(secondReport.baselineVehicleIdentity == identity)
        #expect(secondReport.comparisonVehicleIdentity == identity)
        #expect(firstReport != secondReport)
    }

    private func makeSession(
        id: UUID = UUID(),
        vehicleIdentity: VehicleIdentity? = nil
    ) throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: id,
            vehicleIdentity: vehicleIdentity ?? identity,
            startedAt: .now
        )
    }

    private func appendValue(
        peripheral: String,
        service: String = "A201",
        characteristic: String = "2B10",
        payload: [UInt8],
        sequence: UInt64,
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
