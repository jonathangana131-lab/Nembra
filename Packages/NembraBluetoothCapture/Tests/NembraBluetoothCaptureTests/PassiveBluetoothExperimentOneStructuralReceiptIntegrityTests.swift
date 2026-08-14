import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One receipt/catalog integrity")
struct PassiveBluetoothExperimentOneStructuralReceiptIntegrityTests {
    private enum FixtureError: Error {
        case incompletePowerCycle
    }

    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!

    @Test("receipt candidate count must match the preserved raw snapshot")
    func candidateCountMismatchFailsClosed() throws {
        let original = try powerCycleResult()
        var windows = original.windows
        let first = windows[0]
        windows[0] = PassiveBluetoothPowerCycleObservationWindowReceipt(
            phase: first.phase,
            windowSequence: first.windowSequence,
            startedAtUptimeNanoseconds: first.startedAtUptimeNanoseconds,
            endedAtUptimeNanoseconds: first.endedAtUptimeNanoseconds,
            observedCandidateCount: first.observedCandidateCount + 1
        )
        let tampered = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: original.observationSnapshots,
            correlation: original.correlation
        )

        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: tampered,
            captureSession: try captureSession()
        )

        #expect(assessment.powerCycleDurationAssessment.isDurationSufficient)
        #expect(assessment.status == .powerCycleEvidenceInconsistent)
        #expect(!assessment.isStructurallyCoherent)
    }

    @Test("later receipt cannot overlap or regress behind the prior monotonic window")
    func crossWindowChronologyRegressionFailsClosed() throws {
        let original = try powerCycleResult()
        var windows = original.windows
        let first = windows[0]
        let second = windows[1]
        let duration = second.endedAtUptimeNanoseconds - second.startedAtUptimeNanoseconds
        let regressedStart = first.endedAtUptimeNanoseconds - 1
        windows[1] = PassiveBluetoothPowerCycleObservationWindowReceipt(
            phase: second.phase,
            windowSequence: second.windowSequence,
            startedAtUptimeNanoseconds: regressedStart,
            endedAtUptimeNanoseconds: regressedStart + duration,
            observedCandidateCount: second.observedCandidateCount
        )
        let tampered = PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: original.observationSnapshots,
            correlation: original.correlation
        )

        // The lower duration primitive intentionally validates each receipt independently; this
        // reconstructed artifact therefore still passes that narrow gate. Experiment One's raw
        // structural replay must add the serial-producer chronology invariant and reject it.
        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: tampered,
            captureSession: try captureSession()
        )

        #expect(assessment.powerCycleDurationAssessment.isDurationSufficient)
        #expect(assessment.status == .powerCycleEvidenceInconsistent)
        #expect(!assessment.isStructurallyCoherent)
    }

    private func powerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        var finalResult: PassiveBluetoothPowerCycleObservationResult?

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index) * 20_000_000_000
            let candidates: [PassiveBluetoothCandidateObservationSnapshot.Candidate]
            if phase.operatorExpectedPowerOn {
                candidates = [candidate(neighbor), candidate(target)]
            } else {
                candidates = [candidate(neighbor)]
            }

            finalResult = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds:
                    start + PassiveBluetoothExperimentOneCapturePolicy
                        .minimumPowerCycleWindowDurationNanoseconds,
                candidates: candidates
            ) ?? finalResult
        }

        guard let finalResult else { throw FixtureError.incompletePowerCycle }
        return finalResult
    }

    private func candidate(_ id: UUID) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        PassiveBluetoothCandidateObservationSnapshot.Candidate(id: id, isConnectable: true)
    }

    private func captureSession() throws -> PassiveBluetoothCaptureSession {
        let record = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 4_000),
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFF0",
                    isPrimary: true
                )
            )
        )
        let readyUptime: UInt64 = 1_000
        return try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            vehicleIdentity: VehicleProfile.aovoproES80.identity,
            startedAt: Date(timeIntervalSince1970: 4_000),
            records: [record],
            observationBoundaries: [
                PassiveBluetoothObservationBoundary(
                    kind: .finiteAcquisitionReady,
                    recordSequenceWatermark: 1,
                    observedAtUptimeNanoseconds: readyUptime,
                    observedAtDate: Date(timeIntervalSince1970: 5_000)
                ),
                PassiveBluetoothObservationBoundary(
                    kind: .observationHorizon,
                    recordSequenceWatermark: 1,
                    observedAtUptimeNanoseconds:
                        readyUptime + PassiveBluetoothExperimentOneCapturePolicy
                            .minimumPostReadyObservationDurationNanoseconds,
                    observedAtDate: Date(timeIntervalSince1970: 5_060)
                ),
            ]
        )
    }
}
