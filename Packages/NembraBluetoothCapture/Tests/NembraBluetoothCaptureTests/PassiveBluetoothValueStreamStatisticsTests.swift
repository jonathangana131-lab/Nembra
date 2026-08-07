import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth raw value stream statistics")
struct PassiveBluetoothValueStreamStatisticsTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("callback intervals payload variation duplicates and origins are summarized without decoding")
    func streamStatistics() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 1_000_000_000, payload: [0x10], origin: .readResponse)
        try appendValue(to: &session, sequence: 2, uptime: 1_100_000_000, payload: [0x10], origin: .subscriptionUpdate)
        try appendValue(to: &session, sequence: 3, uptime: 1_300_000_000, payload: [0x11, 0x12], origin: .subscriptionUpdate)
        try appendValue(to: &session, sequence: 4, uptime: 1_600_000_000, payload: [0x13], origin: .subscriptionUpdate)

        let stats = try #require(PassiveBluetoothValueStreamAnalysis.summarize(session).first)
        #expect(stats.sampleCount == 4)
        #expect(stats.continuitySegmentCount == 1)
        #expect(stats.origins == [.readResponse, .subscriptionUpdate])
        #expect(stats.minimumPayloadByteCount == 1)
        #expect(stats.maximumPayloadByteCount == 2)
        #expect(stats.uniquePayloadCount == 3)
        #expect(stats.consecutiveDuplicatePayloadCount == 1)
        #expect(stats.firstReceiptUptimeNanoseconds == 1_000_000_000)
        #expect(stats.lastReceiptUptimeNanoseconds == 1_600_000_000)
        #expect(stats.callbackIntervalCount == 3)
        try expectApproximately(stats.minimumCallbackIntervalSeconds, 0.1)
        try expectApproximately(stats.medianCallbackIntervalSeconds, 0.2)
        try expectApproximately(stats.meanCallbackIntervalSeconds, 0.2)
        try expectApproximately(stats.maximumCallbackIntervalSeconds, 0.3)
    }

    @Test("interruptions split cadence so a capture gap is never averaged into callback timing")
    func interruptionBreaksCadence() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 100, payload: [0x01])
        try appendValue(to: &session, sequence: 2, uptime: 200, payload: [0x02])
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "observer gap")),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 300,
            receivedAtDate: .now
        )
        try appendValue(to: &session, sequence: 4, uptime: 10_000, payload: [0x03])
        try appendValue(to: &session, sequence: 5, uptime: 10_400, payload: [0x04])

        let stats = try #require(PassiveBluetoothValueStreamAnalysis.summarize(session).first)
        #expect(stats.sampleCount == 4)
        #expect(stats.continuitySegmentCount == 2)
        #expect(stats.callbackIntervalCount == 2)
        try expectApproximately(stats.minimumCallbackIntervalSeconds, 0.0000001, tolerance: 1e-15)
        try expectApproximately(stats.maximumCallbackIntervalSeconds, 0.0000004, tolerance: 1e-15)
        try expectApproximately(stats.meanCallbackIntervalSeconds, 0.00000025, tolerance: 1e-15)
    }

    @Test("same-peripheral structured disconnect splits cadence")
    func structuredDisconnectBreaksCadence() throws {
        let peripheral = "target-a"
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 100, payload: [0x01], peripheral: peripheral)
        try appendValue(to: &session, sequence: 2, uptime: 200, payload: [0x02], peripheral: peripheral)
        try appendDisconnect(to: &session, sequence: 3, uptime: 300, peripheral: peripheral)
        try appendValue(to: &session, sequence: 4, uptime: 10_000, payload: [0x03], peripheral: peripheral)
        try appendValue(to: &session, sequence: 5, uptime: 10_400, payload: [0x04], peripheral: peripheral)

        let stats = try #require(PassiveBluetoothValueStreamAnalysis.summarize(session).first)
        #expect(stats.continuitySegmentCount == 2)
        #expect(stats.callbackIntervalCount == 2)
        try expectApproximately(stats.minimumCallbackIntervalSeconds, 0.0000001, tolerance: 1e-15)
        try expectApproximately(stats.maximumCallbackIntervalSeconds, 0.0000004, tolerance: 1e-15)
    }

    @Test("unrelated peripheral disconnect does not fragment target cadence")
    func unrelatedDisconnectDoesNotBreakCadence() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 100, payload: [0x01], peripheral: "target-a")
        try appendDisconnect(to: &session, sequence: 2, uptime: 150, peripheral: "unrelated-b")
        try appendValue(to: &session, sequence: 3, uptime: 400, payload: [0x02], peripheral: "target-a")

        let stats = try #require(PassiveBluetoothValueStreamAnalysis.summarize(session).first)
        #expect(stats.key.peripheralIdentifier == "target-a")
        #expect(stats.continuitySegmentCount == 1)
        #expect(stats.callbackIntervalCount == 1)
        try expectApproximately(stats.meanCallbackIntervalSeconds, 0.0000003, tolerance: 1e-15)
    }

    @Test("different characteristics remain independent streams and sort deterministically")
    func streamSeparation() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 1, service: "FD50", characteristic: "B", payload: [0x01])
        try appendValue(to: &session, sequence: 2, uptime: 2, service: "A201", characteristic: "A", payload: [0x02])

        let stats = PassiveBluetoothValueStreamAnalysis.summarize(session)
        #expect(stats.count == 2)
        #expect(stats.map(\.key.serviceUUID) == ["A201", "FD50"])
        #expect(stats.allSatisfy { $0.sampleCount == 1 && $0.callbackIntervalCount == 0 })
        #expect(stats.allSatisfy { $0.meanCallbackIntervalSeconds == nil })
    }

    @Test("non-value evidence does not manufacture a stream")
    func noValueEvidence() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Voltage", displayedValue: "39.8 V")),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        #expect(PassiveBluetoothValueStreamAnalysis.summarize(session).isEmpty)
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        service: String = "TEST",
        characteristic: String = "VALUE",
        payload: [UInt8],
        origin: PassiveBluetoothValueOrigin = .subscriptionUpdate,
        peripheral: String = "physical-es80-placeholder"
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
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }

    private func appendDisconnect(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        peripheral: String
    ) throws {
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: .disconnected
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }

    private func expectApproximately(
        _ actual: Double?,
        _ expected: Double,
        tolerance: Double = 1e-12
    ) throws {
        let actual = try #require(actual)
        #expect(abs(actual - expected) <= tolerance)
    }
}
