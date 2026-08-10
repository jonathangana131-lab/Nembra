from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAlreadyTerminalObservationContinuitySourceTests.swift")
source = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    source = source.replace(old, new, 1)

replace_once(
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await invalidateObservationContinuity(
                token: token,
                message: "Application receipt arrived after authenticated observation continuity was already invalid.",
                kind: "application_observation_continuity_invalidated"
            )''',
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await mirrorAlreadyTerminalObservationContinuity(
                token: token,
                message: "Application receipt crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                kind: "application_observation_continuity_invalidated"
            )''',
"application continuity mirror")

replace_once(
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness exceeded the accepted continuous-observation horizon.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return''',
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.mirrorAlreadyTerminalObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return''',
"watchdog continuity mirror")

replace_once(
'''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical acceptance sealing encountered a monotonic-clock regression.",
                            kind: "accepted_prefix_seal_clock_regressed"
                        )
                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }''',
'''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical acceptance sealing encountered a monotonic-clock regression.",
                            kind: "accepted_prefix_seal_clock_regressed"
                        )
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                        await self.mirrorAlreadyTerminalObservationContinuity(
                            token: token,
                            message: "Canonical acceptance crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                            kind: "accepted_prefix_seal_continuity_invalidated"
                        )
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical readiness sealing violated the current internal session lifecycle: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_lifecycle_rejected"
                        )
                    }''',
"seal terminal classification")

needle = '''    private func invalidateObservationContinuity(
'''
helper = '''    /// Mirrors a terminal continuity verdict already committed by the package mutation that threw
    /// `observationContinuityInvalidated`. The package clears its current token before throwing,
    /// so a second ledger terminal here would fabricate a retirement failure.
    private func mirrorAlreadyTerminalObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        watchdog?.cancel()
        watchdog = nil
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateObservationContinuity(
'''
if source.count(needle) != 1:
    raise SystemExit(f"mirror insertion: expected one marker, found {source.count(needle)}")
source = source.replace(needle, helper, 1)
APP.write_text(source)

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app already-terminal observation continuity")
struct TuyaAlreadyTerminalObservationContinuitySourceTests {
    @Test("package continuity error retires token before it throws")
    func packageContinuityErrorIsAlreadyTerminal() throws {
        let ledger = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")
        guard let functionStart = ledger.range(of: "private func requireContinuousAuthenticatedObservation(at now: UInt64) throws") else {
            Issue.record("Expected package continuity guard was not found")
            throw SourceContractError.sectionMissing
        }
        let continuity = ledger[functionStart.lowerBound...]
        guard let clear = continuity.range(of: "currentToken = nil"),
              let thrown = continuity.range(of: "throw MutationError.observationContinuityInvalidated") else {
            Issue.record("Expected terminal continuity mutation was not found")
            throw SourceContractError.sectionMissing
        }
        #expect(clear.lowerBound < thrown.lowerBound)
    }

    @Test("three package-terminal continuity catches mirror instead of terminalizing twice")
    func packageTerminalCatchesOnlyMirror() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.components(separatedBy: "mirrorAlreadyTerminalObservationContinuity(").count - 1 >= 4)
        #expect(app.contains("accepted_prefix_seal_continuity_invalidated"))
        #expect(app.contains("accepted_prefix_seal_lifecycle_rejected"))

        let application = try section(in: app, from: "private func receivedApplicationUpdate", to: "private func startWatchdog")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        #expect(String(application).contains("catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated"))
        #expect(String(application).contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(String(watchdog).contains("mirrorAlreadyTerminalObservationContinuity"))
    }

    @Test("mirror helper mutates app ownership only")
    func mirrorHelperDoesNotInventSecondLedgerTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(in: app, from: "private func mirrorAlreadyTerminalObservationContinuity", to: "private func invalidateObservationContinuity")
        #expect(helper.contains("currentConnectionToken == token"))
        #expect(helper.contains("watchdog?.cancel()"))
        #expect(helper.contains("currentConnectionToken = nil"))
        #expect(helper.contains("localBLESettlementToken = nil"))
        #expect(helper.contains("sdkLocalBLEOnline = false"))
        #expect(helper.contains("driver = nil"))
        #expect(helper.contains("refreshLedgerSnapshot"))
        #expect(helper.contains("phase = .failed"))
        #expect(!helper.contains("sessionLedger."))
        #expect(!helper.contains("markObservationContinuityInvalidated"))
        #expect(!helper.contains("markInternalLifecycleFailure"))
        #expect(!helper.contains("endConnection"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''')

for required in ("mirrorAlreadyTerminalObservationContinuity", "accepted_prefix_seal_continuity_invalidated", "accepted_prefix_seal_lifecycle_rejected"):
    if required not in APP.read_text():
        raise SystemExit(f"missing mirror marker: {required}")
print("terminal continuity mirror applied")
