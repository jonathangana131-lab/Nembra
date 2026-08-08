import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth -> Tuya bridge continuity contract")
struct PassiveBluetoothTuyaCandidateBridgeContinuityContractTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("bridge preserves every capture event that NembraCore declares a raw-byte continuity break")
    func unrelatedStructuredDisconnectAdvancesCandidateContinuity() throws {
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "71000000-0000-0000-0000-000000000007")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [0, 2, 0x10, 0xAA],
            sequence: 1,
            uptime: 100
        )
        try appendDisconnect(
            to: &session,
            peripheral: "noise-B",
            sequence: 2,
            uptime: 110
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [1, 0xBB],
            sequence: 3,
            uptime: 200
        )

        let disconnectRecord = try #require(session.records.first { $0.sequenceNumber == 2 })
        #expect(disconnectRecord.event.breaksByteContinuity)

        let analyses = try PassiveBluetoothTuyaCandidateBridge.analyze(
            session: session,
            peripheralIdentifier: "target-A",
            policy: try TuyaCandidateFragmentReassemblyPolicy(
                maximumEncryptedMessageBytes: 64,
                maximumFragmentCount: 8
            )
        )
        let analysis = try #require(analyses.first)

        #expect(analysis.transcript.fragments.map(\.captureSequenceNumber) == [1, 3])
        #expect(analysis.transcript.fragments.map(\.observation.continuityGeneration) == [0, 1])
        #expect(analysis.events == [
            .incompleteAtBoundary(
                startObservationIndex: 0,
                lastAcceptedObservationIndex: 0,
                nextObservationIndex: 1,
                boundary: .continuityGenerationChanged
            ),
            .rejectedCandidate(
                startObservationIndex: 1,
                lastAcceptedObservationIndex: nil,
                failingObservationIndex: 1,
                error: .unexpectedPacketIndex(expected: 0, actual: 1)
            )
        ])
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
