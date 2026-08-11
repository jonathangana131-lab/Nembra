import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One authority status promotion")
struct PassiveBluetoothExperimentOneStatusPromotionPolicyTests {
    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let otherTarget = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    @Test("authority mismatch dominates structurally coherent evidence")
    func mismatchDominatesStructuralCoherence() {
        let promoted = PassiveBluetoothExperimentOneStatusPromotionPolicy.promotedStatus(
            authorityMatches: false,
            structuralStatus: .structurallyCoherent(target)
        )

        #expect(promoted == .observationSeriesAuthorityMismatch)
    }

    @Test("authority mismatch also dominates structural failure")
    func mismatchDominatesStructuralFailure() {
        let promoted = PassiveBluetoothExperimentOneStatusPromotionPolicy.promotedStatus(
            authorityMatches: false,
            structuralStatus: .captureTargetUnresolved
        )

        #expect(promoted == .observationSeriesAuthorityMismatch)
    }

    @Test("matching authority maps every structural status one to one")
    func matchingAuthorityPreservesStructuralDecision() {
        typealias Structural = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.Status
        typealias Authority = PassiveBluetoothExperimentOneCaptureEvidenceAssessment.Status

        let mappings: [(Structural, Authority)] = [
            (
                .powerCycleDurationRejected(.insufficientDuration),
                .powerCycleDurationRejected(.insufficientDuration)
            ),
            (.powerCycleEvidenceInconsistent, .powerCycleEvidenceInconsistent),
            (
                .correlationRejected(.noRepeatableCandidate),
                .correlationRejected(.noRepeatableCandidate)
            ),
            (.captureTargetUnresolved, .captureTargetUnresolved),
            (
                .captureTargetIdentifierMalformed("bad-uuid"),
                .captureTargetIdentifierMalformed("bad-uuid")
            ),
            (
                .captureTargetMismatch(correlated: target, captured: otherTarget),
                .captureTargetMismatch(correlated: target, captured: otherTarget)
            ),
            (
                .observationDurationRejected(.continuityBreakWithinWindow),
                .observationDurationRejected(.continuityBreakWithinWindow)
            ),
            (.structurallyCoherent(target), .coherentCaptureEvidence(target)),
        ]

        for (structural, expected) in mappings {
            let promoted = PassiveBluetoothExperimentOneStatusPromotionPolicy.promotedStatus(
                authorityMatches: true,
                structuralStatus: structural
            )
            #expect(promoted == expected)
        }
    }
}
