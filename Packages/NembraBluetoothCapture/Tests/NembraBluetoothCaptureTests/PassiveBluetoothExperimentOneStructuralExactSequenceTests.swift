import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One exact power-cycle producer sequence")
struct PassiveBluetoothExperimentOneStructuralExactSequenceTests {
    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!

    @Test("detached strictly-increasing counters cannot become structural Experiment One evidence")
    func detachedIncreasingWindowSequenceFailsClosed() throws {
        let series = PassiveBluetoothCandidateObservationSeriesIdentity(
            rawValue: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        )
        let sequences: [UInt64] = [10, 20, 30, 40]
        let phases = PassiveBluetoothPowerCycleObservationPhase.allCases

        let snapshots = try zip(phases, sequences).map { pair in
            try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: series,
                windowSequence: .init(rawValue: pair.1),
                candidates: pair.0.operatorExpectedPowerOn
                    ? [candidate(neighbor), candidate(target)]
                    : [candidate(neighbor)]
            )
        }
        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        #expect(correlation.disposition == .singleRepeatableCandidate(target))

        let minimum = PassiveBluetoothExperimentOneCapturePolicy
            .minimumPowerCycleWindowDurationNanoseconds
        let receipts = zip(phases, snapshots).enumerated().map { index, pair in
            let start = UInt64(index) * (minimum + 1_000)
            return PassiveBluetoothPowerCycleObservationWindowReceipt(
                phase: pair.0,
                windowSequence: pair.1.windowSequence,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + minimum,
                observedCandidateCount: pair.1.candidates.count
            )
        }
        let result = PassiveBluetoothPowerCycleObservationResult(
            windows: receipts,
            observationSnapshots: snapshots,
            correlation: correlation
        )

        let assessment = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: result,
            captureSession: try validCaptureSession()
        )

        #expect(assessment.status == .powerCycleEvidenceInconsistent)
        #expect(!assessment.isStructurallyCoherent)
    }

    private func candidate(
        _ id: UUID
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
    }

    private func validCaptureSession() throws -> PassiveBluetoothCaptureSession {
        let startedAt = Date(timeIntervalSince1970: 4_000)
        let record = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: startedAt,
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: "FFF0",
                    isPrimary: true
                )
            )
        )
        let readyUptime: UInt64 = 1_000
        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: 1,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: Date(timeIntervalSince1970: 5_000)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 1,
            observedAtUptimeNanoseconds: readyUptime
                + PassiveBluetoothExperimentOneCapturePolicy
                    .minimumPostReadyObservationDurationNanoseconds,
            observedAtDate: Date(timeIntervalSince1970: 5_060)
        )

        return try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            vehicleIdentity: VehicleProfile.aovoproES80.identity,
            startedAt: startedAt,
            records: [record],
            observationBoundaries: [ready, horizon]
        )
    }
}