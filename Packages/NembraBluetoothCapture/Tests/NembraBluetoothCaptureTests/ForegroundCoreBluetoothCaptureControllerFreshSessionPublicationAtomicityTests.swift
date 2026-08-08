import Foundation
import Testing

@Suite("Fresh-session failure-atomic publication")
struct ForegroundCoreBluetoothCaptureControllerFreshSessionPublicationAtomicityTests {
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

    private static func method(
        named name: String,
        endingBefore nextName: String,
        in source: String
    ) throws -> Substring {
        let start = try #require(source.range(of: "private func \(name)("))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: "private func \(nextName)("))
        return tail[..<end.lowerBound]
    }

    private static func assertFailureAtomicOrdering(
        in method: Substring,
        reopenCall: String
    ) throws {
        let stagedGateDeclaration = try #require(
            method.range(of: "var reopenedGate = observationBoundaryQueueGate")
        )
        let stagedGateValidation = try #require(
            method.range(of: "try reopenedGate.\(reopenCall)(")
        )
        let fenceTransition = try #require(
            method.range(of: "try artifactAuthorityFence.transition(")
        )
        let recorderPublication = try #require(
            method.range(of: "recorder = freshSession.recorder")
        )
        let stagedGatePublication = try #require(
            method.range(of: "observationBoundaryQueueGate = reopenedGate")
        )

        #expect(stagedGateDeclaration.lowerBound < stagedGateValidation.lowerBound)
        #expect(stagedGateValidation.lowerBound < fenceTransition.lowerBound)
        #expect(fenceTransition.lowerBound < recorderPublication.lowerBound)
        #expect(recorderPublication.lowerBound < stagedGatePublication.lowerBound)

        // A reference-backed authority transition is intentionally irreversible. Once it
        // succeeds, the remaining publication path must contain no throwing queue-gate reopen.
        #expect(!method.contains("try observationBoundaryQueueGate.\(reopenCall)("))

        let afterFence = method[fenceTransition.lowerBound...]
        #expect(afterFence.filter { $0 == "\n" }.count > 0)
        #expect(!afterFence.contains("try reopenedGate."))
    }

    @Test("terminal fresh-session reopen is prevalidated before canonical authority advances")
    func terminalRecoveryIsFailureAtomic() throws {
        let source = try Self.controllerSource()
        let method = try Self.method(
            named: "completeTerminalFreshTargetSessionIfReady",
            endingBefore: "scheduleAbortedFreshTargetSessionRecoveryIfNeeded",
            in: source
        )
        try Self.assertFailureAtomicOrdering(
            in: method,
            reopenCall: "reopenAfterTerminalFreshTargetSession"
        )
    }

    @Test("abort fresh-session reopen is prevalidated before canonical authority advances")
    func abortRecoveryIsFailureAtomic() throws {
        let source = try Self.controllerSource()
        let method = try Self.method(
            named: "completeAbortedFreshTargetSessionIfReady",
            endingBefore: "beginTargetSessionIfNeeded",
            in: source
        )
        try Self.assertFailureAtomicOrdering(
            in: method,
            reopenCall: "reopenAfterAbortedFreshTargetSession"
        )
    }
}