import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth -> Tuya bridge target continuity")
struct PassiveBluetoothTuyaCandidateBridgeTargetContinuityTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("unrelated peripheral disconnect does not manufacture a target stream gap")
    func unrelatedDisconnectDoesNotAdvanceTargetContinuity() throws {
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "72000000-0000-0000-0000-000000000001")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        try appendValue(to: &session, peripheral: "target-A", payload: [0, 2, 0x10, 0xAA], sequence: 1, uptime: 100)
        try appendDisconnect(to: &session, peripheral: "noise-B", sequence: 2, uptime: 110)
        try appendValue(to: &session, peripheral: "target-A", payload: [1, 0xBB], sequence: 3, uptime: 200)

        let transcript = try #require(
            PassiveBluetoothTuyaCandidateBridge.transcripts(
                in: session,
                peripheralIdentifier: "target-A"
            ).first
        )

        #expect(transcript.fragments.map(\.captureSequenceNumber) == [1, 3])
        #expect(transcript.fragments.map(\.observation.continuityGeneration) == [0, 0])
    }

    @Test("selected target disconnect advances target stream continuity")
    func targetDisconnectAdvancesTargetContinuity() throws {
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "72000000-0000-0000-0000-000000000002")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        try appendValue(to: &session, peripheral: "target-A", payload: [0, 2, 0x10, 0xAA], sequence: 1, uptime: 100)
        try appendDisconnect(to: &session, peripheral: "target-A", sequence: 2, uptime: 110)
        try appendValue(to: &session, peripheral: "target-A", payload: [1, 0xBB], sequence: 3, uptime: 200)

        let transcript = try #require(
            PassiveBluetoothTuyaCandidateBridge.transcripts(
                in: session,
                peripheralIdentifier: "target-A"
            ).first
        )

        #expect(transcript.fragments.map(\.captureSequenceNumber) == [1, 3])
        #expect(transcript.fragments.map(\.observation.continuityGeneration) == [0, 1])
    }

    @Test("global interruption advances target stream continuity")
    func globalInterruptionAdvancesTargetContinuity() throws {
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "72000000-0000-0000-0000-000000000003")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        try appendValue(to: &session, peripheral: "target-A", payload: [0, 2, 0x10, 0xAA], sequence: 1, uptime: 100)
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "foreground integrity lost")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 110,
            receivedAtDate: Date(timeIntervalSince1970: 2)
        )
        try appendValue(to: &session, peripheral: "target-A", payload: [1, 0xBB], sequence: 3, uptime: 200)

        let transcript = try #require(
            PassiveBluetoothTuyaCandidateBridge.transcripts(
                in: session,
                peripheralIdentifier: "target-A"
            ).first
        )

        #expect(transcript.fragments.map(\.observation.continuityGeneration) == [0, 1])
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        peripheral: String,
        payload: [UInt8],
        sequence: UInt64,
        uptime: UInt64
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: "A201",
                characteristicUUID: "2B10",
                origin: .notification,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }

    private func appendDisconnect(
        to session: inout PassiveBluetoothCaptureSession,
        peripheral: String,
        sequence: UInt64,
        uptime: UInt64
    ) throws {
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: .disconnected
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }
}
