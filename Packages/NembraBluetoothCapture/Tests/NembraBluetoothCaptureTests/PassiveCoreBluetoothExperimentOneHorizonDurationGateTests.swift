import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One Ready to Horizon duration gate")
struct PassiveCoreBluetoothExperimentOneHorizonDurationGateTests {
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

    @Test("uses the sealed Experiment One sixty-second policy")
    func usesCanonicalExperimentPolicy() {
        #expect(
            PassiveCoreBluetoothExperimentOneHorizonDurationGate
                .minimumObservationDurationNanoseconds
                == PassiveBluetoothExperimentOneCapturePolicy
                    .minimumPostReadyObservationDurationNanoseconds
        )
        #expect(
            PassiveCoreBluetoothExperimentOneHorizonDurationGate
                .minimumObservationDurationNanoseconds == 60_000_000_000
        )
    }

    @Test("monotonic regression fails closed before subtraction")
    func rejectsRegressingUptime() {
        do {
            _ = try PassiveCoreBluetoothExperimentOneHorizonDurationGate
                .validatedElapsedDuration(
                    readyUptimeNanoseconds: 101,
                    currentUptimeNanoseconds: 100
                )
            Issue.record("Regressing monotonic uptime must fail closed.")
        } catch let error as PassiveCoreBluetoothExperimentOneHorizonDurationGate.StateError {
            #expect(
                error == .uptimeRegressed(
                    readyUptimeNanoseconds: 101,
                    currentUptimeNanoseconds: 100
                )
            )
        } catch {
            Issue.record("Unexpected duration-gate error: \(error)")
        }
    }

    @Test("one nanosecond short remains ineligible")
    func rejectsOneNanosecondShort() {
        let required = PassiveCoreBluetoothExperimentOneHorizonDurationGate
            .minimumObservationDurationNanoseconds
        let ready: UInt64 = 1_000

        do {
            _ = try PassiveCoreBluetoothExperimentOneHorizonDurationGate
                .validatedElapsedDuration(
                    readyUptimeNanoseconds: ready,
                    currentUptimeNanoseconds: ready + required - 1
                )
            Issue.record("Experiment One Horizon must not admit one nanosecond early.")
        } catch let error as PassiveCoreBluetoothExperimentOneHorizonDurationGate.StateError {
            #expect(
                error == .minimumObservationDurationNotSatisfied(
                    requiredNanoseconds: required,
                    observedNanoseconds: required - 1
                )
            )
        } catch {
            Issue.record("Unexpected duration-gate error: \(error)")
        }
    }

    @Test("exact minimum and later uptime are eligible")
    func acceptsExactMinimumAndLater() throws {
        let required = PassiveCoreBluetoothExperimentOneHorizonDurationGate
            .minimumObservationDurationNanoseconds
        let ready: UInt64 = 10_000

        let exact = try PassiveCoreBluetoothExperimentOneHorizonDurationGate
            .validatedElapsedDuration(
                readyUptimeNanoseconds: ready,
                currentUptimeNanoseconds: ready + required
            )
        let later = try PassiveCoreBluetoothExperimentOneHorizonDurationGate
            .validatedElapsedDuration(
                readyUptimeNanoseconds: ready,
                currentUptimeNanoseconds: ready + required + 777
            )

        #expect(exact == required)
        #expect(later == required + 777)
    }

    @Test("production admission cannot advance Horizon before sixty seconds")
    @MainActor
    func productionAdmissionRejectsEarlyWithoutMutatingLifecycle() async throws {
        let recorder = try makeRecorder()
        let fence = makeFence()
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

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
        let phaseBeforeAdmission = gate.phase

        do {
            _ = try PassiveCoreBluetoothExperimentOneHorizonDurationGate.admit(
                committedReadyEpoch: committedReady
            )
            Issue.record("A freshly committed Ready epoch must not earn a sixty-second Horizon permit.")
        } catch let error as PassiveCoreBluetoothExperimentOneHorizonDurationGate.StateError {
            switch error {
            case let .minimumObservationDurationNotSatisfied(required, observed):
                #expect(
                    required == PassiveBluetoothExperimentOneCapturePolicy
                        .minimumPostReadyObservationDurationNanoseconds
                )
                #expect(observed < required)
            case .uptimeRegressed:
                Issue.record("Production monotonic uptime must not regress after Ready.")
            }
        } catch {
            Issue.record("Unexpected duration-gate error: \(error)")
        }

        #expect(gate.phase == phaseBeforeAdmission)
        #expect(gate.phase == .observing)
        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.count == 1)
        #expect(session.observationBoundaries.first?.kind == .finiteAcquisitionReady)
    }
}
