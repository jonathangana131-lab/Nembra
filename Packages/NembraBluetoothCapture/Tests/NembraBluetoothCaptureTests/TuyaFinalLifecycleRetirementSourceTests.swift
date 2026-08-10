import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture final lifecycle retirement")
struct TuyaFinalLifecycleRetirementSourceTests {
    @Test("every locally known chronology failure has a clock-independent retirement route")
    func chronologyFailuresCannotLeaveHiddenCallbackAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let authStart = try section(
            app,
            from: "let token = try await self.sessionLedger.beginConnection()",
            to: "newDriver.connect("
        )
        #expect(authStart.contains("self.currentConnectionToken = token"))
        #expect(authStart.contains("markAuthenticationStarted"))
        #expect(authStart.contains("invalidateChronologyIntegrity"))
        guard let publish = authStart.range(of: "self.currentConnectionToken = token"),
              let mutate = authStart.range(of: "markAuthenticationStarted") else {
            Issue.record("Could not prove token publication precedes auth-start mutation.")
            return
        }
        #expect(publish.lowerBound < mutate.lowerBound)

        let watchdog = try section(app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        #expect(watchdog.contains("observation_clock_regressed"))
        #expect(watchdog.contains("invalidateChronologyIntegrity"))
        #expect(watchdog.contains("observation_poll_gap_exceeded"))
        #expect(watchdog.contains("invalidateObservationContinuity"))
        #expect(watchdog.contains("markApplicationObservationTimedOut"))
        #expect(watchdog.contains("authenticated_application_timeout_chronology_fallback"))
    }

    @Test("terminal helpers never silently discard a failed authority retirement")
    func appTerminalHelpersFallBackToNoClockRetirement() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let tail = try section(app, from: "private func recordObservedTransportLoss", to: "private func refreshLedgerSnapshot")
        #expect(tail.contains("sessionLedger.endConnection"))
        #expect(tail.contains("sessionLedger.markSourceAuthorityInvalidated"))
        #expect(tail.contains("sessionLedger.markObservationContinuityInvalidated"))
        #expect(tail.contains("invalidateChronologyIntegrity"))
        #expect(!tail.contains("try? await sessionLedger.endConnection"))
        #expect(!tail.contains("try? await sessionLedger.markSourceAuthorityInvalidated"))
        #expect(!tail.contains("try? await sessionLedger.markObservationContinuityInvalidated"))
    }

    private func section(_ source: String, from start: String, to end: String) throws -> Substring {
        guard let first = source.range(of: start),
              let last = source.range(of: end, range: first.upperBound..<source.endIndex) else {
            throw SourceContractError.missing
        }
        return source[first.lowerBound..<last.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum SourceContractError: Error { case missing }
}
