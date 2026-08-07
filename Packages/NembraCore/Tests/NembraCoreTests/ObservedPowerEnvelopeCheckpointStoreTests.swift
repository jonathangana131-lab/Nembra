import Foundation
import Testing
@testable import NembraCore

@Suite("Observed power envelope checkpoint journal")
struct ObservedPowerEnvelopeCheckpointStoreTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-observed-power-envelope-store-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func policy(
        headroom: Double = 0.05,
        hysteresis: Double = 0.05
    ) throws -> ObservedPowerEnvelopePolicy {
        try ObservedPowerEnvelopePolicy(
            windowCapacity: 6,
            minimumLearningSampleCount: 3,
            minimumUpperBandSupportCount: 2,
            upperPercentile: 0.8,
            upperBandFraction: 0.15,
            headroomFraction: headroom,
            upwardHysteresisFraction: hysteresis
        )
    }

    private func checkpoint(
        vehicle: String = "sim-es80-store",
        mode: String? = "sport",
        watts: [Double] = [400, 420, 410],
        policy suppliedPolicy: ObservedPowerEnvelopePolicy? = nil
    ) throws -> ObservedPowerEnvelopeCalibrationCheckpoint {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: vehicle,
            confirmedModeKey: mode
        )
        let chosenPolicy = try suppliedPolicy ?? policy()
        var learner = try ObservedPowerEnvelopeLearner.simulatorQA(
            scope: scope,
            policy: chosenPolicy
        )
        for (index, watts) in watts.enumerated() {
            _ = learner.record(.simulatorQA(
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: UInt64(index + 1) * 1_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        return try ObservedPowerEnvelopeCalibrationCheckpoint.simulatorQA(from: learner)
    }

    private func verifiedLearner(
        vehicle: String = "physical-es80-store",
        mode: String? = "sport",
        watts: [Double] = [500, 540, 520],
        policy suppliedPolicy: ObservedPowerEnvelopePolicy? = nil
    ) throws -> (ObservedPowerEnvelopeScope, ObservedPowerEnvelopePolicy, ObservedPowerEnvelopeLearner) {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: vehicle,
            confirmedModeKey: mode
        )
        let chosenPolicy = try suppliedPolicy ?? policy()
        var learner = try ObservedPowerEnvelopeLearner.verifiedVehicleMeasurements(
            scope: scope,
            policy: chosenPolicy
        )
        for (index, watts) in watts.enumerated() {
            _ = learner.record(.verifiedVehicleMeasurement(
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: UInt64(index + 1),
                observedAtUptimeNanoseconds: UInt64(index + 1) * 9_000,
                learningEligibility: .eligibleForEnvelopeLearning
            ))
        }
        return (scope, chosenPolicy, learner)
    }

    private func slotURL(_ fileName: String, in directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func encode(
        _ envelope: AtomicObservedPowerEnvelopeCheckpointStore.Envelope
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    private func decodeEnvelope(at url: URL) throws -> AtomicObservedPowerEnvelopeCheckpointStore.Envelope {
        try JSONDecoder().decode(
            AtomicObservedPowerEnvelopeCheckpointStore.Envelope.self,
            from: Data(contentsOf: url)
        )
    }

    private func physicalLookingJSON(
        from simulator: ObservedPowerEnvelopeCalibrationCheckpoint
    ) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(simulator)) as? [String: Any]
        )
        object["identityAuthority"] = "verifiedVehicleIdentity"
        object["evidenceAuthority"] = "verifiedVehicleMeasurement"
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test("two-slot journal round-trips and advances only for a qualified stronger calibration")
    func roundTripQualifiedProgression() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let first = try checkpoint(watts: [400, 420, 410])
        let stronger = try checkpoint(watts: [600, 630, 620])

        #expect(try await store.saveSimulatorQA(first) == .stored(generation: 1))
        #expect(try await store.saveSimulatorQA(stronger) == .stored(generation: 2))
        #expect(try await store.loadSimulatorQA() == stronger)
        #expect(FileManager.default.fileExists(
            atPath: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir).path
        ))
    }

    @Test("equal lower and sub-hysteresis candidates cannot shrink or churn durable calibration")
    func weakerCandidatesRetainExistingWithoutWrite() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let retained = try checkpoint(watts: [500, 520, 510])
        let lower = try checkpoint(watts: [300, 320, 310])
        let marginal = try checkpoint(watts: [510, 530, 520])

        #expect(try await store.saveSimulatorQA(retained) == .stored(generation: 1))
        #expect(try await store.saveSimulatorQA(retained) == .retainedExisting)
        #expect(try await store.saveSimulatorQA(lower) == .retainedExisting)
        #expect(try await store.saveSimulatorQA(marginal) == .retainedExisting)
        #expect(try await store.loadSimulatorQA() == retained)
        #expect(!FileManager.default.fileExists(
            atPath: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir).path
        ))
    }

    @Test("ordinary Codable cannot mint a verified-physical checkpoint from matched authority strings")
    func publicDecoderRejectsVerifiedAuthorityPair() throws {
        let simulator = try checkpoint()
        #expect(throws: ObservedPowerEnvelopeCheckpointError.authorityMismatch) {
            try JSONDecoder().decode(
                ObservedPowerEnvelopeCalibrationCheckpoint.self,
                from: physicalLookingJSON(from: simulator)
            )
        }
    }

    @Test("public durable write rejects a genuine package checkpoint with physical authority")
    func publicWriteRejectsVerifiedCheckpointOnEmptyDirectory() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let (_, _, learner) = try verifiedLearner()
        let physical = try ObservedPowerEnvelopeCalibrationCheckpoint
            .verifiedVehicleMeasurements(from: learner)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.authorityMismatch) {
            try await store.saveSimulatorQA(physical)
        }
        #expect(try await store.loadSimulatorQA() == nil)
        #expect(!FileManager.default.fileExists(
            atPath: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir).path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir).path
        ))
    }

    @Test("package-sealed physical persistence snapshots the verified learner and restores retained authority")
    func verifiedPhysicalPersistenceIsEndToEndPackageSealed() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let (scope, chosenPolicy, learner) = try verifiedLearner()

        #expect(
            try await store.saveVerifiedVehicleMeasurements(from: learner)
                == .stored(generation: 1)
        )
        let restored = try #require(
            try await store.loadVerifiedVehicleMeasurement(
                expectedScope: scope,
                expectedPolicy: chosenPolicy
            )
        )

        #expect(restored.scope == scope)
        #expect(restored.evidenceAuthority == .verifiedVehicleMeasurement)
        #expect(restored.learningSampleCount == 3)
        #expect(restored.upperBandSupportCount >= 2)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.authorityMismatch) {
            _ = try await store.loadSimulatorQA()
        }
    }

    @Test("journal directory is bound to one exact vehicle mode")
    func scopeMismatchRequiresExplicitClearOrSeparateDirectory() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let retained = try checkpoint(vehicle: "sim-es80-a", mode: "sport")
        try await store.saveSimulatorQA(retained)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.scopeMismatch) {
            try await store.saveSimulatorQA(try checkpoint(vehicle: "sim-es80-b", mode: "sport"))
        }
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.scopeMismatch) {
            try await store.saveSimulatorQA(try checkpoint(vehicle: "sim-es80-a", mode: "drive"))
        }
        #expect(try await store.loadSimulatorQA() == retained)
    }

    @Test("journal directory does not silently cross learning policies")
    func policyMismatchRequiresExplicitClearOrSeparateDirectory() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let retained = try checkpoint(policy: policy(hysteresis: 0.05))
        try await store.saveSimulatorQA(retained)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.policyMismatch) {
            try await store.saveSimulatorQA(try checkpoint(
                watts: [600, 630, 620],
                policy: policy(hysteresis: 0.10)
            ))
        }
        #expect(try await store.loadSimulatorQA() == retained)
    }

    @Test("a corrupt newest slot falls back to the older known-good calibration")
    func corruptNewestFallsBack() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let older = try checkpoint(watts: [400, 420, 410])
        let newer = try checkpoint(watts: [600, 630, 620])
        try await store.saveSimulatorQA(older)
        try await store.saveSimulatorQA(newer)

        let slotB = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        try Data("truncated".utf8).write(to: slotB)

        #expect(try await store.loadSimulatorQA() == older)
    }

    @Test("one corrupt slot plus one unused slot recovers without erasing forensic evidence")
    func corruptPlusMissingRecoversIntoUnusedSlot() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        let slotB = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        let forensic = Data("broken-old-envelope".utf8)
        try forensic.write(to: slotA)

        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let recovered = try checkpoint()
        #expect(try await store.saveSimulatorQA(recovered) == .stored(generation: 1))

        #expect(try Data(contentsOf: slotA) == forensic)
        #expect(FileManager.default.fileExists(atPath: slotB.path))
        #expect(try await store.loadSimulatorQA() == recovered)
    }

    @Test("two corrupt slots require explicit recovery instead of silent save")
    func bothCorruptRequireExplicitRecovery() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("bad-a".utf8).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        )
        try Data("bad-b".utf8).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        )
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint) {
            _ = try await store.loadSimulatorQA()
        }
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint) {
            try await store.saveSimulatorQA(try checkpoint())
        }

        // Explicit clear is the destructive recovery operation and leaves a durable
        // monotonic cleared state rather than deleting one corrupt file at a time.
        try await store.clear()
        #expect(try await store.loadSimulatorQA() == nil)
    }

    @Test("unsupported journal schema is never silently overwritten by load or save")
    func unsupportedSchemaIsPreserved() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        try Data("{\"schemaVersion\":999}".utf8).write(to: slotA)
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.unsupportedSchema(999)) {
            _ = try await store.loadSimulatorQA()
        }
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.unsupportedSchema(999)) {
            try await store.saveSimulatorQA(try checkpoint())
        }

        // Explicit clear may intentionally recover an unknown-format journal; if it
        // is interrupted after phase one the survivor stays unsupported/fail-closed.
        try await store.clear()
        #expect(try await store.loadSimulatorQA() == nil)
    }

    @Test("unknown inner calibration schema blocks fallback and normal overwrite")
    func unsupportedCheckpointSchemaIsPreserved() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        let older = try checkpoint(watts: [400, 420, 410])
        try await store.saveSimulatorQA(older)

        let futureBase = try checkpoint(watts: [600, 630, 620])
        let futureEnvelope = AtomicObservedPowerEnvelopeCheckpointStore.Envelope.checkpoint(
            generation: 2,
            checkpoint: futureBase
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: encode(futureEnvelope)) as? [String: Any]
        )
        var inner = try #require(object["checkpoint"] as? [String: Any])
        inner["schemaVersion"] = 999
        object["checkpoint"] = inner
        let slotB = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        let futureData = try JSONSerialization.data(withJSONObject: object)
        try futureData.write(to: slotB)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.unsupportedCheckpointSchema(999)) {
            _ = try await store.loadSimulatorQA()
        }
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.unsupportedCheckpointSchema(999)) {
            try await store.saveSimulatorQA(try checkpoint(watts: [800, 830, 820]))
        }
        #expect(try Data(contentsOf: slotB) == futureData)
    }

    @Test("same generation with divergent valid calibrations is a journal conflict")
    func sameGenerationConflictIsRejected() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let low = try checkpoint(watts: [400, 420, 410])
        let high = try checkpoint(watts: [600, 630, 620])
        let a = AtomicObservedPowerEnvelopeCheckpointStore.Envelope.checkpoint(
            generation: 7,
            checkpoint: low
        )
        let b = AtomicObservedPowerEnvelopeCheckpointStore.Envelope.checkpoint(
            generation: 7,
            checkpoint: high
        )
        try encode(a).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        )
        try encode(b).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        )
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.conflictingGenerations) {
            _ = try await store.loadSimulatorQA()
        }
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.conflictingGenerations) {
            try await store.saveSimulatorQA(try checkpoint(watts: [800, 830, 820]))
        }

        // Explicit clear resolves the conflict with a newer monotonic barrier.
        try await store.clear()
        #expect(try await store.loadSimulatorQA() == nil)
    }

    @Test("valid checkpoint generations must preserve monotonic hysteresis progression")
    func invalidHistoricalProgressionIsRejected() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stronger = try checkpoint(watts: [600, 630, 620])
        let lower = try checkpoint(watts: [400, 420, 410])
        let older = AtomicObservedPowerEnvelopeCheckpointStore.Envelope.checkpoint(
            generation: 10,
            checkpoint: stronger
        )
        let newer = AtomicObservedPowerEnvelopeCheckpointStore.Envelope.checkpoint(
            generation: 11,
            checkpoint: lower
        )
        try encode(older).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        )
        try encode(newer).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        )
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.invalidCalibrationProgression) {
            _ = try await store.loadSimulatorQA()
        }
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.invalidCalibrationProgression) {
            try await store.saveSimulatorQA(try checkpoint(watts: [800, 830, 820]))
        }
    }

    @Test("semantically invalid current-schema inner calibration is corrupt journal data")
    func invalidInnerCheckpointIsCorrupt() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let valid = try checkpoint()
        let envelope = AtomicObservedPowerEnvelopeCheckpointStore.Envelope.checkpoint(
            generation: 1,
            checkpoint: valid
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: encode(envelope)) as? [String: Any]
        )
        var inner = try #require(object["checkpoint"] as? [String: Any])
        inner["learnedObservedCeilingWatts"] = -1.0
        object["checkpoint"] = inner
        try JSONSerialization.data(withJSONObject: object).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        )
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.corruptedCheckpoint) {
            _ = try await store.loadSimulatorQA()
        }
    }

    @Test("generation overflow fails without overwriting retained calibration")
    func generationOverflowIsRejected() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let retained = try checkpoint(watts: [400, 420, 410])
        let envelope = AtomicObservedPowerEnvelopeCheckpointStore.Envelope.checkpoint(
            generation: UInt64.max,
            checkpoint: retained
        )
        let slotA = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        try encode(envelope).write(to: slotA)
        let original = try Data(contentsOf: slotA)
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)

        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.generationOverflow) {
            try await store.saveSimulatorQA(try checkpoint(watts: [800, 830, 820]))
        }
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.generationOverflow) {
            try await store.clear()
        }
        #expect(try Data(contentsOf: slotA) == original)
    }

    @Test("completed clear leaves two newer tombstones and explicitly releases binding")
    func clearWritesMonotonicTombstonesAndRebinds() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        try await store.saveSimulatorQA(try checkpoint(vehicle: "sim-es80-a"))
        try await store.saveSimulatorQA(
            try checkpoint(vehicle: "sim-es80-a", watts: [600, 630, 620])
        )

        try await store.clear()
        #expect(try await store.loadSimulatorQA() == nil)

        let a = try decodeEnvelope(
            at: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        )
        let b = try decodeEnvelope(
            at: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        )
        #expect(a.kind == .cleared)
        #expect(b.kind == .cleared)
        #expect(Set([a.generation, b.generation]) == Set([3, 4]))
        #expect(a.checkpoint == nil)
        #expect(b.checkpoint == nil)

        let rebound = try checkpoint(vehicle: "sim-es80-b", mode: "drive")
        #expect(try await store.saveSimulatorQA(rebound) == .stored(generation: 5))
        #expect(try await store.loadSimulatorQA() == rebound)
    }

    @Test("crash after phase-one clear cannot resurrect when slot A was older")
    func interruptedClearAfterOlderSlotAIsMonotonic() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        try await store.saveSimulatorQA(try checkpoint(watts: [400, 420, 410])) // A = 1
        try await store.saveSimulatorQA(try checkpoint(watts: [600, 630, 620])) // B = 2

        // Simulate process death immediately after clear phase 1 atomically replaces
        // the older A slot with generation-3 tombstone, before B is scrubbed.
        try encode(.cleared(generation: 3)).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir),
            options: .atomic
        )

        let relaunched = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        #expect(try await relaunched.loadSimulatorQA() == nil)

        let rebound = try checkpoint(vehicle: "sim-es80-new", mode: "drive")
        #expect(try await relaunched.saveSimulatorQA(rebound) == .stored(generation: 4))
        #expect(try await relaunched.loadSimulatorQA() == rebound)
    }

    @Test("crash after phase-one clear cannot resurrect when slot B was older")
    func interruptedClearAfterOlderSlotBIsMonotonic() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        try await store.saveSimulatorQA(try checkpoint(watts: [400, 420, 410])) // A = 1
        try await store.saveSimulatorQA(try checkpoint(watts: [600, 630, 620])) // B = 2
        try await store.saveSimulatorQA(try checkpoint(watts: [800, 830, 820])) // A = 3

        // Now B is the older slot. Simulate interruption after B becomes the
        // generation-4 tombstone while A's pre-clear generation 3 survives.
        try encode(.cleared(generation: 4)).write(
            to: slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir),
            options: .atomic
        )

        let relaunched = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        #expect(try await relaunched.loadSimulatorQA() == nil)

        let rebound = try checkpoint(vehicle: "sim-es80-new-b", mode: "eco")
        #expect(try await relaunched.saveSimulatorQA(rebound) == .stored(generation: 5))
        #expect(try await relaunched.loadSimulatorQA() == rebound)
    }

    @Test("phase-one tombstone beside unsupported survivor stays fail-closed until clear resumes")
    func interruptedClearWithUnsupportedSurvivorNeverFallsBack() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let slotA = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotAFileName, in: dir)
        let slotB = slotURL(AtomicObservedPowerEnvelopeCheckpointStore.slotBFileName, in: dir)
        try encode(.cleared(generation: 1)).write(to: slotA, options: .atomic)
        try Data("{\"schemaVersion\":999}".utf8).write(to: slotB)

        let relaunched = AtomicObservedPowerEnvelopeCheckpointStore(directoryURL: dir)
        await #expect(throws: ObservedPowerEnvelopeCheckpointStoreError.unsupportedSchema(999)) {
            _ = try await relaunched.loadSimulatorQA()
        }

        try await relaunched.clear()
        #expect(try await relaunched.loadSimulatorQA() == nil)
    }
}
