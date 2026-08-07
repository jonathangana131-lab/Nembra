import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth solicited-service fingerprint truth")
struct PassiveBluetoothSolicitedServiceFingerprintTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("solicited service UUID does not imply the peripheral hosts that service")
    func solicitedServiceDoesNotCreateCandidate() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: identity,
            startedAt: .now
        )
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "test",
                solicitedServiceUUIDs: ["FD50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(
            session,
            peripheralIdentifier: "test"
        ))

        #expect(report.observedServiceUUIDs.isEmpty)
        #expect(report.characteristicUUIDsByService.isEmpty)
        #expect(report.candidateMatches.isEmpty)
    }

    @Test("solicited UUID remains raw evidence while an actually advertised service can match")
    func solicitationStaysSeparateFromAdvertisedServiceEvidence() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: identity,
            startedAt: .now
        )
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "test",
                serviceUUIDs: ["A201"],
                solicitedServiceUUIDs: ["FD50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(
            session,
            peripheralIdentifier: "test"
        ))

        #expect(report.observedServiceUUIDs == ["A201"])
        #expect(report.candidateMatches.map(\.family) == [.tuyaLegacyA201])
        #expect(report.candidateMatches.map(\.strength) == [.serviceObserved])

        guard case let .advertisement(rawAdvertisement) = session.records[0].event else {
            Issue.record("expected raw advertisement evidence")
            return
        }
        #expect(rawAdvertisement.solicitedServiceUUIDs == ["FD50"])
    }
}
