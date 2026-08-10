from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")
s = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, got {count}")
    s = s.replace(old, new, 1)


replace_once(
    "    private var events: [Event] = []\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var watchdog: Task<Void, Never>?",
    "    private var events: [Event] = []\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var applicationEvidenceCommitsInFlight: [TuyaReadOnlyConnectionToken: Int] = [:]\n    private var acceptanceSealToken: TuyaReadOnlyConnectionToken?\n    private var watchdog: Task<Void, Never>?",
    "per-token app evidence custody state",
)

replace_once(
    '''        guard phase == .observing else {
            log("application_update_outside_observation_ignored", [
                "generation": String(token.diagnosticGeneration),
                "phase": phase.rawValue
            ])
            return
        }
        guard sdkAccountLoggedIn,''',
    '''        guard phase == .observing else {
            log("application_update_outside_observation_ignored", [
                "generation": String(token.diagnosticGeneration),
                "phase": phase.rawValue
            ])
            return
        }
        guard acceptanceSealToken != token else {
            log("application_update_after_acceptance_boundary_ignored", [
                "generation": String(token.diagnosticGeneration)
            ])
            return
        }
        guard sdkAccountLoggedIn,''',
    "post-seal-boundary callback fence",
)

replace_once(
    '''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)''',
    '''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationEvidenceCommitsInFlight[token, default: 0] += 1
        defer {
            let current = applicationEvidenceCommitsInFlight[token] ?? 0
            if current <= 1 {
                applicationEvidenceCommitsInFlight.removeValue(forKey: token)
            } else {
                applicationEvidenceCommitsInFlight[token] = current - 1
            }
        }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)''',
    "application evidence in-flight custody",
)

replace_once(
    '''                switch TuyaAuthenticatedReadOnlyPreflight.verdict(for: self.ledgerSnapshot) {
                case .readyForStationaryMapping:''',
    '''                if (self.applicationEvidenceCommitsInFlight[token] ?? 0) > 0 {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }

                switch TuyaAuthenticatedReadOnlyPreflight.verdict(for: self.ledgerSnapshot) {
                case .readyForStationaryMapping:''',
    "watchdog evidence-commit interlock",
)

replace_once(
    '''                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.sealedAcceptedEventPrefix = self.events
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()''',
    '''                    self.acceptanceSealToken = token
                    let acceptedEventPrefixCandidate = self.events
                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.sealedAcceptedEventPrefix = acceptedEventPrefixCandidate
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()''',
    "pre-await acceptance boundary snapshot",
)

replace_once(
    '''                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical readiness sealing violated the current internal session lifecycle: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_lifecycle_rejected"
                        )
                    }
                    return''',
    '''                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical readiness sealing violated the current internal session lifecycle: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_lifecycle_rejected"
                        )
                    }
                    if self.acceptanceSealToken == token {
                        self.acceptanceSealToken = nil
                    }
                    return''',
    "acceptance boundary release",
)

replace_once(
    '''    private func resetDiscoverySessionOnly() {
        sealedAcceptedEventPrefix = nil
        correlationSession?.abandonCurrentWindow()''',
    '''    private func resetDiscoverySessionOnly() {
        sealedAcceptedEventPrefix = nil
        acceptanceSealToken = nil
        correlationSession?.abandonCurrentWindow()''',
    "fresh-attempt seal-boundary reset",
)

APP.write_text(s)

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence export seal")
struct TuyaAcceptedApplicationEvidenceSealSourceTests {
    @Test("application evidence stays in-flight from before package admission through app event append")
    func applicationCommitBridgesPackageAndAppEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("private var applicationEvidenceCommitsInFlight: [TuyaReadOnlyConnectionToken: Int] = [:]"))
        #expect(app.contains("private var acceptanceSealToken: TuyaReadOnlyConnectionToken?"))

        let receive = String(try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        guard let boundaryFence = receive.range(of: "guard acceptanceSealToken != token else"),
              let increment = receive.range(of: "applicationEvidenceCommitsInFlight[token, default: 0] += 1"),
              let packageAdmission = receive.range(of: "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"),
              let appEvent = receive.range(of: "log(\"tuya_application_update\"") else {
            Issue.record("Application callback must expose the complete cross-actor evidence custody sequence.")
            throw SourceContractError.sectionMissing
        }

        #expect(boundaryFence.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < packageAdmission.lowerBound)
        #expect(packageAdmission.lowerBound < appEvent.lowerBound)
        #expect(receive.contains("defer {"))
        #expect(receive.contains("applicationEvidenceCommitsInFlight.removeValue(forKey: token)"))
    }

    @Test("watchdog cannot seal or no-data-timeout while current-generation app evidence commit is suspended")
    func watchdogDefersTerminalDecisionsForInFlightEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        guard let inFlight = watchdog.range(of: "applicationEvidenceCommitsInFlight[token] ?? 0"),
              let verdict = watchdog.range(of: "TuyaAuthenticatedReadOnlyPreflight.verdict(for: self.ledgerSnapshot)"),
              let timeout = watchdog.range(of: "markApplicationObservationTimedOut(for: token)") else {
            Issue.record("Watchdog must gate acceptance and no-data timeout behind app-evidence commit completion.")
            throw SourceContractError.sectionMissing
        }

        #expect(inFlight.lowerBound < verdict.lowerBound)
        #expect(inFlight.lowerBound < timeout.lowerBound)
        #expect(watchdog.contains("Task.sleep(for: .milliseconds(100))"))
        #expect(watchdog.contains("continue"))
    }

    @Test("seal boundary and accepted event candidate are established before package seal suspension")
    func acceptanceBoundaryPrecedesSealAwait() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        guard let boundary = watchdog.range(of: "self.acceptanceSealToken = token"),
              let candidate = watchdog.range(of: "let acceptedEventPrefixCandidate = self.events"),
              let packageSeal = watchdog.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let freeze = watchdog.range(of: "self.sealedAcceptedEventPrefix = acceptedEventPrefixCandidate") else {
            Issue.record("Acceptance must own a pre-await app-event boundary around the package seal.")
            throw SourceContractError.sectionMissing
        }

        #expect(boundary.lowerBound < candidate.lowerBound)
        #expect(candidate.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < freeze.lowerBound)
        #expect(!watchdog.contains("self.sealedAcceptedEventPrefix = self.events"))
    }

    @Test("post-boundary application callback cannot call the ledger")
    func postBoundaryCallbackCannotEnterAcceptedPackagePrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = String(try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        guard let boundaryFence = receive.range(of: "guard acceptanceSealToken != token else"),
              let returnAfterFence = receive.range(of: "return", range: boundaryFence.upperBound..<receive.endIndex),
              let packageAdmission = receive.range(of: "sessionLedger.recordApplicationUpdate", range: returnAfterFence.upperBound..<receive.endIndex) else {
            Issue.record("Post-boundary callbacks must return before package application-evidence admission.")
            throw SourceContractError.sectionMissing
        }

        #expect(boundaryFence.lowerBound < returnAfterFence.lowerBound)
        #expect(returnAfterFence.lowerBound < packageAdmission.lowerBound)
        #expect(receive.contains("application_update_after_acceptance_boundary_ignored"))
    }

    @Test("accepted export stays frozen and a fresh correlation clears only the prior seal boundary")
    func exportAndFreshAttemptPreserveGenerationBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let export = String(try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        ))
        #expect(export.contains("guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix"))
        #expect(export.contains("events: sealedAcceptedEventPrefix"))
        #expect(!export.contains("events: events\n"))

        let reset = String(try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        ))
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(reset.contains("acceptanceSealToken = nil"))
        #expect(!reset.contains("applicationEvidenceCommitsInFlight.removeAll"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
''')
