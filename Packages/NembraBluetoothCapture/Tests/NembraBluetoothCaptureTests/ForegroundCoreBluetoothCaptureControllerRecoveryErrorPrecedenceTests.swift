import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Source contracts for the two recorded-boundary recovery seams where durable
/// recorder evidence already exists but the typed MainActor queue commit fails.
/// Exact quarantine failure is stronger lifecycle evidence and must never be hidden
/// by `try?` while the controller reports only the triggering commit error.
struct ForegroundCoreBluetoothCaptureControllerRecoveryErrorPrecedenceTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    private static func finalizedHorizonSection(in source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "\n    private func beginTargetSessionIfNeeded",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    private static func readyBoundarySection(in source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "\n    private func validateBoundaryAuthority",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    @Test("recorded Horizon quarantine failure outranks the triggering queue-commit error")
    func recordedHorizonRecoveryPreservesErrorPrecedence() throws {
        let source = try Self.controllerSource()
        let section = try Self.finalizedHorizonSection(in: source)
        let recoveryStart = try #require(
            section.range(of: "let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary")?.lowerBound
        )
        let recoveryEnd = try #require(
            section.range(of: "\n            let data: Data", range: recoveryStart..<section.endIndex)?.lowerBound
        )
        let recovery = section[recoveryStart..<recoveryEnd]

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

    @Test("recorded Ready quarantine failure outranks the triggering queue-commit error")
    func recordedReadyRecoveryPreservesErrorPrecedence() throws {
        let source = try Self.controllerSource()
        let section = try Self.readyBoundarySection(in: source)
        let recordedCase = try #require(
            section.range(of: "case let .recorded(recordedReady):")?.lowerBound
        )
        let outerCatch = try #require(
            section.range(of: "\n                } catch {\n                    self.failCapture(error)", range: recordedCase..<section.endIndex)?.lowerBound
        )
        let recovery = section[recordedCase..<outerCatch]

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
