import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 experiment-one passive capture evidence")
struct PassiveBluetoothExperimentOneCaptureEvidenceAssessmentTests {
    private enum FixtureError: Error {
        case incompletePowerCycle
    }

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let otherTarget = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!
    private let runA = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
    private let runB = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!

    @Test("exact experiment-one thresholds compose into coherent software capture evidence")
    func coherentAtExactThresholds() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let session = try captureSession(gattIdentifiers: [target.uuidString])

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(assessment.status == .coherentCaptureEvidence(target))
        #expect(assessment.isCaptureEvidenceCoherent)
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

    @Test("same UUID from a different experiment run cannot inherit later capture proof")
    func crossRunSameUUIDFailsClosed() throws {
        let resultFromRunA = try powerCycleResult(repeatedCandidates: [target])
        let captureFromRunB = try captureSession(gattIdentifiers: [target.uuidString])

        let assessment = PassiveBluetoothExperimentOneCaptureEvidenceAssessment.assess(
            powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence(
                runAuthorityID: runA,
                result: resultFromRunA
            ),
            captureEvidence: PassiveBluetoothExperimentOneCaptureEvidence(
                runAuthorityID: runB,
                session: captureFromRunB
            )
        )

        #expect(assessment.status == .experimentRunAuthorityMismatch)
        #expect(assessment.correlatedPeripheralIdentifier == target)
        #expect(assessment.capturedPeripheralIdentifier == target)
        #expect(!assessment.isCaptureEvidenceCoherent)
    }

    @Test("caller cannot weaken the ten-second power-cycle policy")
    func shortPowerCycleWindowFailsClosed() throws {
        let result = try powerCycleResult(
            repeatedCandidates: [target],
            windowDurationNanoseconds: 9_999_999_999
        )
        let session = try captureSession(gattIdentifiers: [target.uuidString])

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(assessment.status == .powerCycleDurationRejected(.insufficientDuration))
        #expect(!assessment.isCaptureEvidenceCoherent)
        #expect(assessment.correlatedPeripheralIdentifier == target)
    }

    @Test("multiple repeated full UUIDs remain ambiguous")
    func ambiguousCorrelationFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target, otherTarget])
        let session = try captureSession(gattIdentifiers: [target.uuidString])

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(
            assessment.status == .correlationRejected(
                .ambiguousRepeatableCandidates([target, otherTarget])
            )
        )
        #expect(!assessment.isCaptureEvidenceCoherent)
        #expect(assessment.correlatedPeripheralIdentifier == nil)
    }

    @Test("zero typed GATT targets cannot inherit advertisement or operator assumptions")
    func missingCaptureTargetFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let session = try captureSession(gattIdentifiers: [])

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(assessment.status == .captureTargetUnresolved)
        #expect(assessment.captureGATTPeripheralIdentifiers.isEmpty)
        #expect(assessment.capturedPeripheralIdentifier == nil)
        #expect(!assessment.isCaptureEvidenceCoherent)
    }

    @Test("multiple typed GATT peripheral identifiers fail closed")
    func multipleCaptureTargetsFailClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let session = try captureSession(
            gattIdentifiers: [target.uuidString, otherTarget.uuidString]
        )

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(assessment.status == .captureTargetUnresolved)
        #expect(assessment.captureGATTPeripheralIdentifiers.count == 2)
        #expect(assessment.capturedPeripheralIdentifier == nil)
    }

    @Test("malformed imported target identity cannot become correlation authority")
    func malformedCaptureTargetFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let session = try captureSession(gattIdentifiers: ["not-a-corebluetooth-uuid"])

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(
            assessment.status == .captureTargetIdentifierMalformed("not-a-corebluetooth-uuid")
        )
        #expect(assessment.capturedPeripheralIdentifier == nil)
        #expect(!assessment.isCaptureEvidenceCoherent)
    }

    @Test("capture GATT target must equal the repeated power-cycle candidate")
    func correlationCaptureMismatchFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let session = try captureSession(gattIdentifiers: [otherTarget.uuidString])

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(
            assessment.status == .captureTargetMismatch(
                correlated: target,
                captured: otherTarget
            )
        )
        #expect(assessment.correlatedPeripheralIdentifier == target)
        #expect(assessment.capturedPeripheralIdentifier == otherTarget)
        #expect(!assessment.isCaptureEvidenceCoherent)
    }

    @Test("post-ready interval remains independently fail-closed at sixty seconds")
    func shortPostReadyObservationFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let session = try captureSession(
            gattIdentifiers: [target.uuidString],
            postReadyDurationNanoseconds: 59_999_999_999
        )

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(assessment.status == .observationDurationRejected(.insufficientDuration))
        #expect(assessment.powerCycleDurationAssessment.isDurationSufficient)
        #expect(!assessment.observationDurationAssessment.isDurationSufficient)
        #expect(!assessment.isCaptureEvidenceCoherent)
    }

    @Test("stored correlation cannot be detached from preserved raw window catalogs")
    func detachedCorrelationFailsClosed() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        var reorderedSnapshots = result.observationSnapshots
        reorderedSnapshots.swapAt(0, 1)
        let tampered = PassiveBluetoothPowerCycleObservationResult(
            windows: result.windows,
            observationSnapshots: reorderedSnapshots,
            correlation: result.correlation
        )
        let session = try captureSession(gattIdentifiers: [target.uuidString])

        let assessment = assessSameRun(powerCycleResult: tampered, captureSession: session)

        #expect(assessment.status == .powerCycleEvidenceInconsistent)
        #expect(!assessment.isCaptureEvidenceCoherent)
    }

    @Test("UUID representation case does not split the same CoreBluetooth identifier")
    func uuidRepresentationParsesBeforeIdentityComparison() throws {
        let result = try powerCycleResult(repeatedCandidates: [target])
        let lowercase = target.uuidString.lowercased()
        let session = try captureSession(gattIdentifiers: [lowercase])

        let assessment = assessSameRun(powerCycleResult: result, captureSession: session)

        #expect(assessment.status == .coherentCaptureEvidence(target))
        #expect(assessment.captureGATTPeripheralIdentifiers == [lowercase])
        #expect(assessment.capturedPeripheralIdentifier == target)
    }

    private func assessSameRun(
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        captureSession: PassiveBluetoothCaptureSession
    ) -> PassiveBluetoothExperimentOneCaptureEvidenceAssessment {
        PassiveBluetoothExperimentOneCaptureEvidenceAssessment.assess(
            powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence(
                runAuthorityID: runA,
                result: powerCycleResult
            ),
            captureEvidence: PassiveBluetoothExperimentOneCaptureEvidence(
                runAuthorityID: runA,
                session: captureSession
            )
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
