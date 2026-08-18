import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya package-owned incomplete horizon source contract")
struct TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("watchdog has no independent app-owned zero-payload deadline")
    func watchdogDefersIncompleteHorizonDecisionToPackageLedger() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: source,
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            to: "private func recordObservedTransportLoss("
        )

        // The package preflight/ledger owns the canonical 60-second incomplete-session horizon.
        // The app must not recreate that decision from a UI-derived age/count check.
        #expect(!watchdog.contains("(self.canonicalObservedAgeSeconds ?? 0) > 60"))
        #expect(!watchdog.contains("if self.applicationUpdateAdmissionsInFlight == 0,"))
        #expect(!watchdog.contains("authenticated_application_timeout"))

        #expect(watchdog.contains("try await self.sessionLedger.observeCurrentConnection(for: token)"))
        #expect(watchdog.contains("TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached"))
        #expect(watchdog.contains("await self.retirePackageIncompleteObservationHorizon(token: token)"))
    }

    @Test("package horizon retirement is terminal without fabricating BLE offline")
    func packageHorizonRetirementPreservesTransportTruth() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(
            in: source,
            from: "private func retirePackageIncompleteObservationHorizon(",
            to: "private func recordObservedTransportLoss("
        )

        // The package-issued horizon verdict may retire callback/session authority, but it is not
        // evidence that the Tuya local-BLE transport disconnected. Preserve the last witnessed
        // transport bit and drop only the app's driver ownership after terminal sealing.
        #expect(helper.contains("markApplicationObservationTimedOut(for: token)"))
        #expect(helper.contains("currentConnectionToken == token"))
        #expect(helper.contains("phase == .observing"))
        #expect(helper.contains("driver = nil"))
        #expect(!helper.contains("sdkLocalBLEOnline = false"))
        #expect(!helper.contains("recordObservedTransportLoss"))
        #expect(helper.contains("no application update") || helper.contains("application update before the observation deadline"))
    }

    @Test("ordinary continuity mirroring also preserves last witnessed transport truth")
    func continuityTerminalPreservesTransportTruth() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(
            in: source,
            from: "private func mirrorAlreadyTerminalObservationContinuity(",
            to: "private func invalidateObservationContinuity("
        )
        #expect(!helper.contains("sdkLocalBLEOnline = false"))
        #expect(helper.contains("driver = nil"))
        #expect(helper.contains("no disconnect") || helper.contains("does not claim BLE"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return String(source[a.lowerBound..<b.lowerBound])
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
