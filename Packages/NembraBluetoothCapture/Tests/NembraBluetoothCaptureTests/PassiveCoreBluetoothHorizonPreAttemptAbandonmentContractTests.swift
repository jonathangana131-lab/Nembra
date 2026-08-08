import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red source contract for the fourth partial Horizon state:
/// Horizon transaction allocated, but controller work fails before any recorder
/// mutation attempt begins.
///
/// That state cannot truthfully reuse `HorizonRecorderMutationRejectionReceipt`,
/// because that receipt is issued only after the one-shot recorder attempt reaches
/// the canonical authority fence and is rejected before its mutation body executes.
/// The package therefore needs a distinct producer-owned abandonment authority that
/// consumes the exact Horizon admission while its mutation permit is still unused.
struct PassiveCoreBluetoothHorizonPreAttemptAbandonmentContractTests {
    private static func packageSource(_ file: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent(file),
            encoding: .utf8
        )
    }

    @Test("unused Horizon admission has distinct producer-owned abandonment authority")
    func exactAdmissionCanAbandonBeforeRecorderAttemptWithoutForgingMutationRejection() throws {
        let transactionSource = try Self.packageSource(
            "PassiveCoreBluetoothObservationBoundaryTransactionDecision.swift"
        )
        let gateSource = try Self.packageSource(
            "PassiveCoreBluetoothObservationBoundaryQueueGate.swift"
        )

        // Deliberately pin a separate API vocabulary so this state cannot be
        // accidentally routed through the mutation-point rejection receipt.
        #expect(transactionSource.contains("HorizonPreAttemptAbandonmentReceipt"))
        #expect(transactionSource.contains("abandonBeforeRecorderAttempt"))
        #expect(gateSource.contains("abortHorizonBeforeRecorderAttempt"))

        // The queue gate must keep this origin distinct from the existing case where
        // a recorder attempt happened and canonical authority rejected it.
        #expect(gateSource.contains("uncommittedHorizonAbandonedBeforeRecorderAttempt"))
        #expect(gateSource.contains("uncommittedHorizonRejectedBeforeRecorderMutation"))
    }

    @Test("pre-attempt abandonment must consume the same one-shot mutation permit")
    func abandonmentAndRecorderAttemptCannotBothWin() throws {
        let transactionSource = try Self.packageSource(
            "PassiveCoreBluetoothObservationBoundaryTransactionDecision.swift"
        )

        // The abandonment producer belongs on HorizonAdmission and must consume the
        // exact shared permit, rather than exposing a caller-constructible receipt.
        let admissionStart = try #require(
            transactionSource.range(of: "struct HorizonAdmission")?.lowerBound
        )
        let admissionEnd = try #require(
            transactionSource.range(
                of: "struct RecordedHorizonBoundary",
                range: admissionStart..<transactionSource.endIndex
            )?.lowerBound
        )
        let admission = transactionSource[admissionStart..<admissionEnd]

        #expect(admission.contains("abandonBeforeRecorderAttempt"))
        #expect(admission.contains("mutationPermit"))
        #expect(!admission.contains("public init"))
    }
}
