import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One Horizon-bounded target attribution")
struct PassiveBluetoothExperimentOneStructuralHorizonScopeTests {
    private enum FixtureError: Error {
        case incompletePowerCycle
    }

    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let otherTarget = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!

    @Test("post-H GATT records cannot make the accepted target ambiguous")
    func postHOtherTargetIsIgnored() throws {
        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: try powerCycleResult(),
            captureSession: try captureSession(
                gattIdentifiers: [target.uuidString, otherTarget.uuidString],
                readyWatermark: 1,
                horizonWatermark: 1
            )
        )

        #expect(assessment.status == .structurallyCoherent(target))
        #expect(assessment.captureGATTPeripheralIdentifiers == [target.uuidString])
        #expect(assessment.capturedPeripheralIdentifier == target)
    }

    @Test("a target observed only after H cannot establish Experiment One structural target evidence")
    func postHOnlyTargetIsUnavailable() throws {
        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: try powerCycleResult(),
            captureSession: try captureSession(
                gattIdentifiers: [target.uuidString],
                readyWatermark: 0,
                horizonWatermark: 0
            )
        )

        #expect(assessment.status == .captureTargetUnresolved)
        #expect(assessment.captureGATTPeripheralIdentifiers.isEmpty)
        #expect(assessment.capturedPeripheralIdentifier == nil)
    }

    @Test("invalid Ready-Horizon duration wins before target attribution")
    func invalidObservationWindowBlocksTargetInterpretation() throws {
        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: try powerCycleResult(),
            captureSession: try captureSession(
                gattIdentifiers: ["not-a-corebluetooth-uuid"],
                readyWatermark: 1,
                horizonWatermark: 1,
                postReadyDurationNanoseconds:
                    PassiveBluetoothExperimentOneCapturePolicy
                        .minimumPostReadyObservationDurationNanoseconds - 1
            )
        )

        #expect(assessment.status == .observationDurationRejected(.insufficientDuration))
        #expect(assessment.captureGATTPeripheralIdentifiers.isEmpty)
        #expect(assessment.capturedPeripheralIdentifier == nil)
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
        gattIdentifiers: [String],
        readyWatermark: UInt64,
        horizonWatermark: UInt64,
        postReadyDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    ) throws -> PassiveBluetoothCaptureSession {
        let records = try gattIdentifiers.enumerated().map { index, identifier in
            let sequence = UInt64(index + 1)
            return PassiveBluetoothCaptureRecord(
                sequenceNumber: sequence,
                receivedAtUptimeNanoseconds: sequence * 100,
                receivedAtDate: Date(timeIntervalSince1970: 4_000 + Double(index)),
                event: .service(
                    try PassiveBluetoothServiceObservation(
                        peripheralIdentifier: identifier,
                        serviceUUID: "FFF0",
                        isPrimary: true
                    )
                )
            )
        }

        let readyUptime: UInt64 = 1_000
        return try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            vehicleIdentity: VehicleProfile.aovoproES80.identity,
            startedAt: Date(timeIntervalSince1970: 4_000),
            records: records,
            observationBoundaries: [
                PassiveBluetoothObservationBoundary(
                    kind: .finiteAcquisitionReady,
                    recordSequenceWatermark: readyWatermark,
                    observedAtUptimeNanoseconds: readyUptime,
                    observedAtDate: Date(timeIntervalSince1970: 5_000)
                ),
                PassiveBluetoothObservationBoundary(
                    kind: .observationHorizon,
                    recordSequenceWatermark: horizonWatermark,
                    observedAtUptimeNanoseconds: readyUptime + postReadyDurationNanoseconds,
                    observedAtDate: Date(timeIntervalSince1970: 5_060)
                ),
            ]
        )
    }
}
