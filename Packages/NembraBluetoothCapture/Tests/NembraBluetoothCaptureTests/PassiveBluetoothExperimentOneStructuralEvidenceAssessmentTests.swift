import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One descriptive structural evidence")
struct PassiveBluetoothExperimentOneStructuralEvidenceAssessmentTests {
    private enum FixtureError: Error {
        case incompletePowerCycle
    }

    private let es80 = VehicleProfile.aovoproES80.identity
    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let otherTarget = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!

    @Test("exact fixed thresholds produce descriptive structural coherence")
    func coherentAtExactThresholds() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let session = try captureSession(gattIdentifiers: [target.uuidString])

        let assessment = assess(result, session)

        #expect(assessment.status == .structurallyCoherent(target))
        #expect(assessment.isStructurallyCoherent)
        #expect(assessment.correlatedPeripheralIdentifier == target)
        #expect(assessment.capturedPeripheralIdentifier == target)
        #expect(assessment.captureGATTPeripheralIdentifiers == [target.uuidString])
        #expect(assessment.captureSessionID == session.id)
        #expect(assessment.vehicleIdentity == es80)
        #expect(assessment.powerCycleDurationAssessment.isDurationSufficient)
        #expect(assessment.observationDurationAssessment.isDurationSufficient)
        #expect(
            assessment.powerCycleDurationAssessment.minimumRequiredDurationNanoseconds
                == PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        )
        #expect(
            assessment.observationDurationAssessment.minimumRequiredDurationNanoseconds
                == PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
        )
    }

    @Test("power-cycle window one nanosecond short fails closed")
    func shortPowerCycleWindowFailsClosed() throws {
        let result = try powerCycleResult(
            repeatedCandidates: [target],
            windowDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds - 1
        )
        let assessment = assess(
            result,
            try captureSession(gattIdentifiers: [target.uuidString])
        )

        #expect(assessment.status == .powerCycleDurationRejected(.insufficientDuration))
        #expect(!assessment.isStructurallyCoherent)
    }

    @Test("no repeatable ON-only candidate is rejected")
    func noRepeatableCandidateFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [])
        let assessment = assess(
            result,
            try captureSession(gattIdentifiers: [target.uuidString])
        )

        #expect(assessment.status == .correlationRejected(.noRepeatableCandidate))
        #expect(assessment.correlatedPeripheralIdentifier == nil)
    }

    @Test("multiple repeatable full UUIDs remain ambiguous")
    func ambiguousCorrelationFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target, otherTarget])
        let assessment = assess(
            result,
            try captureSession(gattIdentifiers: [target.uuidString])
        )

        #expect(
            assessment.status == .correlationRejected(
                .ambiguousRepeatableCandidates([target, otherTarget])
            )
        )
        #expect(assessment.correlatedPeripheralIdentifier == nil)
    }

    @Test("advertisement or connection context cannot replace typed GATT target evidence")
    func missingGATTTargetFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let assessment = assess(result, try captureSession(gattIdentifiers: []))

        #expect(assessment.status == .captureTargetUnresolved)
        #expect(assessment.captureGATTPeripheralIdentifiers.isEmpty)
        #expect(assessment.capturedPeripheralIdentifier == nil)
    }

    @Test("multiple typed GATT peripheral identifiers fail closed")
    func multipleGATTTargetsFailClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let assessment = assess(
            result,
            try captureSession(gattIdentifiers: [target.uuidString, otherTarget.uuidString])
        )

        #expect(assessment.status == .captureTargetUnresolved)
        #expect(assessment.captureGATTPeripheralIdentifiers.count == 2)
        #expect(assessment.capturedPeripheralIdentifier == nil)
    }

    @Test("malformed imported GATT target identifier fails closed")
    func malformedGATTTargetFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let assessment = assess(
            result,
            try captureSession(gattIdentifiers: ["not-a-corebluetooth-uuid"])
        )

        #expect(
            assessment.status == .captureTargetIdentifierMalformed("not-a-corebluetooth-uuid")
        )
        #expect(assessment.capturedPeripheralIdentifier == nil)
    }

    @Test("capture GATT target must equal the repeated power-cycle candidate")
    func correlationCaptureMismatchFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let assessment = assess(
            result,
            try captureSession(gattIdentifiers: [otherTarget.uuidString])
        )

        #expect(
            assessment.status == .captureTargetMismatch(
                correlated: target,
                captured: otherTarget
            )
        )
        #expect(assessment.correlatedPeripheralIdentifier == target)
        #expect(assessment.capturedPeripheralIdentifier == otherTarget)
    }

    @Test("post-ready interval one nanosecond short fails closed")
    func shortPostReadyObservationFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let assessment = assess(
            result,
            try captureSession(
                gattIdentifiers: [target.uuidString],
                postReadyDurationNanoseconds:
                    PassiveBluetoothExperimentOneCapturePolicy
                        .minimumPostReadyObservationDurationNanoseconds - 1
            )
        )

        #expect(assessment.status == .observationDurationRejected(.insufficientDuration))
        #expect(assessment.powerCycleDurationAssessment.isDurationSufficient)
        #expect(!assessment.observationDurationAssessment.isDurationSufficient)
    }

    @Test("stored correlation cannot be detached from reordered raw window catalogs")
    func detachedCorrelationFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        var reorderedSnapshots = result.observationSnapshots
        reorderedSnapshots.swapAt(0, 1)
        let tampered = PassiveBluetoothPowerCycleObservationResult(
            windows: result.windows,
            observationSnapshots: reorderedSnapshots,
            correlation: result.correlation
        )

        let assessment = assess(
            tampered,
            try captureSession(gattIdentifiers: [target.uuidString])
        )

        #expect(assessment.status == .powerCycleEvidenceInconsistent)
        #expect(!assessment.isStructurallyCoherent)
    }

    @Test("UUID string case does not split one CoreBluetooth identifier")
    func uuidRepresentationParsesBeforeComparison() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let lowercase = target.uuidString.lowercased()
        let assessment = assess(
            result,
            try captureSession(gattIdentifiers: [lowercase])
        )

        #expect(assessment.status == .structurallyCoherent(target))
        #expect(assessment.captureGATTPeripheralIdentifiers == [lowercase])
        #expect(assessment.capturedPeripheralIdentifier == target)
    }

    @Test("two actual producer lives never share observation-series authority")
    func producerLifeAuthorityMismatchIsDetectable() throws {
        let first = try powerCycleResult(repeatedCandidates: [target])
        let second = try powerCycleResult(repeatedCandidates: [target])
        let firstIdentity = try #require(first.correlation.observationSeriesIdentities.first)
        let secondIdentity = try #require(second.correlation.observationSeriesIdentities.first)

        #expect(
            PassiveBluetoothExperimentOneStructuralEvidenceAssessment
                .observationSeriesAuthorityMatches(
                    powerCycle: firstIdentity,
                    capture: firstIdentity
                )
        )
        #expect(
            !PassiveBluetoothExperimentOneStructuralEvidenceAssessment
                .observationSeriesAuthorityMatches(
                    powerCycle: firstIdentity,
                    capture: secondIdentity
                )
        )
    }

    private func assess(
        _ result: PassiveBluetoothPowerCycleObservationResult,
        _ session: PassiveBluetoothCaptureSession
    ) -> PassiveBluetoothExperimentOneStructuralEvidenceAssessment {
        PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: result,
            captureSession: session
        )
    }

    private func powerCycleResult(
        repeatedCandidates: [UUID],
        windowDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        var finalResult: PassiveBluetoothPowerCycleObservationResult?

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index) * 20_000_000_000
            let candidates: [PassiveBluetoothCandidateObservationSnapshot.Candidate]
            if phase.operatorExpectedPowerOn {
                candidates = [candidate(neighbor)] + repeatedCandidates.map { candidate($0) }
            } else {
                candidates = [candidate(neighbor)]
            }

            finalResult = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + windowDurationNanoseconds,
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
        postReadyDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    ) throws -> PassiveBluetoothCaptureSession {
        var records: [PassiveBluetoothCaptureRecord] = []
        records.reserveCapacity(gattIdentifiers.count)

        for (index, identifier) in gattIdentifiers.enumerated() {
            let sequence = UInt64(index + 1)
            records.append(
                PassiveBluetoothCaptureRecord(
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
            )
        }

        let readyUptime: UInt64 = 1_000
        let watermark = records.last?.sequenceNumber ?? 0
        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: watermark,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: Date(timeIntervalSince1970: 5_000)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: watermark,
            observedAtUptimeNanoseconds: readyUptime + postReadyDurationNanoseconds,
            observedAtDate: Date(timeIntervalSince1970: 5_060)
        )

        return try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 4_000),
            records: records,
            observationBoundaries: [ready, horizon]
        )
    }
}
