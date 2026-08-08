import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerRecoveryErrorPrecedenceTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("recorded Horizon quarantine failure outranks triggering queue-commit error")
    func recordedHorizonRecoveryPreservesErrorPrecedence() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary")?.lowerBound)
        let end = try #require(source.range(of: "\n            let data: Data", range: start..<source.endIndex)?.lowerBound)
        let recovery = source[start..<end]
        #expect(recovery.contains("let recordedHorizonFailure = error"))
        #expect(recovery.contains("abortRecordedHorizonBeforeGateCommit"))
        #expect(recovery.contains("throw recordedHorizonFailure"))
        #expect(!recovery.contains("try? observationBoundaryQueueGate.abortRecordedHorizonBeforeGateCommit"))
        let quarantine = try #require(recovery.range(of: "abortRecordedHorizonBeforeGateCommit")?.lowerBound)
        let originalRethrow = try #require(recovery.range(of: "throw recordedHorizonFailure")?.lowerBound)
        #expect(quarantine < originalRethrow)
        let between = recovery[quarantine..<originalRethrow]
        #expect(between.contains("catch"))
        #expect(between.contains("throw error"))
    }

    @Test("recorded Ready quarantine failure outranks triggering queue-commit error")
    func recordedReadyRecoveryPreservesErrorPrecedence() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "case let .recorded(recordedReady):")?.lowerBound)
        let end = try #require(source.range(of: "\n                } catch {\n                    self.failCapture(error)", range: start..<source.endIndex)?.lowerBound)
        let recovery = source[start..<end]
        #expect(recovery.contains("let recordedReadyFailure = error"))
        #expect(recovery.contains("abortRecordedReadyBeforeGateCommit"))
        #expect(recovery.contains("throw recordedReadyFailure"))
        #expect(!recovery.contains("try? self.observationBoundaryQueueGate.abortRecordedReadyBeforeGateCommit"))
        let quarantine = try #require(recovery.range(of: "abortRecordedReadyBeforeGateCommit")?.lowerBound)
        let originalRethrow = try #require(recovery.range(of: "throw recordedReadyFailure")?.lowerBound)
        #expect(quarantine < originalRethrow)
        let between = recovery[quarantine..<originalRethrow]
        #expect(between.contains("catch"))
        #expect(between.contains("throw error"))
    }
}
