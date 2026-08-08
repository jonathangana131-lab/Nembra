from pathlib import Path

p = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = p.read_text()

old = '''            let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)
            // No actor suspension may occur between the authority-fenced recorder
            // return and typed queue commit. A callback cannot interleave here on
            // MainActor and relabel this exact Horizon epoch.
            let committedHorizon = try recordedHorizon.markBoundaryRecorded(
                on: &observationBoundaryQueueGate,
                lastProcessedQueueSequence: lastProcessedEventSequence
            )

            let data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)
'''
new = '''            let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)
            // No actor suspension may occur between the authority-fenced recorder
            // return and typed queue commit. If that exact commit loses lifecycle
            // authority, #507's producer-issued recorded-H token quarantines the
            // durable H without fabricating terminal/frozen success.
            let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary
            do {
                committedHorizon = try recordedHorizon.markBoundaryRecorded(
                    on: &observationBoundaryQueueGate,
                    lastProcessedQueueSequence: lastProcessedEventSequence
                )
            } catch {
                _ = try? observationBoundaryQueueGate.abortRecordedHorizonBeforeGateCommit(
                    recordedHorizon
                )
                throw error
            }

            let data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)
'''
count = s.count(old)
if count != 1:
    raise SystemExit(f'expected exactly one Horizon commit seam, found {count}')
s = s.replace(old, new, 1)
p.write_text(s)

t = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerRecordedHorizonRecoveryTests.swift')
if t.exists():
    raise SystemExit('controller recorded-H recovery test already exists')
t.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Controller integration contract for #507's producer-issued recorded-H quarantine.
/// This is software lifecycle truth only; it establishes no physical ES80 evidence.
struct ForegroundCoreBluetoothCaptureControllerRecordedHorizonRecoveryTests {
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

    @Test("durable Horizon commit failure quarantines exact recorded H before generic failure")
    func recordedHorizonCommitFailureUsesProducerQuarantine() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "            let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)")?.lowerBound)
        let end = try #require(source.range(of: "            let data = try await recorder.encodedJSON", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        let record = try #require(section.range(of: "horizonAdmission.recordBoundary")?.lowerBound)
        let commit = try #require(section.range(of: "recordedHorizon.markBoundaryRecorded")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortRecordedHorizonBeforeGateCommit")?.lowerBound)
        #expect(section.distance(from: section.startIndex, to: record) < section.distance(from: section.startIndex, to: commit))
        #expect(section.distance(from: section.startIndex, to: commit) < section.distance(from: section.startIndex, to: quarantine))
        #expect(!section[commit..<quarantine].contains("await"))
    }
}
''')
