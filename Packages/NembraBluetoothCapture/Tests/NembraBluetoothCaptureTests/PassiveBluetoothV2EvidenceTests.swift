import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth v2 evidence integration")
struct PassiveBluetoothV2EvidenceTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("structured disconnect prevents correlation across the continuity gap")
    func structuredDisconnectSplitsCorrelation() throws {
        let peripheral = "TARGET"
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)

        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 100,
            peripheral: peripheral,
            characteristic: "OLD",
            payload: [0xAA]
        )
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: .disconnected
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 150,
            receivedAtDate: .now
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(
                field: "Voltage",
                displayedValue: "39.8 V"
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 200,
            receivedAtDate: .now
        )
        try appendValue(
            to: &session,
            sequence: 4,
            uptime: 250,
            peripheral: peripheral,
            characteristic: "NEW",
            payload: [0xBB]
        )

        let window = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            lookbackNanoseconds: 1_000,
            lookaheadNanoseconds: 1_000
        ).first)
        #expect(window.candidates.map(\.characteristicUUID) == ["NEW"])
    }

    @Test("connection identity alone never manufactures GATT topology")
    func connectionOnlyIsNotGATTEvidence() throws {
        let peripheral = "TARGET"
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: .connected
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let conservative = PassiveBluetoothTransportFingerprint.analyze(session)
        #expect(conservative.peripheralIdentifier.isEmpty)
        #expect(conservative.observedServiceUUIDs.isEmpty)
        #expect(conservative.characteristicUUIDsByService.isEmpty)
        #expect(conservative.candidateMatches.isEmpty)

        let all = PassiveBluetoothTransportFingerprint.analyzeAll(session)
        #expect(all.map(\.peripheralIdentifier) == [peripheral])
        #expect(all[0].observedServiceUUIDs.isEmpty)
    }

    @Test("subscription evidence contributes only its explicit GATT path")
    func subscriptionSeedsExactPath() throws {
        let peripheral = "TARGET"
        let characteristic = "00000002-0000-1001-8001-00805F9B07D0"
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try session.append(
            .subscription(try PassiveBluetoothSubscriptionObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: "FD50",
                characteristicUUID: characteristic,
                requestedEnabled: true,
                resultingIsNotifying: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let report = PassiveBluetoothTransportFingerprint.analyze(session)
        #expect(report.peripheralIdentifier == peripheral)
        #expect(report.observedServiceUUIDs == ["FD50"])
        #expect(report.characteristicUUIDsByService["FD50"] == [characteristic])
        let match = try #require(report.candidateMatches.first)
        #expect(match.family == .tuyaModernFD50)
        #expect(match.strength == .characteristicFamilyObserved)
        #expect(match.observedCharacteristicUUIDs == [characteristic])
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        peripheral: String,
        characteristic: String,
        payload: [UInt8]
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheral,
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
