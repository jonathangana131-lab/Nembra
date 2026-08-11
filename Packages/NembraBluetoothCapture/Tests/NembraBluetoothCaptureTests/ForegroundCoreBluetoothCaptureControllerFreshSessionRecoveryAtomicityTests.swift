import Foundation
import Testing

@Suite("Fresh-session recovery failure-atomic publication")
struct ForegroundCoreBluetoothCaptureControllerFreshSessionRecoveryAtomicityTests {
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
        before nextName: String,
        in source: String
    ) throws -> Substring {
        let start = try #require(source.range(of: "private func \(name)("))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: "private func \(nextName)("))
        return tail[..<end.lowerBound]
    }

    private static func assertFailureAtomicInstall(
        _ method: Substring,
        stagedReopenCall: String,
        liveReopenCall: String
    ) throws {
        let declaration = try #require(
            method.range(of: "var reopenedGate = observationBoundaryQueueGate")
        )
        let validation = try #require(method.range(of: stagedReopenCall))
        let transition = try #require(
            method.range(of: "try artifactAuthorityFence.transition(")
        )
        let publication = try #require(
            method.range(of: "observationBoundaryQueueGate = reopenedGate")
        )

        #expect(declaration.lowerBound < validation.lowerBound)
        #expect(validation.lowerBound < transition.lowerBound)
        #expect(transition.lowerBound < publication.lowerBound)
        #expect(!method.contains(liveReopenCall))

        let catchRange = try #require(method.range(
            of: "        } catch {",
            range: transition.upperBound..<method.endIndex
        ))
        let postTransition = method[transition.upperBound..<catchRange.lowerBound]
        #expect(!postTransition.contains("try "))
        #expect(!postTransition.contains("await "))
        #expect(postTransition.contains("recorder = freshSession.recorder"))
        #expect(postTransition.contains("observationBoundaryQueueGate = reopenedGate"))
    }

    @Test("terminal-H fresh-session gate is fully prevalidated before canonical fence transition")
    func terminalRecoveryIsFailureAtomic() throws {
        let source = try Self.controllerSource()
        let method = try Self.method(
            named: "completeTerminalFreshTargetSessionIfReady",
            before: "scheduleAbortedFreshTargetSessionRecoveryIfNeeded",
            in: source
        )

        try Self.assertFailureAtomicInstall(
            method,
            stagedReopenCall: "try reopenedGate.reopenAfterTerminalFreshTargetSession(",
            liveReopenCall: "try observationBoundaryQueueGate.reopenAfterTerminalFreshTargetSession("
        )
    }

    @Test("abort-quarantine fresh-session gate is fully prevalidated before canonical fence transition")
    func abortRecoveryIsFailureAtomic() throws {
        let source = try Self.controllerSource()
        let method = try Self.method(
            named: "completeAbortedFreshTargetSessionIfReady",
            before: "beginTargetSessionIfNeeded",
            in: source
        )

        try Self.assertFailureAtomicInstall(
            method,
            stagedReopenCall: "try reopenedGate.reopenAfterAbortedFreshTargetSession(",
            liveReopenCall: "try observationBoundaryQueueGate.reopenAfterAbortedFreshTargetSession("
        )
    }
}