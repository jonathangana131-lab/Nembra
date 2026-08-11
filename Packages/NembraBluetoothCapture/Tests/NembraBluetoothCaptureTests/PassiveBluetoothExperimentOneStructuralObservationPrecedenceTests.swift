import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One observation-boundary precedence")
struct PassiveBluetoothExperimentOneStructuralObservationPrecedenceTests {
    private enum FixtureError: Error {
        case incompletePowerCycle
    }

    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!

    @Test("invalid Ready-Horizon duration blocks target interpretation first")
    func invalidObservationWindowBlocksTargetInterpretation() throws {
        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: try powerCycleResult(),
            captureSession: try captureSession(
                gattIdentifier: "not-a-corebluetooth-uuid",
                postReadyDurationNanoseconds:
                    PassiveBluetoothExperimentOneCapturePolicy
                        .minimumPostReadyObservationDurationNanoseconds - 1
            )
        )

        #expect(assessment.status == .observationDurationRejected(.insufficientDuration))
        #expect(assessment.captureGATTPeripheralIdentifiers.isEmpty)
        #expect(assessment.capturedPeripheralIdentifier == nil)
    }

    @Test("valid Horizon permits typed target interpretation through its final watermark")
    func validObservationWindowAllowsTargetInterpretation() throws {
        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: try powerCycleResult(),
            captureSession: try captureSession(gattIdentifier: target.uuidString)
        )

        #expect(assessment.status == .structurallyCoherent(target))
        #expect(assessment.captureGATTPeripheralIdentifiers == [target.uuidString])
        #expect(assessment.capturedPeripheralIdentifier == target)
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

    private func captureSession(
        gattIdentifier: String,
        postReadyDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    ) throws -> PassiveBluetoothCaptureSession {
        let record = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 4_000),
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: gattIdentifier,
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
                    observedAtUptimeNanoseconds: readyUptime + postReadyDurationNanoseconds,
                    observedAtDate: Date(timeIntervalSince1970: 5_060)
                ),
            ]
        )
    }
}
