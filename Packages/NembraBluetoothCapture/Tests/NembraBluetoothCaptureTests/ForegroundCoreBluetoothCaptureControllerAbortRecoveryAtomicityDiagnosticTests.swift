import Foundation
import Testing

@Suite("Abort recovery failure-atomic publication diagnostic")
struct ForegroundCoreBluetoothCaptureControllerAbortRecoveryAtomicityDiagnosticTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
            ),
            encoding: .utf8
        )
    }

    private static func abortRecoveryMethod(in source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "private func completeAbortedFreshTargetSessionIfReady(")
        )
        let tail = source[start.lowerBound...]
        let end = try #require(
            tail.range(of: "private func beginTargetSessionIfNeeded(")
        )
        return tail[..<end.lowerBound]
    }

    @Test("all throwing gate validation happens on a value copy before canonical fence transition")
    func queueGateMustPreflightBeforeIrreversibleAuthorityTransition() throws {
        let method = try Self.abortRecoveryMethod(in: Self.controllerSource())

        let stagedGateDeclaration = try #require(
            method.range(of: "var reopenedGate = observationBoundaryQueueGate")
        )
        let stagedGateValidation = try #require(
            method.range(of: "try reopenedGate.reopenAfterAbortedFreshTargetSession(")
        )
        let fenceTransition = try #require(
            method.range(of: "try artifactAuthorityFence.transition(")
        )
        let stagedGatePublication = try #require(
            method.range(of: "observationBoundaryQueueGate = reopenedGate")
        )

        #expect(stagedGateDeclaration.lowerBound < stagedGateValidation.lowerBound)
        #expect(stagedGateValidation.lowerBound < fenceTransition.lowerBound)
        #expect(fenceTransition.lowerBound < stagedGatePublication.lowerBound)
        #expect(!method.contains("try observationBoundaryQueueGate.reopenAfterAbortedFreshTargetSession("))
    }
}
