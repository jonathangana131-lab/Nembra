import Foundation
import Testing

@Suite("Fresh-session recovery publication atomicity")
struct ForegroundCoreBluetoothCaptureControllerRecoveryAtomicityTests {
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

    private static func requireAtomicPublication(
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
        let stagedGatePublication = try #require(
            method.range(of: "observationBoundaryQueueGate = reopenedGate")
        )

        #expect(stagedGateDeclaration.lowerBound < stagedGateValidation.lowerBound)
        #expect(stagedGateValidation.lowerBound < fenceTransition.lowerBound)
        #expect(fenceTransition.lowerBound < stagedGatePublication.lowerBound)
        #expect(!method.contains("try observationBoundaryQueueGate.\(reopenCall)("))
    }

    @Test("abort recovery prevalidates queue-gate reopen before canonical fence transition")
    func abortRecoveryIsFailureAtomic() throws {
        let source = try Self.controllerSource()
        let method = try Self.method(
            named: "completeAbortedFreshTargetSessionIfReady",
            endingBefore: "beginTargetSessionIfNeeded",
            in: source
        )
        try Self.requireAtomicPublication(
            in: method,
            reopenCall: "reopenAfterAbortedFreshTargetSession"
        )
    }

    @Test("terminal recovery prevalidates queue-gate reopen before canonical fence transition")
    func terminalRecoveryIsFailureAtomic() throws {
        let source = try Self.controllerSource()
        let method = try Self.method(
            named: "completeTerminalFreshTargetSessionIfReady",
            endingBefore: "scheduleAbortedFreshTargetSessionRecoveryIfNeeded",
            in: source
        )
        try Self.requireAtomicPublication(
            in: method,
            reopenCall: "reopenAfterTerminalFreshTargetSession"
        )
    }
}