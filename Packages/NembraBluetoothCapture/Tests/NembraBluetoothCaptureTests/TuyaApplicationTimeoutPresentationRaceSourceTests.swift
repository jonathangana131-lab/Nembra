import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application-timeout terminal presentation race")
struct TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("package-owned incomplete horizon cannot overwrite a newer app terminal after snapshot suspension")
    func timeoutCompletionRevalidatesPresentationOwnership() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: source,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))
        let terminal = try #require(watchdog.range(
            of: "MutationError.incompleteObservationHorizonReached"
        ))
        let mirror = try #require(watchdog.range(
            of: "mirrorAlreadyTerminalIncompleteObservationHorizon(",
            range: terminal.upperBound..<watchdog.endIndex
        ))
        #expect(terminal.lowerBound < mirror.lowerBound)

        let helper = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))
        let initialOwnership = try #require(helper.range(of: "guard currentConnectionToken == token else { return }"))
        let snapshotAwait = try #require(helper.range(of: "await refreshLedgerSnapshot()"))
        let postAwaitOwnership = try #require(helper.range(
            of: "guard phase == .observing else { return }",
            range: snapshotAwait.upperBound..<helper.endIndex
        ))
        let phaseWrite = try #require(helper.range(
            of: "phase = .failed",
            range: postAwaitOwnership.upperBound..<helper.endIndex
        ))

        // Foreground/view/source teardown can run while the package snapshot is refreshed. The
        // already-terminal package verdict may update app presentation only while this exact
        // observing owner remains current; it must never issue a duplicate package terminal.
        #expect(initialOwnership.lowerBound < snapshotAwait.lowerBound)
        #expect(snapshotAwait.lowerBound < postAwaitOwnership.lowerBound)
        #expect(postAwaitOwnership.lowerBound < phaseWrite.lowerBound)
        #expect(!helper.contains("markApplicationObservationTimedOut"))
        #expect(!helper.contains("markObservationContinuityInvalidated"))
    }

    @Test("incomplete-horizon message remains downstream of the post-await ownership fence")
    func timeoutCopyIsPublishedOnlyByCurrentObservationOwner() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))

        let snapshotAwait = try #require(helper.range(
            of: "await refreshLedgerSnapshot()"
        ))
        let ownership = try #require(helper.range(
            of: "guard phase == .observing else { return }",
            range: snapshotAwait.upperBound..<helper.endIndex
        ))
        let messageWrite = try #require(helper.range(
            of: "self.message = message",
            range: ownership.upperBound..<helper.endIndex
        ))

        #expect(snapshotAwait.lowerBound < ownership.lowerBound)
        #expect(ownership.lowerBound < messageWrite.lowerBound)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
