import Foundation
import NembraBluetoothCapture
import NembraCore
import Testing

@Suite("Passive Bluetooth Tuya candidate provenance authority")
struct PassiveBluetoothTuyaCandidateProvenanceAuthorityTests {
    @Test("caller-constructed validated session never upgrades into artifact authority")
    func callerConstructedSessionStaysSoftwareAuthority() throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000127")!
        let vehicle = VehicleIdentity(
            manufacturer: "Research",
            model: "Synthetic",
            displayName: "Caller-constructed session",
            protocolFamily: "Unverified"
        )
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: vehicle,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let value = try PassiveBluetoothValueObservation(
            peripheralIdentifier: "caller-peripheral",
            serviceUUID: "FFF0",
            characteristicUUID: "FFF1",
            origin: .notification,
            payload: Data([0x01])
        )
        try session.append(
            .value(value),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_001)
        )

        let transcripts = try PassiveBluetoothTuyaCandidateBridge.transcripts(
            in: session,
            peripheralIdentifier: "caller-peripheral"
        )
        let transcript = try #require(transcripts.first)

        #expect(transcript.captureContext.sessionID == sessionID)
        #expect(transcript.captureContext.vehicleIdentity == vehicle)
        #expect(
            transcript.captureContext.sessionProvenanceAuthority == .validatedSoftwareSession
        )
    }
}
