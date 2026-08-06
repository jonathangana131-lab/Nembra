import Foundation
import Testing
@testable import NembraCore

@Suite("Ride transport-gap provenance")
struct RideTransportGapEvidenceTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func policy(
        endingDuration: UInt64 = 100
    ) throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: 0,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: endingDuration,
            maximumSpeedSampleAgeNanoseconds: 1_000
        )
    }

    private func observation(
        _ uptime: UInt64,
        connection: VehicleConnectionState = .connected,
        speedKPH: Double? = nil,
        odometer: Double? = nil
    ) throws -> RideObservation {
        let date = epoch.addingTimeInterval(Double(uptime) / 1_000_000_000)
        let sample = try speedKPH.map {
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
            speedSample: sample,
            odometerKilometers: odometer
        )
    }

    private func checkpoint(
        phase: RideCheckpointPhase = .active,
        gapEvidence: RideTransportGapEvidence = .unknown
    ) throws -> RideRecoveryCheckpoint {
        try RideRecoveryCheckpoint(
            sessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            persistedPhase: phase,
            phaseBeganAtDate: phase == .active ? nil : epoch.addingTimeInterval(2),
            lastObservedAtDate: epoch.addingTimeInterval(3),
            checkpointedAtDate: epoch.addingTimeInterval(4),
            startingOdometerKilometers: 100,
            latestOdometerKilometers: 100.5,
            accumulatedGPSDistanceMeters: 500,
            transportGapEvidence: gapEvidence
        )
    }

    private func completedEvidence(
        gapEvidence: RideTransportGapEvidence
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(1),
            endedAtDate: epoch.addingTimeInterval(60),
            startingOdometerKilometers: 100,
            endingOdometerKilometers: 101,
            qualityScreenedGPSDistanceMeters: 1_500,
            continuity: .uninterruptedProcess,
            transportGapEvidence: gapEvidence
        )
    }

    private func completedRide(
        from update: RideEngineUpdate
    ) throws -> CompletedRideEvidence {
        for event in update.events {
            if case let .rideEnded(evidence) = event {
                return evidence
            }
        }
        Issue.record("expected completed ride evidence")
        throw RideCheckpointError.corruptedCheckpoint
    }

    private func removeKey(
        _ key: String,
        fromNestedPath path: [String],
        in data: Data
    ) throws -> Data {
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        func removing(
            key: String,
            path: ArraySlice<String>,
            object: inout [String: Any]
        ) throws {
            guard let head = path.first else {
                object.removeValue(forKey: key)
                return
            }
            var child = try #require(object[head] as? [String: Any])
            try removing(key: key, path: path.dropFirst(), object: &child)
            object[head] = child
        }

        try removing(key: key, path: path[...], object: &root)
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test("fresh confirmed ride begins with known no-observed-gap evidence")
    func freshRideStartsNoneObserved() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 100))

        let checkpoint = try #require(
            engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(2))
        )
        #expect(checkpoint.transportGapEvidence == .noneObserved)
    }

    @Test("ride completing without a scooter disconnect preserves none-observed provenance")
    func uninterruptedCompletionPreservesNoneObserved() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        _ = try engine.ingest(observation(2_000, speedKPH: 0, odometer: 100.1))
        let ended = try engine.ingest(observation(2_100, speedKPH: 0, odometer: 100.1))

        let evidence = try completedRide(from: ended)
        #expect(evidence.transportGapEvidence == .noneObserved)
    }

    @Test("observed disconnect survives reconnect and completion")
    func observedDisconnectIsSticky() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        _ = try engine.ingest(
            observation(1_500, connection: .disconnected, odometer: 100.05)
        )

        let disconnectedCheckpoint = try #require(
            engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(2))
        )
        #expect(disconnectedCheckpoint.transportGapEvidence == .observed)

        _ = try engine.ingest(observation(2_000, speedKPH: 8, odometer: 100.1))
        _ = try engine.ingest(observation(3_000, speedKPH: 0, odometer: 100.1))
        let ended = try engine.ingest(observation(3_100, speedKPH: 0, odometer: 100.1))

        let evidence = try completedRide(from: ended)
        #expect(evidence.transportGapEvidence == .observed)
    }

    @Test("disconnect during ending candidate is durable observed evidence")
    func endingCandidateDisconnectIsObserved() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, speedKPH: 8))
        _ = try engine.ingest(observation(2_000, speedKPH: 0))
        _ = try engine.ingest(observation(2_050, connection: .disconnected))

        let checkpoint = try #require(
            engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(3))
        )
        #expect(checkpoint.persistedPhase == .temporarilyDisconnected)
        #expect(checkpoint.transportGapEvidence == .observed)
    }

    @Test("process recovery downgrades unproven none-observed evidence to unknown")
    func processRecoveryDowngradesNoneObserved() throws {
        let original = try checkpoint(gapEvidence: .noneObserved)
        var engine = try RideEngine.restoring(
            from: original,
            policy: try policy(),
            recoveredAtUptimeNanoseconds: 10_000,
            recoveredAtDate: epoch.addingTimeInterval(10)
        )

        let immediatelyRecovered = try #require(
            engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(11))
        )
        #expect(immediatelyRecovered.transportGapEvidence == .unknown)

        _ = try engine.ingest(observation(11_000, speedKPH: 8, odometer: 100.6))
        let resumed = try #require(
            engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(12))
        )
        #expect(resumed.transportGapEvidence == .unknown)
    }

    @Test("directly observed gap survives process recovery")
    func observedGapSurvivesRecovery() throws {
        let original = try checkpoint(gapEvidence: .observed)
        let engine = try RideEngine.restoring(
            from: original,
            policy: try policy(),
            recoveredAtUptimeNanoseconds: 10_000,
            recoveredAtDate: epoch.addingTimeInterval(10)
        )

        let recovered = try #require(
            engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(11))
        )
        #expect(recovered.transportGapEvidence == .observed)
    }

    @Test("fresh disconnected observation after recovery promotes unknown to observed")
    func postRecoveryDisconnectBecomesObserved() throws {
        let original = try checkpoint(gapEvidence: .unknown)
        var engine = try RideEngine.restoring(
            from: original,
            policy: try policy(),
            recoveredAtUptimeNanoseconds: 10_000,
            recoveredAtDate: epoch.addingTimeInterval(10)
        )

        _ = try engine.ingest(
            observation(11_000, connection: .disconnected, odometer: 100.5)
        )
        let checkpoint = try #require(
            engine.recoveryCheckpoint(checkpointedAtDate: epoch.addingTimeInterval(12))
        )
        #expect(checkpoint.transportGapEvidence == .observed)
    }

    @Test("legacy completed evidence without transport field decodes as unknown")
    func legacyCompletedEvidenceDecodesUnknown() throws {
        let encoder = JSONEncoder()
        let current = try completedEvidence(gapEvidence: .observed)
        let legacyData = try removeKey(
            "transportGapEvidence",
            fromNestedPath: [],
            in: encoder.encode(current)
        )

        let decoded = try JSONDecoder().decode(CompletedRideEvidence.self, from: legacyData)
        #expect(decoded.transportGapEvidence == .unknown)
    }

    @Test("legacy recovery checkpoint without transport field decodes as unknown")
    func legacyRecoveryCheckpointDecodesUnknown() throws {
        let encoder = JSONEncoder()
        let current = try checkpoint(gapEvidence: .observed)
        let legacyData = try removeKey(
            "transportGapEvidence",
            fromNestedPath: [],
            in: encoder.encode(current)
        )

        let decoded = try JSONDecoder().decode(RideRecoveryCheckpoint.self, from: legacyData)
        #expect(decoded.transportGapEvidence == .unknown)
    }

    @Test("v1 journal loads as unknown and next save upgrades to v2")
    func legacyJournalMigratesOnNextWrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-gap-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacyCheckpoint = try checkpoint(gapEvidence: .observed)
        let envelope = AtomicRideCheckpointStore.Envelope(
            schemaVersion: AtomicRideCheckpointStore.legacySchemaVersion,
            generation: 7,
            checkpoint: .inProgress(legacyCheckpoint)
        )
        let encoder = JSONEncoder()
        var legacyData = try encoder.encode(envelope)
        legacyData = try removeKey(
            "transportGapEvidence",
            fromNestedPath: ["checkpoint", "inProgress"],
            in: legacyData
        )
        let slotA = directory.appendingPathComponent(AtomicRideCheckpointStore.slotAFileName)
        try legacyData.write(to: slotA)

        let store = AtomicRideCheckpointStore(directoryURL: directory)
        guard case let .inProgress(loaded)? = try await store.load() else {
            Issue.record("expected migrated in-progress v1 checkpoint")
            return
        }
        #expect(loaded.transportGapEvidence == .unknown)

        let current = try checkpoint(gapEvidence: .observed)
        try await store.save(.inProgress(current))
        #expect(try await store.load() == .inProgress(current))

        let slotB = directory.appendingPathComponent(AtomicRideCheckpointStore.slotBFileName)
        let writtenObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: slotB)) as? [String: Any]
        )
        #expect(writtenObject["schemaVersion"] as? Int == AtomicRideCheckpointStore.schemaVersion)
        #expect(AtomicRideCheckpointStore.schemaVersion == 2)
    }

    @Test("temporary-disconnect checkpoint cannot claim no gap was observed")
    func contradictoryDisconnectedCheckpointRejected() throws {
        #expect(throws: RideCheckpointError.invalidCheckpoint) {
            _ = try checkpoint(
                phase: .temporarilyDisconnected,
                gapEvidence: .noneObserved
            )
        }
    }
}
