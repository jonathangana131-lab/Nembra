import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth capture-wide continuity")
struct PassiveBluetoothCaptureWideContinuityTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("unrelated disconnect cannot combine transport fingerprint evidence across a raw gap")
    func unrelatedDisconnectFencesTransportFingerprintStrength() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: identity,
            startedAt: .now
        )
        try appendService("A201", sequence: 1, to: &session)
        try appendCharacteristic("2B10", sequence: 2, to: &session)
        try appendDisconnect(peripheral: "unrelated-b", sequence: 3, to: &session)
        try appendService("A201", sequence: 4, to: &session)
        try appendCharacteristic("2B11", sequence: 5, to: &session)

        let report = try #require(
            PassiveBluetoothTransportFingerprint.analyze(
                session,
                peripheralIdentifier: "target-a"
            )
        )

        #expect(report.characteristicUUIDsByService["A201"] == ["2B10", "2B11"])
        let match = try #require(report.candidateMatches.first)
        #expect(match.family == .tuyaLegacyA201)
        #expect(match.strength == .characteristicFamilyObserved)
        #expect(match.observedCharacteristicUUIDs != ["2B10", "2B11"])
    }

    private func appendService(
        _ uuid: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: "target-a",
                serviceUUID: uuid,
                isPrimary: true
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }

    private func appendCharacteristic(
        _ uuid: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: "target-a",
                serviceUUID: "A201",
                characteristicUUID: uuid,
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
