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

    @Test("interruptions split cadence so a disconnect gap is never averaged into callback timing")
    func interruptionBreaksCadence() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 100, payload: [0x01])
        try appendValue(to: &session, sequence: 2, uptime: 200, payload: [0x02])
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "disconnect")),
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

    @Test("structured disconnect uses the same byte-continuity boundary as an interruption")
    func structuredDisconnectBreaksCadence() throws {
        let peripheral = "physical-es80-placeholder"
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 100, payload: [0x01])
        try appendValue(to: &session, sequence: 2, uptime: 200, payload: [0x02])
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: .disconnected
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 300,
            receivedAtDate: .now
        )
        try appendValue(to: &session, sequence: 4, uptime: 10_000, payload: [0x03])
        try appendValue(to: &session, sequence: 5, uptime: 10_400, payload: [0x04])

        let stats = try #require(PassiveBluetoothValueStreamAnalysis.summarize(session).first)
        #expect(stats.continuitySegmentCount == 2)
        #expect(stats.callbackIntervalCount == 2)
        try expectApproximately(stats.minimumCallbackIntervalSeconds, 0.0000001, tolerance: 1e-15)
        try expectApproximately(stats.maximumCallbackIntervalSeconds, 0.0000004, tolerance: 1e-15)
    }

    @Test("notification pause and resume splits only the affected characteristic cadence")
    func notificationStateTransitionIsPathLocal() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 100,
            characteristic: "A",
            payload: [0x01]
        )
        try appendValue(
            to: &session,
            sequence: 2,
            uptime: 150,
            characteristic: "B",
            payload: [0x10]
        )
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 200,
            characteristic: "A",
            payload: [0x02]
        )
        try appendValue(
            to: &session,
            sequence: 4,
            uptime: 250,
            characteristic: "B",
            payload: [0x11]
        )
        try appendSubscription(
            to: &session,
            sequence: 5,
            uptime: 300,
            characteristic: "A",
            requestedEnabled: false,
            resultingIsNotifying: false
        )
        try appendValue(
            to: &session,
            sequence: 6,
            uptime: 400,
            characteristic: "B",
            payload: [0x12]
        )
        try appendSubscription(
            to: &session,
            sequence: 7,
            uptime: 500,
            characteristic: "A",
            requestedEnabled: true,
            resultingIsNotifying: true
        )
        try appendValue(
            to: &session,
            sequence: 8,
            uptime: 10_000,
            characteristic: "A",
            payload: [0x03]
        )
        try appendValue(
            to: &session,
            sequence: 9,
            uptime: 10_100,
            characteristic: "A",
            payload: [0x04]
        )
        try appendValue(
            to: &session,
            sequence: 10,
            uptime: 10_200,
            characteristic: "B",
            payload: [0x13]
        )

        let stats = PassiveBluetoothValueStreamAnalysis.summarize(session)
        let a = try #require(stats.first { $0.key.characteristicUUID == "A" })
        let b = try #require(stats.first { $0.key.characteristicUUID == "B" })

        #expect(a.sampleCount == 4)
        #expect(a.continuitySegmentCount == 2)
        #expect(a.callbackIntervalCount == 2)
        try expectApproximately(a.minimumCallbackIntervalSeconds, 0.0000001, tolerance: 1e-15)
        try expectApproximately(a.maximumCallbackIntervalSeconds, 0.0000001, tolerance: 1e-15)

        #expect(b.sampleCount == 4)
        #expect(b.continuitySegmentCount == 1)
        #expect(b.callbackIntervalCount == 3)
        try expectApproximately(b.maximumCallbackIntervalSeconds, 0.0000098, tolerance: 1e-15)
    }

    @Test("first observed enabled state does not manufacture a cadence break")
    func initialEnabledStateRemainsContinuous() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 100, payload: [0x01])
        try appendSubscription(
            to: &session,
            sequence: 2,
            uptime: 150,
            requestedEnabled: true,
            resultingIsNotifying: true
        )
        try appendValue(to: &session, sequence: 3, uptime: 200, payload: [0x02])

        let stats = try #require(PassiveBluetoothValueStreamAnalysis.summarize(session).first)
        #expect(stats.continuitySegmentCount == 1)
        #expect(stats.callbackIntervalCount == 1)
        try expectApproximately(stats.maximumCallbackIntervalSeconds, 0.0000001, tolerance: 1e-15)
    }

    @Test("different characteristics remain independent streams and sort deterministically")
    func streamSeparation() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 1,
            service: "FD50",
            characteristic: "B",
            payload: [0x01]
        )
        try appendValue(
            to: &session,
            sequence: 2,
            uptime: 2,
            service: "A201",
            characteristic: "A",
            payload: [0x02]
        )

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
        origin: PassiveBluetoothValueOrigin = .subscriptionUpdate
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: "physical-es80-placeholder",
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

    private func appendSubscription(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        service: String = "TEST",
        characteristic: String = "VALUE",
        requestedEnabled: Bool?,
        resultingIsNotifying: Bool
    ) throws {
        try session.append(
            .subscription(try PassiveBluetoothSubscriptionObservation(
                peripheralIdentifier: "physical-es80-placeholder",
                serviceUUID: service,
                characteristicUUID: characteristic,
                requestedEnabled: requestedEnabled,
                resultingIsNotifying: resultingIsNotifying
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
