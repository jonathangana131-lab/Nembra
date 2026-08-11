import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application-timeout terminal presentation race")
struct TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("timeout completion cannot overwrite a newer app terminal after actor suspension")
    func timeoutCompletionRevalidatesPresentationOwnership() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: source,
            from: "if self.applicationUpdateAdmissionsInFlight == 0,",
            to: "try? await Task.sleep(for: .seconds(1))"
        ))

        let terminal = try #require(watchdog.range(
            of: "try await sessionLedger.markApplicationObservationTimedOut(for: token)"
        ))
        let phaseWrite = try #require(watchdog.range(
            of: "self.phase = .failed",
            range: terminal.upperBound..<watchdog.endIndex
        ))
        let postAwaitOwnership = String(watchdog[terminal.upperBound..<phaseWrite.lowerBound])

        // Foreground/view/source teardown can run while the package actor commits the timeout.
        // Once another path has already changed app-local terminal ownership, the resumed timeout
        // must not replace that more specific failure with a stale "no application update" reason.
        #expect(postAwaitOwnership.contains("self.currentConnectionToken == token"))
        #expect(postAwaitOwnership.contains("self.phase == .observing"))
    }

    @Test("timeout message remains downstream of the post-await ownership fence")
    func timeoutCopyIsPublishedOnlyByCurrentObservationOwner() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: source,
            from: "if self.applicationUpdateAdmissionsInFlight == 0,",
            to: "try? await Task.sleep(for: .seconds(1))"
        ))

        let terminal = try #require(watchdog.range(
            of: "try await sessionLedger.markApplicationObservationTimedOut(for: token)"
        ))
        let message = try #require(watchdog.range(
            of: "Authenticated session produced no application update before the observation deadline.",
            range: terminal.upperBound..<watchdog.endIndex
        ))
        let postAwait = String(watchdog[terminal.upperBound..<message.lowerBound])

        #expect(postAwait.contains("self.currentConnectionToken == token"))
        #expect(postAwait.contains("self.phase == .observing"))
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
