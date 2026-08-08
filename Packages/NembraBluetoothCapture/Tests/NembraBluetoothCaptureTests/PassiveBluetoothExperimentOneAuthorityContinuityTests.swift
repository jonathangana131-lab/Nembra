import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 experiment-one authority continuity")
struct PassiveBluetoothExperimentOneAuthorityContinuityTests {
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
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!

    @Test("detached power-cycle authorities cannot inherit whole-experiment coherence from one capture")
    func detachedPowerCycleAuthoritiesCannotBindTheSameCapture() throws {
        let firstPowerCycle = try powerCycleResult()
        let secondPowerCycle = try powerCycleResult()

        let firstSeries = try #require(
            firstPowerCycle.correlation.observationSeriesIdentities.first
        )
        let secondSeries = try #require(
            secondPowerCycle.correlation.observationSeriesIdentities.first
        )
        #expect(firstSeries != secondSeries)

        let capture = try callerBuiltCaptureSession()
        let firstAssessment = PassiveBluetoothExperimentOneCaptureEvidenceAssessment.assess(
            powerCycleResult: firstPowerCycle,
            captureSession: capture
        )
        let secondAssessment = PassiveBluetoothExperimentOneCaptureEvidenceAssessment.assess(
            powerCycleResult: secondPowerCycle,
            captureSession: capture
        )

        // This capture carries no producer-issued relationship to either package-issued OFF1 ->
        // ON1 -> OFF2 -> ON2 series. UUID equality cannot choose one detached producer life and
        // invent experiment provenance, so both combinations must fail closed. Once Nembra has a
        // sealed finalized-capture authority that is positively bound to one series, this fixture
        // should evolve to prove A + C can be coherent while independently issued B + C is rejected.
        #expect(!firstAssessment.isCaptureEvidenceCoherent)
        #expect(!secondAssessment.isCaptureEvidenceCoherent)
    }

    @Test("a structurally valid caller-built capture is not experiment-one PASS authority")
    func barePublicCaptureSessionCannotEarnWholeExperimentCoherence() throws {
        let powerCycle = try powerCycleResult()

        // This fixture intentionally constructs the capture side only from NembraCore's public raw
        // schema initializers. Public/importable structural evidence is useful for offline analysis,
        // but experiment-one PASS must require a package/controller-issued authority proving that
        // this exact artifact actually crossed the trusted recorder/finalization boundary.
        let capture = try callerBuiltCaptureSession()
        let assessment = PassiveBluetoothExperimentOneCaptureEvidenceAssessment.assess(
            powerCycleResult: powerCycle,
            captureSession: capture
        )

        #expect(!assessment.isCaptureEvidenceCoherent)
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
                    start + PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds,
                candidates: candidates
            ) ?? finalResult
        }

        guard let finalResult else {
            throw FixtureError.incompletePowerCycle
        }
        return finalResult
    }

    private func candidate(_ id: UUID) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        PassiveBluetoothCandidateObservationSnapshot.Candidate(id: id, isConnectable: true)
    }

    /// The capture side deliberately uses only public NembraCore evidence constructors. The test
    /// target needs `@testable` solely to obtain a deterministic package-issued power-cycle result.
    private func callerBuiltCaptureSession() throws -> PassiveBluetoothCaptureSession {
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

        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: 1,
            observedAtUptimeNanoseconds: 1_000,
            observedAtDate: Date(timeIntervalSince1970: 5_000)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 1,
            observedAtUptimeNanoseconds:
                1_000 + PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds,
            observedAtDate: Date(timeIntervalSince1970: 5_060)
        )

        return try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 4_000),
            records: [record],
            observationBoundaries: [ready, horizon]
        )
    }
}
