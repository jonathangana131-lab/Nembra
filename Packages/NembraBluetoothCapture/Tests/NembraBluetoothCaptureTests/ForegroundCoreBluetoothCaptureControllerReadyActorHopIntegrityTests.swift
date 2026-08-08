import Foundation
import Testing

@Suite("Foreground CoreBluetooth Ready actor-hop integrity")
struct ForegroundCoreBluetoothCaptureControllerReadyActorHopIntegrityTests {
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

    private static func readySection() throws -> Substring {
        let source = try controllerSource()
        let start = try #require(
            source.range(of: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded() {")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    private func requireForegroundEvidenceIntegrity() throws {",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    @Test("Ready revalidates exact authority after FIFO suspension before first recorder attempt")
    func readyAuthorityDriftIsPreAttemptFailure() throws {
        let section = try Self.readySection()

        let flush = try #require(
            section.range(of: "await self.flushPendingEvents(through: admission.queueCutoff)")
        )
        let authorityCheck = try #require(
            section.range(
                of: "try self.validateBoundaryAuthority(admission.authority)",
                range: flush.upperBound..<section.endIndex
            )
        )
        let abandonment = try #require(
            section.range(
                of: "admission.abandonBeforeRecorderAttempt()",
                range: authorityCheck.upperBound..<section.endIndex
            )
        )
        let firstRecorderAttempt = try #require(
            section.range(
                of: "admission.recordBoundaryWithMutationOutcome(on: recorder)",
                range: abandonment.upperBound..<section.endIndex
            )
        )

        #expect(flush.lowerBound < authorityCheck.lowerBound)
        #expect(authorityCheck.lowerBound < abandonment.lowerBound)
        #expect(abandonment.lowerBound < firstRecorderAttempt.lowerBound)
    }

    @Test("Ready rechecks foreground integrity after recorder actor hop before queue commit")
    func recordedReadyRechecksForegroundBeforeCommit() throws {
        let section = try Self.readySection()
        let recordedCase = try #require(section.range(of: "case let .recorded(recordedReady):"))
        let commit = try #require(
            section.range(
                of: "self.committedReadyEpoch = try recordedReady.markBoundaryRecorded(",
                range: recordedCase.upperBound..<section.endIndex
            )
        )
        let integrityCheck = try #require(
            section.range(
                of: "try self.requireForegroundEvidenceIntegrity()",
                range: recordedCase.upperBound..<commit.lowerBound
            )
        )
        let interlock = section[recordedCase.upperBound..<commit.lowerBound]

        #expect(!interlock.contains("await"))
        #expect(integrityCheck.lowerBound < commit.lowerBound)
    }

    @Test("recorded Ready quarantine failure outranks triggering foreground or queue-commit failure")
    func recordedReadyRecoveryErrorPrecedenceIsExplicit() throws {
        let section = try Self.readySection()
        let recordedCase = try #require(section.range(of: "case let .recorded(recordedReady):"))
        let tail = section[recordedCase.lowerBound..<section.endIndex]

        let preservedFailure = try #require(tail.range(of: "let recordedReadyFailure = error"))
        let quarantine = try #require(
            tail.range(
                of: "abortRecordedReadyBeforeGateCommit(",
                range: preservedFailure.upperBound..<tail.endIndex
            )
        )
        let rethrow = try #require(
            tail.range(
                of: "throw recordedReadyFailure",
                range: quarantine.upperBound..<tail.endIndex
            )
        )

        #expect(!tail.contains("try? self.observationBoundaryQueueGate.abortRecordedReadyBeforeGateCommit"))
        #expect(preservedFailure.lowerBound < quarantine.lowerBound)
        #expect(quarantine.lowerBound < rethrow.lowerBound)
    }
}
