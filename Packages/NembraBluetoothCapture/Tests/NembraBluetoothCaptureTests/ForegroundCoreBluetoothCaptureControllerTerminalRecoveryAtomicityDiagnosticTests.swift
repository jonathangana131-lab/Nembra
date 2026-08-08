import Foundation
import Testing

@Suite("Terminal recovery failure-atomic publication diagnostic")
struct ForegroundCoreBluetoothCaptureControllerTerminalRecoveryAtomicityDiagnosticTests {
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

    private static func terminalRecoveryMethod(in source: String) throws -> Substring {
        let start = try #require(source.range(
            of: "private func completeTerminalFreshTargetSessionIfReady("
        ))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(
            of: "private func scheduleAbortedFreshTargetSessionRecoveryIfNeeded("
        ))
        return tail[..<end.lowerBound]
    }

    @Test("terminal gate preflights before irreversible canonical fence transition")
    func queueGateMustPreflightBeforeFenceTransition() throws {
        let method = try Self.terminalRecoveryMethod(in: Self.controllerSource())
        let declaration = try #require(
            method.range(of: "var reopenedGate = observationBoundaryQueueGate")
        )
        let validation = try #require(
            method.range(of: "try reopenedGate.reopenAfterTerminalFreshTargetSession(")
        )
        let transition = try #require(
            method.range(of: "try artifactAuthorityFence.transition(")
        )
        let publication = try #require(
            method.range(of: "observationBoundaryQueueGate = reopenedGate")
        )

        #expect(declaration.lowerBound < validation.lowerBound)
        #expect(validation.lowerBound < transition.lowerBound)
        #expect(transition.lowerBound < publication.lowerBound)
        #expect(!method.contains(
            "try observationBoundaryQueueGate.reopenAfterTerminalFreshTargetSession("
        ))
    }

    @Test("canonical fence transition is the final fallible terminal install step")
    func fenceTransitionIsFinalFallibleInstallStep() throws {
        let method = try Self.terminalRecoveryMethod(in: Self.controllerSource())
        let transition = try #require(
            method.range(of: "try artifactAuthorityFence.transition(")
        )
        let catchRange = try #require(method.range(
            of: "        } catch {",
            range: transition.upperBound..<method.endIndex
        ))
        let publication = method[transition.upperBound..<catchRange.lowerBound]

        #expect(!publication.contains("try "))
        #expect(!publication.contains("await "))
        #expect(publication.contains("recorder = freshSession.recorder"))
        #expect(publication.contains("observationBoundaryQueueGate = reopenedGate"))
    }
}
