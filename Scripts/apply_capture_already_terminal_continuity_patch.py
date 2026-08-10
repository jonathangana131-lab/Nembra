from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAlreadyTerminalObservationContinuitySourceTests.swift")
source = app_path.read_text()


def replace_exact(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    source = source.replace(old, new, 1)


replace_exact(
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await invalidateObservationContinuity(
                token: token,
                message: "Application receipt arrived after authenticated observation continuity was already invalid.",
                kind: "application_observation_continuity_invalidated"
            )
''',
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await mirrorAlreadyTerminalObservationContinuity(
                token: token,
                message: "Application receipt crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                kind: "application_observation_continuity_invalidated"
            )
''',
"application receipt already-terminal continuity",
)

replace_exact(
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness exceeded the accepted continuous-observation horizon.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
''',
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.mirrorAlreadyTerminalObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
''',
"watchdog already-terminal continuity",
)

replace_exact(
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
                    }
''',
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
                    }
''',
"acceptance seal already-terminal continuity",
)

helper_anchor = '''    private func invalidateObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
'''
if source.count(helper_anchor) != 1:
    raise SystemExit(f"continuity helper anchor: expected one match, found {source.count(helper_anchor)}")
mirror_helper = '''    /// Mirrors a terminal continuity verdict already committed by the package mutation that threw
    /// `observationContinuityInvalidated`. That package path clears its current token before
    /// throwing, so calling another ledger terminal here would manufacture a false retirement
    /// failure. This helper changes app-local ownership/presentation only; it does not claim BLE
    /// disconnect, source loss, a new clock receipt, or a second terminal event.
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

'''
source = source.replace(helper_anchor, mirror_helper + helper_anchor, 1)
app_path.write_text(source)

test_path.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app already-terminal observation continuity")
struct TuyaAlreadyTerminalObservationContinuitySourceTests {
    @Test("package continuity error retires token before it throws")
    func packageContinuityErrorIsAlreadyTerminal() throws {
        let ledger = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")
        let continuity = try section(
            in: ledger,
            from: "private func requireContinuousAuthenticatedObservation(at now: UInt64) throws",
            to: "}"
        )

        guard let clear = continuity.range(of: "currentToken = nil"),
              let thrown = continuity.range(of: "throw MutationError.observationContinuityInvalidated") else {
            Issue.record("Expected terminal continuity mutation was not found")
            throw SourceContractError.sectionMissing
        }
        #expect(clear.lowerBound < thrown.lowerBound)
    }

    @Test("application receipt mirrors package terminal without terminalizing twice")
    func applicationReceiptDoesNotReterminalize() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let body = try catchBody(
            in: app,
            functionStart: "private func receivedApplicationUpdate",
            errorCase: "MutationError.observationContinuityInvalidated"
        )

        #expect(body.contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(!body.contains("invalidateObservationContinuity"))
        #expect(!body.contains("markInternalLifecycleFailure"))
    }

    @Test("watchdog liveness mirrors package terminal without terminalizing twice")
    func watchdogLivenessDoesNotReterminalize() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = try catchBody(
            in: String(watchdog),
            functionStart: "sessionLedger.observeCurrentConnection(for: token)",
            errorCase: "MutationError.observationContinuityInvalidated"
        )

        #expect(body.contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(!body.contains("invalidateObservationContinuity"))
        #expect(!body.contains("markInternalLifecycleFailure"))
    }

    @Test("acceptance seal explicitly mirrors package-terminal continuity")
    func acceptanceSealDoesNotReterminalize() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let seal = try section(
            in: String(watchdog),
            from: "sessionLedger.sealAcceptedObservation(for: token)",
            to: "case .blocked:"
        )
        let body = try catchBody(
            in: String(seal),
            functionStart: "sessionLedger.sealAcceptedObservation(for: token)",
            errorCase: "MutationError.observationContinuityInvalidated"
        )

        #expect(body.contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(!body.contains("invalidateObservationContinuity"))
        #expect(!body.contains("markInternalLifecycleFailure"))
        #expect(String(seal).contains("accepted_prefix_seal_lifecycle_rejected"))
    }

    @Test("mirror helper mutates app ownership only")
    func mirrorHelperDoesNotInventSecondLedgerTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(
            in: app,
            from: "private func mirrorAlreadyTerminalObservationContinuity",
            to: "private func invalidateObservationContinuity"
        )

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

    private func catchBody(in source: String, functionStart: String, errorCase: String) throws -> Substring {
        guard let functionRange = source.range(of: functionStart),
              let catchRange = source.range(of: "catch TuyaAuthenticatedReadOnlySessionLedger.\(errorCase) {", range: functionRange.lowerBound..<source.endIndex),
              let nextCatch = source.range(of: "} catch", range: catchRange.upperBound..<source.endIndex) else {
            Issue.record("Expected typed catch missing: \(errorCase)")
            throw SourceContractError.sectionMissing
        }
        return source[catchRange.lowerBound..<nextCatch.lowerBound]
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
