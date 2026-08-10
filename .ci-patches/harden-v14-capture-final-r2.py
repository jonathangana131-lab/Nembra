from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFinalLifecycleRetirementSourceTests.swift")


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


app = APP.read_text()

# Once beginConnection mints package callback authority, publish the owner token locally before
# the next clock-sampling mutation. A regressed clock during markAuthenticationStarted must retire
# that exact package generation instead of falling into a UI-only failure.
app = once(
    app,
'''            do {
                let token = try await self.sessionLedger.beginConnection()
                try await self.sessionLedger.markAuthenticationStarted(for: token)
                self.currentConnectionToken = token
                await self.refreshLedgerSnapshot()
''',
'''            do {
                let token = try await self.sessionLedger.beginConnection()
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch {
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated-session chronology could not start safely: \(error.localizedDescription)",
                        kind: "session_auth_start_rejected"
                    )
                    return
                }
                await self.refreshLedgerSnapshot()
''',
    "auth-start generation retirement",
)

# A locally observed monotonic regression is chronology failure, not an observation-gap or
# disconnect fact. Use the no-clock terminal directly.
app = once(
    app,
'''                guard now >= previousPollUptime else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted by a monotonic-clock regression.", "observation_clock_regressed")
                    return
                }
''',
'''                guard now >= previousPollUptime else {
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated observation chronology failed closed because the monotonic clock regressed.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }
''',
    "watchdog clock regression terminal",
)

# A >5s watchdog gap is continuity evidence, not clock-integrity evidence. Route through the app
# terminal helper so a secondary clock failure while sealing the gap still falls back to the
# no-clock retirement path.
app = once(
    app,
'''                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.", "observation_poll_gap_exceeded")
                    return
                }
''',
'''                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.",
                        kind: "observation_poll_gap_exceeded"
                    )
                    return
                }
''',
    "watchdog long-gap terminal",
)

# The no-application deadline must not clear app state if the package terminal failed to retire
# callback authority. Preserve the timeout classification when possible, otherwise fall back to
# clock-independent chronology retirement.
app = once(
    app,
'''                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }
''',
'''                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch {
                        await self.invalidateChronologyIntegrity(
                            token: token,
                            message: "Authenticated session reached the no-application deadline while chronology could not be sealed safely.",
                            kind: "authenticated_application_timeout_chronology_fallback"
                        )
                        return
                    }
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }
''',
    "no-application terminal retirement",
)

APP.write_text(app)

TEST.write_text(r'''import Foundation
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
''')
