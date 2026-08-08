import Foundation
import Testing
@testable import NembraCore

@Suite("Ride transport-gap connection states")
struct RideTransportGapConnectionStateTests {
    private func policy() throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: 0,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: 100,
            maximumSpeedSampleAgeNanoseconds: 1_000
        )
    }

    private func observation(
        uptime: UInt64,
        connection: VehicleConnectionState,
        speedKPH: Double? = nil
    ) throws -> RideObservation {
        let date = Date(timeIntervalSince1970: 1_700_200_000 + Double(uptime) / 1_000_000_000)
        let speed = try speedKPH.map {
            try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: $0 / 3.6,
                receivedAtUptimeNanoseconds: uptime,
                receivedAtDate: date
            )
        }
        return try RideObservation(
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: date,
            connection: connection,
            speedSample: speed
        )
    }

    @Test("every non-connected vehicle state is observed transport-gap evidence")
    func nonConnectedStatesAreObserved() throws {
        let nonConnectedStates: [VehicleConnectionState] = [
            .disconnected,
            .connecting,
            .reconnecting
        ]

        for state in nonConnectedStates {
            var engine = RideEngine(policy: try policy())
            _ = try engine.ingest(
                observation(uptime: 1_000, connection: .connected, speedKPH: 8)
            )
            _ = try engine.ingest(
                observation(uptime: 2_000, connection: state)
            )

            let optionalCheckpoint = try engine.recoveryCheckpoint(
                checkpointedAtDate: Date(timeIntervalSince1970: 1_700_200_100)
            )
            let checkpoint = try #require(optionalCheckpoint)
            #expect(checkpoint.persistedPhase == .temporarilyDisconnected)
            #expect(checkpoint.transportGapEvidence == .observed)
        }
    }
}
