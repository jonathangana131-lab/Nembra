import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth boundary mutation permits")
struct PassiveCoreBluetoothObservationBoundaryMutationPermitTests {
    private enum AttemptResult: Equatable, Sendable {
        case recorded
        case replayRejected
        case unexpected
    }

    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    private func makeFence() -> PassiveCoreBluetoothArtifactAuthorityFence {
        PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
    }

    private func makeRecorder() throws -> PassiveCoreBluetoothCaptureRecorder {
        try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private static func classifyReadyAttempt(
        _ admission: PassiveCoreBluetoothObservationBoundaryTransactionDecision,
        recorder: PassiveCoreBluetoothCaptureRecorder
    ) async -> AttemptResult {
        do {
            _ = try await admission.recordBoundary(on: recorder)
            return .recorded
        } catch let error as PassiveCoreBluetoothObservationBoundaryMutationAttemptError {
            return error == .alreadyAttempted ? .replayRejected : .unexpected
        } catch {
            return .unexpected
        }
    }

    private static func classifyHorizonAttempt(
        _ admission: PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission,
        recorder: PassiveCoreBluetoothCaptureRecorder
    ) async -> AttemptResult {
        do {
            _ = try await admission.recordBoundary(on: recorder)
            return .recorded
        } catch let error as PassiveCoreBluetoothObservationBoundaryMutationAttemptError {
            return error == .alreadyAttempted ? .replayRejected : .unexpected
        } catch {
            return .unexpected
        }
    }

    @Test("Ready admission rejects sequential recorder replay after one durable append")
    @MainActor
    func readySequentialReplayIsOneShot() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: makeFence(),
            gate: &gate
        )

        _ = try await ready.recordBoundary(on: recorder)

        do {
            _ = try await ready.recordBoundary(on: recorder)
            Issue.record("The same Ready admission must not enter the recorder twice.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryMutationAttemptError {
            #expect(error == .alreadyAttempted)
        } catch {
            Issue.record("Unexpected Ready replay error: \(error)")
        }

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.map(\.kind) == [.finiteAcquisitionReady])
        guard case .drainingReady = gate.phase else {
            Issue.record("Replay rejection must not mutate the unresolved Ready gate transaction.")
            return
        }
    }

    @Test("Ready admission permits exactly one concurrent recorder entry across value copies")
    @MainActor
    func readyConcurrentReplayIsOneShot() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: makeFence(),
            gate: &gate
        )
        let copies = Array(repeating: ready, count: 8)

        let results = await withTaskGroup(
            of: AttemptResult.self,
            returning: [AttemptResult].self
        ) { group in
            for copy in copies {
                group.addTask {
                    await Self.classifyReadyAttempt(copy, recorder: recorder)
                }
            }

            var collected: [AttemptResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(results.filter { $0 == .recorded }.count == 1)
        #expect(results.filter { $0 == .replayRejected }.count == 7)
        #expect(!results.contains(.unexpected))

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.map(\.kind) == [.finiteAcquisitionReady])
    }

    @Test("Horizon admission rejects sequential recorder replay after one durable append")
    @MainActor
    func horizonSequentialReplayIsOneShot() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &gate
        )

        _ = try await horizon.recordBoundary(on: recorder)

        do {
            _ = try await horizon.recordBoundary(on: recorder)
            Issue.record("The same Horizon admission must not enter the recorder twice.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryMutationAttemptError {
            #expect(error == .alreadyAttempted)
        } catch {
            Issue.record("Unexpected Horizon replay error: \(error)")
        }

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
        guard case .drainingHorizon = gate.phase else {
            Issue.record("Replay rejection must not mutate the unresolved Horizon gate transaction.")
            return
        }
    }

    @Test("Horizon admission permits exactly one concurrent recorder entry across value copies")
    @MainActor
    func horizonConcurrentReplayIsOneShot() async throws {
        let recorder = try makeRecorder()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let fence = makeFence()
        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &gate
        )
        let copies = Array(repeating: horizon, count: 8)

        let results = await withTaskGroup(
            of: AttemptResult.self,
            returning: [AttemptResult].self
        ) { group in
            for copy in copies {
                group.addTask {
                    await Self.classifyHorizonAttempt(copy, recorder: recorder)
                }
            }

            var collected: [AttemptResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(results.filter { $0 == .recorded }.count == 1)
        #expect(results.filter { $0 == .replayRejected }.count == 7)
        #expect(!results.contains(.unexpected))

        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
    }
}
