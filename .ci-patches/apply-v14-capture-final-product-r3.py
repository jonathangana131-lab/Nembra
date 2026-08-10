from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
EXPLICIT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaExplicitCorrelatedTargetConfirmationSourceTests.swift")
EXPORT_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelatedTargetExportProvenanceSourceTests.swift")
SESSION_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSessionTerminalRetirementSourceTests.swift")
FRESH_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFreshTargetAndAcquisitionTerminalSourceTests.swift")
TRANSPORT_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaTransportSuccessAuthoritySourceTests.swift")
PROGRESS_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelationProgressPresentationSourceTests.swift")


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


app = APP.read_text()

app = once(
    app,
    "        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
    "correlated phase",
)

app = once(
    app,
'''        let selectedPeripheralID: String?
        let phase: Phase
''',
'''        let selectedPeripheralID: String?
        let targetCorrelationMethod: String?
        let targetCorrelationWindowCount: Int?
        let targetCorrelationOperatorConfirmed: Bool
        let phase: Phase
''',
    "export correlation provenance fields",
)

app = once(
    app,
'''    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
''',
'''    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?
''',
    "published correlation progress",
)

app = once(
    app,
'''    private var baseline = Set<UUID>()
    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?
    private var driver: OfficialTuyaDriver?
''',
'''    private var baseline = Set<UUID>()
    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?
    private var correlationProgressTask: Task<Void, Never>?
    private var targetCorrelationMethod: String?
    private var targetCorrelationWindowCount: Int?
    private var targetCorrelationOperatorConfirmed = false
    private var driver: OfficialTuyaDriver?
''',
    "correlation presentation/provenance state",
)

app = once(
    app,
"    deinit { watchdog?.cancel() }",
"    deinit {\n        watchdog?.cancel()\n        correlationProgressTask?.cancel()\n    }",
    "progress task deinit cleanup",
)

app = once(
    app,
'''    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
''',
'''    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
''',
    "field build presentation authority",
)

app = once(
    app,
"    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
"",
    "remove unobservable computed progress",
)

app = once(
    app,
'''        let label = correlationWindowLabel
        do {
            try session.startCurrentWindow()
            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline
''',
'''        let label = correlationWindowLabel
        do {
            try session.startCurrentWindow()
            correlationProgress = session.progress
            startCorrelationProgressObservation(session: session)
            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline
''',
    "start progress observer with package window",
)

observer = '''
    private func startCorrelationProgressObservation(session: PassiveBluetoothPowerCycleObservationSession) {
        stopCorrelationProgressObservation()
        correlationProgress = session.progress
        correlationProgressTask = Task { @MainActor [weak self, weak session] in
            while !Task.isCancelled {
                guard let self,
                      let session,
                      self.correlationSession === session else { return }
                if let progress = session.progress {
                    self.correlationProgress = progress
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopCorrelationProgressObservation() {
        correlationProgressTask?.cancel()
        correlationProgressTask = nil
    }

'''
app = once(
    app,
"    func finishCorrelationWindow() {",
observer + "    func finishCorrelationWindow() {",
    "progress observation helpers",
)

app = once(
    app,
'''        do {
            let final = try session.finishCurrentWindow()
            if let final {
''',
'''        do {
            let final = try session.finishCurrentWindow()
            stopCorrelationProgressObservation()
            correlationProgress = session.progress
            if let final {
''',
    "retire progress observer after successful seal",
)

# Retire the presentation observer whenever the package series itself is abandoned.
app = app.replace(
'''            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally(''',
'''            session.abandonCurrentWindow()
            stopCorrelationProgressObservation()
            correlationProgress = nil
            correlationSession = nil
            failLocally('''
)

app = once(
    app,
'''    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {
        switch result.correlation.disposition {
''',
'''    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {
        targetCorrelationMethod = "fresh-off1-on1-off2-on2-full-corebluetooth-uuid-repeat"
        targetCorrelationWindowCount = result.windows.count
        targetCorrelationOperatorConfirmed = false
        switch result.correlation.disposition {
''',
    "record correlation provenance before disposition",
)

app = once(
    app,
'''            byID = [id: candidate]
            candidates = [candidate]
            selectedID = id
            correlationSession = nil
            phase = .selected
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Discovery is retired before Tuya's SDK takes BLE ownership."
            log("candidate_selected", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])
''',
'''            byID = [id: candidate]
            candidates = [candidate]
            selectedID = nil
            correlationSession = nil
            phase = .correlated
            message = "Scooter signal found by the complete repeated power-cycle series. Confirm this correlated Bluetooth target before Tuya may take BLE ownership. This is current-session correlation evidence, not permanent scooter identity."
            log("candidate_correlation_ready", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])
''',
    "separate correlation from selection",
)

confirm = '''
    func confirmCorrelatedTarget(_ candidate: Candidate) {
        guard phase == .correlated,
              selectedID == nil,
              candidate.freshlyCorrelated,
              byID[candidate.id] == candidate,
              targetCorrelationMethod != nil,
              targetCorrelationWindowCount == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
            failLocally("Only the single target earned by this exact OFF1→ON1→OFF2→ON2 series can be confirmed.", "target_confirmation_rejected")
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Current Tuya account/device authority changed before target confirmation.", "sdk_authority_changed_before_target_confirmation")
            return
        }

        selectedID = candidate.id
        targetCorrelationOperatorConfirmed = true
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This confirmation does not establish durable scooter identity. Tuya may now take sole BLE ownership for the read-only authentication test."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "operator-confirmed-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID),
            "correlationMethod": targetCorrelationMethod ?? "unknown",
            "windows": String(targetCorrelationWindowCount ?? 0)
        ])
    }

'''
app = once(
    app,
"    func invalidateSDKMembership() {",
confirm + "    func invalidateSDKMembership() {",
    "explicit target confirmation action",
)

app = once(
    app,
'''        if phase == .baseline || phase == .powerOn || phase == .scanning {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
''',
'''        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            stopCorrelationProgressObservation()
            correlationProgress = nil
            correlationSession = nil
        }
''',
    "membership invalidation retires correlation presentation",
)

app = once(
    app,
"        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
"        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
    "membership invalidates pending correlation authority",
)

# Publish local token ownership immediately after the ledger mints it, then retire that exact
# generation through the clock-independent terminal if auth-start chronology itself fails.
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

app = once(
    app,
'''                } catch {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
''',
'''                } catch {
                    await invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
''',
    "auth-promotion chronology terminal",
)

app = once(
    app,
'''            case .invalidClock:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
''',
'''            case .invalidClock:
                await invalidateChronologyIntegrity(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
''',
    "local-BLE invalid clock terminal",
)

chronology = '''    private func invalidateChronologyIntegrity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            // Package authority was already retired; continue clearing app ownership.
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            return
        } catch {
            // This terminal performs no clock sample. A failure here means state was already
            // terminal/incompatible; never invent a different physical failure classification.
            log("chronology_terminal_rejected", [
                "generation": String(token.diagnosticGeneration),
                "error": error.localizedDescription
            ])
        }
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
app = once(
    app,
"    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {",
chronology + "    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {",
    "chronology cleanup helper",
)

# SDK failure callback scheduling must not overwrite already-observed source drift with a generic
# authentication-establishment terminal.
app = once(
    app,
'''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }
''',
'''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before the SDK failure callback was classified.",
                kind: "sdk_source_authority_lost_before_auth_failure"
            )
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }
''',
    "SDK failure source-race classification",
)

app = once(
    app,
'''        try? await sessionLedger.markAuthenticationFailed(for: token)
        currentConnectionToken = nil
''',
'''        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch {
            await invalidateChronologyIntegrity(token: token, message: message, kind: kind + "_chronology_fallback")
            return
        }
        currentConnectionToken = nil
''',
    "auth failure terminal fallback",
)

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
    "watchdog gap terminal helper",
)

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
    "no-application timeout terminal fallback",
)

app = once(
    app,
'''        try? await sessionLedger.endConnection(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
''',
'''        do {
            try await sessionLedger.endConnection(for: token)
        } catch {
            await invalidateChronologyIntegrity(
                token: token,
                message: "Tuya local-BLE transport ended, but session chronology also became invalid while retiring authority.",
                kind: "sdk_local_ble_drop_chronology_fallback"
            )
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
''',
    "transport terminal fallback",
)

app = once(
    app,
'''        try? await sessionLedger.markSourceAuthorityInvalidated(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
''',
'''        do {
            try await sessionLedger.markSourceAuthorityInvalidated(for: token)
        } catch {
            await invalidateChronologyIntegrity(token: token, message: message, kind: kind + "_chronology_fallback")
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
''',
    "source terminal fallback",
)

app = once(
    app,
'''        try? await sessionLedger.markObservationContinuityInvalidated(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
''',
'''        do {
            try await sessionLedger.markObservationContinuityInvalidated(for: token)
        } catch {
            await invalidateChronologyIntegrity(token: token, message: message, kind: kind + "_chronology_fallback")
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
''',
    "continuity terminal fallback",
)

app = once(
    app,
'''            schemaVersion: 7,
''',
'''            schemaVersion: 8,
''',
    "export schema bump",
)
app = once(
    app,
'''            selectedPeripheralID: selectedID?.uuidString,
            phase: phase,
''',
'''            selectedPeripheralID: selectedID?.uuidString,
            targetCorrelationMethod: targetCorrelationMethod,
            targetCorrelationWindowCount: targetCorrelationWindowCount,
            targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed,
            phase: phase,
''',
    "export correlation provenance values",
)

app = once(
    app,
'''    private func resetDiscoverySessionOnly() {
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
''',
'''    private func resetDiscoverySessionOnly() {
        correlationSession?.abandonCurrentWindow()
        stopCorrelationProgressObservation()
        correlationProgress = nil
        correlationSession = nil
        targetCorrelationMethod = nil
        targetCorrelationWindowCount = nil
        targetCorrelationOperatorConfirmed = false
''',
    "reset correlation presentation/provenance",
)

app = once(
    app,
'''    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
''',
'''    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            stopCorrelationProgressObservation()
            correlationProgress = nil
            correlationSession = nil
        }
''',
    "local failure retires correlation presentation",
)

# App-visible build authority must match the runtime guard.
app = once(
    app,
'            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
'            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance verified" : "Not authoritative")',
    "field build row",
)
app = once(
    app,
"            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
"            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "NO-GO build banner",
)
app = once(
    app,
"                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
"                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "OFF1 build gating",
)

app = once(
    app,
'''            case .powerOn:
                Text("Next: \(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            default:
''',
'''            case .powerOn:
                Text("Next: \(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("Scooter signal found")
                    .font(.headline)
                Text("One full CoreBluetooth target repeated across the complete four-window series. Confirm it explicitly before authentication. This is current-session correlation evidence, not permanent scooter identity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let candidate = test.candidates.first(where: { $0.freshlyCorrelated }) {
                    Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget(candidate) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)
                }

            default:
''',
    "explicit confirmation UI",
)

APP.write_text(app)

# Repair two internally contradictory/stale source contracts without weakening their authority.
explicit = EXPLICIT.read_text()
explicit = once(
    explicit,
'''            from: "private func finishCorrelationSeries",
            to: "func invalidateSDKMembership"
''',
'''            from: "private func finishCorrelationSeries",
            to: "func confirmCorrelatedTarget"
''',
    "explicit confirmation test section boundary",
)
EXPLICIT.write_text(explicit)

export_test = EXPORT_TEST.read_text()
export_test = once(
    export_test,
'''            from: "private func finishCorrelationSeries",
            to: "func invalidateSDKMembership"
''',
'''            from: "private func finishCorrelationSeries",
            to: "func confirmCorrelatedTarget"
''',
    "export provenance test section boundary",
)
EXPORT_TEST.write_text(export_test)

session_test = SESSION_TEST.read_text()
session_test = session_test.replace("invalidateInternalLifecycle", "invalidateChronologyIntegrity")
session_test = session_test.replace("markInternalLifecycleFailure", "markChronologyIntegrityInvalidated")
SESSION_TEST.write_text(session_test)

fresh = FRESH_TEST.read_text()
fresh = once(
    fresh,
'''        #expect(invalidClockBranch.contains("authenticationAcquisitionFailed"))
''',
'''        #expect(invalidClockBranch.contains("invalidateChronologyIntegrity"))
''',
    "fresh target invalid-clock contract",
)
FRESH_TEST.write_text(fresh)

transport = TRANSPORT_TEST.read_text()
transport = once(
    transport,
'''        #expect(prefix.contains("invalidateSourceAuthority"))
''',
'''        #expect(prefix.contains("invalidateChronologyIntegrity"))
''',
    "transport auth-rejection terminal contract",
)
TRANSPORT_TEST.write_text(transport)

PROGRESS_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation-progress presentation bridge")
struct TuyaCorrelationProgressPresentationSourceTests {
    @Test("package scan-readiness progress is published instead of pulled from an unobservable session")
    func correlationProgressHasAppOwnedPublishedSnapshot() throws {
        let app = try source()
        #expect(app.contains("@Published private(set) var correlationProgress"))
        #expect(!app.contains("var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }"))
        #expect(app.contains("private var correlationProgressTask: Task<Void, Never>?"))
        let projection = try section(app, "var correlationWindowIsScanning", "var correlationWindowLabel")
        #expect(projection.contains("correlationProgress?.isScanning == true"))
        #expect(!projection.contains("correlationSession?.progress"))
    }

    @Test("window readiness is projected from package progress and retired at boundaries")
    func progressObserverIsTruthfulAndBounded() throws {
        let app = try source()
        let start = try section(app, "private func startCurrentCorrelationWindow()", "private func startCorrelationProgressObservation")
        #expect(start.contains("session.startCurrentWindow()"))
        #expect(start.contains("startCorrelationProgressObservation(session:"))
        let observer = try section(app, "private func startCorrelationProgressObservation", "private func stopCorrelationProgressObservation")
        #expect(observer.contains("session.progress"))
        #expect(observer.contains("self.correlationProgress = progress"))
        #expect(observer.contains("Task.sleep"))
        #expect(observer.contains("Task.isCancelled"))
        let finish = try section(app, "func finishCorrelationWindow()", "private func finishCorrelationSeries")
        #expect(finish.contains("stopCorrelationProgressObservation"))
        let reset = try section(app, "private func resetDiscoverySessionOnly", "private func failLocally")
        #expect(reset.contains("stopCorrelationProgressObservation"))
        #expect(reset.contains("correlationProgress = nil"))
    }

    @Test("seal remains gated by the published package liveness snapshot")
    func sealActionUsesPublishedLiveness() throws {
        let app = try source()
        let view = try section(app, "private struct SecureLinkView", "#Preview")
        #expect(view.contains("test.correlationWindowIsScanning"))
        #expect(view.contains(".disabled(!test.correlationWindowIsScanning)"))
    }

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }
    private func section(_ source: String, _ start: String, _ end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw E.missing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private enum E: Error { case missing }
}
''')
