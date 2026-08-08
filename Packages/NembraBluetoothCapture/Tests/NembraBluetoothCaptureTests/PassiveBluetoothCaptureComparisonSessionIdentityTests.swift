import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth controlled comparison session identity")
struct PassiveBluetoothCaptureComparisonSessionIdentityTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("self-comparison preserves descriptive evidence but withholds direct metrics")
    func selfComparisonFailsClosed() throws {
        let sessionID = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
        var session = try makeSession(id: sessionID)
        try appendValue(
            payload: [0xAA],
            sequence: 1,
            to: &session
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: session,
            comparison: session
        )

        #expect(report.baselineCaptureSessionID == sessionID)
        #expect(report.comparisonCaptureSessionID == sessionID)
        #expect(report.peripheralRelationship == .sameObservedIdentifier)
        #expect(report.differenceAvailability == .sameCaptureSession)
        #expect(report.baselineServices == Set(["A201"]))
        #expect(report.comparisonServices == Set(["A201"]))
        #expect(report.addedServices == nil)
        #expect(report.removedServices == nil)
        #expect(report.sharedServices == nil)

        let stream = try #require(report.streamComparisons.first)
        #expect(stream.presence == .both)
        #expect(stream.differenceAvailability == .sameCaptureSession)
        #expect(stream.baseline?.lastPayload == Data([0xAA]))
        #expect(stream.comparison?.lastPayload == Data([0xAA]))
        #expect(stream.sharedPayloadCount == nil)
        #expect(stream.baselineOnlyPayloadCount == nil)
        #expect(stream.comparisonOnlyPayloadCount == nil)
        #expect(stream.lastPayloadChanged == nil)
        #expect(stream.rawDifferenceScore == nil)
    }

    @Test("separate materializations claiming one session identity cannot produce state deltas")
    func sameSessionIDDifferentContentsFailClosed() throws {
        let sessionID = UUID(uuidString: "80000000-0000-0000-0000-000000000008")!
        var baseline = try makeSession(id: sessionID)
        try appendValue(
            payload: [0xAA],
            sequence: 1,
            to: &baseline
        )

        var comparison = try makeSession(id: sessionID)
        try appendValue(
            payload: [0xBB],
            sequence: 1,
            to: &comparison
        )

        let report = PassiveBluetoothCaptureComparison.compare(
            baseline: baseline,
            comparison: comparison
        )

        #expect(report.baselineCaptureSessionID == sessionID)
        #expect(report.comparisonCaptureSessionID == sessionID)
        #expect(report.peripheralRelationship == .sameObservedIdentifier)
        #expect(report.differenceAvailability == .sameCaptureSession)
        #expect(report.baselineServices == Set(["A201"]))
        #expect(report.comparisonServices == Set(["A201"]))
        #expect(report.addedServices == nil)
        #expect(report.removedServices == nil)
        #expect(report.sharedServices == nil)

        let stream = try #require(report.streamComparisons.first)
        #expect(stream.presence == .both)
        #expect(stream.differenceAvailability == .sameCaptureSession)
        #expect(stream.baseline?.lastPayload == Data([0xAA]))
        #expect(stream.comparison?.lastPayload == Data([0xBB]))
        #expect(stream.sharedPayloadCount == nil)
        #expect(stream.baselineOnlyPayloadCount == nil)
        #expect(stream.comparisonOnlyPayloadCount == nil)
        #expect(stream.lastPayloadChanged == nil)
        #expect(stream.rawDifferenceScore == nil)
    }

    private func makeSession(id: UUID) throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: id,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 7_000)
        )
    }

    private func appendValue(
        payload: [UInt8],
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: "selected-target",
                serviceUUID: "A201",
                characteristicUUID: "2B10",
                origin: .subscriptionUpdate,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: Date(timeIntervalSince1970: 7_001)
        )
    }
}
