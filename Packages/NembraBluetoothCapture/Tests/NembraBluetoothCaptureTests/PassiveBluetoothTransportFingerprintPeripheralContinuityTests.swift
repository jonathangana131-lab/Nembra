import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothTransportFingerprintPeripheralContinuityTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test
    func unrelatedPeripheralDisconnectDoesNotFragmentSelectedFingerprint() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendServiceAndCharacteristic(
            peripheral: "target-a",
            characteristic: "2B10",
            sequence: 1,
            to: &session
        )
        try appendDisconnect(peripheral: "unrelated-b", sequence: 3, to: &session)
        try appendCharacteristic(
            peripheral: "target-a",
            characteristic: "2B11",
            sequence: 4,
            to: &session
        )

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(
            session,
            peripheralIdentifier: "target-a"
        ))
        let match = try #require(report.candidateMatches.first)

        #expect(match.family == .tuyaLegacyA201)
        #expect(match.strength == .expectedDataPathObserved)
        #expect(match.observedCharacteristicUUIDs == ["2B10", "2B11"])
    }

    @Test
    func selectedPeripheralDisconnectStillFragmentsFingerprintGeneration() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendServiceAndCharacteristic(
            peripheral: "target-a",
            characteristic: "2B10",
            sequence: 1,
            to: &session
        )
        try appendDisconnect(peripheral: "target-a", sequence: 3, to: &session)
        try appendServiceAndCharacteristic(
            peripheral: "target-a",
            characteristic: "2B11",
            sequence: 4,
            to: &session
        )

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(
            session,
            peripheralIdentifier: "target-a"
        ))
        let match = try #require(report.candidateMatches.first)

        #expect(match.family == .tuyaLegacyA201)
        #expect(match.strength == .characteristicFamilyObserved)
    }

    private func appendServiceAndCharacteristic(
        peripheral: String,
        characteristic: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: "A201",
                isPrimary: true
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
        try appendCharacteristic(
            peripheral: peripheral,
            characteristic: characteristic,
            sequence: sequence + 1,
            to: &session
        )
    }

    private func appendCharacteristic(
        peripheral: String,
        characteristic: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: "A201",
                characteristicUUID: characteristic,
                properties: [.read]
            )),
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
}
