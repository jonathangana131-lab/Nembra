import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture session terminal retirement truth")
struct TuyaSessionTerminalRetirementSourceTests {
    @Test("auth-start rejection cannot strand a freshly minted generation")
    func authenticationStartFailureRetiresMintedGeneration() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let begin = app.range(of: "private func beginOfficialConnection(candidate:"),
              let authenticated = app.range(of: "private func authenticated(token:", range: begin.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate official connection start.")
            return
        }

        let source = String(app[begin.lowerBound..<authenticated.lowerBound])
        guard let beginConnection = source.range(of: "sessionLedger.beginConnection()"),
              let authStart = source.range(of: "sessionLedger.markAuthenticationStarted(for: token)") else {
            Issue.record("Expected ledger generation + auth-start chronology is missing.")
            return
        }

        let prefixThroughAuthStart = String(source[source.startIndex..<authStart.lowerBound])
        #expect(beginConnection.lowerBound < authStart.lowerBound)
        #expect(prefixThroughAuthStart.contains("currentConnectionToken = token"))
        #expect(source.contains("invalidateInternalLifecycle"))
    }

    @Test("local settlement clock failure uses the clock-independent terminal")
    func invalidSettlementClockCannotRetryTheBrokenClock() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let invalidClock = app.range(of: "case .invalidClock:", range: authenticated.upperBound..<app.endIndex),
              let authFailure = app.range(of: "private func authenticationFailed", range: invalidClock.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate local-BLE invalid-clock branch.")
            return
        }

        let branch = String(app[invalidClock.lowerBound..<authFailure.lowerBound])
        #expect(branch.contains("invalidateInternalLifecycle"))
        #expect(!branch.contains("authenticationAcquisitionFailed"))
        #expect(!branch.contains("invalidateSourceAuthority"))
    }

    @Test("authentication chronology rejection cannot masquerade as source drift")
    func authenticationPromotionRejectionUsesInternalLifecycleTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let observedOnline = app.range(of: "case .observedOnline:"),
              let keepWaiting = app.range(of: "case .keepWaiting:", range: observedOnline.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate authenticated promotion branch.")
            return
        }

        let branch = String(app[observedOnline.lowerBound..<keepWaiting.lowerBound])
        #expect(branch.contains("sessionLedger.markAuthenticated(for: token"))
        #expect(branch.contains("invalidateInternalLifecycle"))
        #expect(!branch.contains("invalidateSourceAuthority"))
    }

    @Test("watchdog monotonic regression cannot silently drop app ownership")
    func watchdogClockRegressionUsesNoClockRetirement() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let watchdog = app.range(of: "private func startWatchdog(token:"),
              let regression = app.range(of: "guard now >= previousPollUptime else", range: watchdog.upperBound..<app.endIndex),
              let gap = app.range(of: "let gap = now - previousPollUptime", range: regression.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate watchdog clock-regression branch.")
            return
        }

        let branch = String(app[regression.lowerBound..<gap.lowerBound])
        #expect(branch.contains("invalidateInternalLifecycle"))
        #expect(!branch.contains("markObservationContinuityInvalidated"))
        #expect(!branch.contains("currentConnectionToken = nil"))
    }

    @Test("terminal helpers never discard app ownership after a swallowed ledger failure")
    func terminalHelpersDoNotUseTryQuestionMarkBeforeOwnershipClear() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private func invalidateInternalLifecycle("))
        #expect(app.contains("sessionLedger.markInternalLifecycleFailure(for: token)"))

        #expect(!app.contains("try? await sessionLedger.markAuthenticationFailed(for: token)"))
        #expect(!app.contains("try? await sessionLedger.markSourceAuthorityInvalidated(for: token)"))
        #expect(!app.contains("try? await sessionLedger.markObservationContinuityInvalidated(for: token)"))
        #expect(!app.contains("try? await sessionLedger.endConnection(for: token)"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
