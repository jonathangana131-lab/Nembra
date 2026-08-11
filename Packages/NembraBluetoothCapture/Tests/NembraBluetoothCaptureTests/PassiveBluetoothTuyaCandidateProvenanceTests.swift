import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth -> Tuya candidate provenance authority")
struct PassiveBluetoothTuyaCandidateProvenanceTests {
    @Test("caller-constructed validated sessions remain software provenance only")
    func callerConstructedSessionCannotBecomePhysicalAuthority() throws {
        let sessionID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
        let identity = VehicleIdentity(
            manufacturer: "caller-supplied",
            model: "caller-supplied",
            displayName: "Caller-supplied identity",
            protocolFamily: "unknown"
        )
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_234)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: "caller-target",
                serviceUUID: "A201",
                characteristicUUID: "2B10",
                origin: .notification,
                payload: Data([0, 1, 0x10, 0xAA])
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1_235)
        )

        let transcript = try #require(
            PassiveBluetoothTuyaCandidateBridge.transcripts(
                in: session,
                peripheralIdentifier: "caller-target"
            ).first
        )

        #expect(transcript.captureContext.provenanceClass == .validatedSoftwareSessionOnly)
        #expect(transcript.captureContext.sessionID == sessionID)
        #expect(transcript.captureContext.vehicleIdentity == identity)
        #expect(transcript.captureContext.peripheralIdentifier == "caller-target")
    }
}
