from pathlib import Path
import re

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFinalConvergenceAuthoritySourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one literal match, found {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    compiled = re.compile(pattern, re.MULTILINE | re.DOTALL)
    matches = list(compiled.finditer(text))
    if len(matches) != 1:
        raise SystemExit(f"{label}: expected exactly one regex match, found {len(matches)}")
    return compiled.sub(lambda _: replacement, text, count=1)


app = APP.read_text()

app = replace_once(
    app,
    "        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
    "explicit correlation phase",
)

app = replace_once(
    app,
    "    private var currentConnectionToken: TuyaReadOnlyConnectionToken?\n    private var membershipAccountUID: String?",
    "    private var currentConnectionToken: TuyaReadOnlyConnectionToken?\n    private var localBLESettlementToken: TuyaReadOnlyConnectionToken?\n    private var membershipAccountUID: String?",
    "local BLE settlement owner storage",
)

app = replace_once(
    app,
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "field build presentation authority",
)

old_finish = '''            byID = [id: candidate]
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
            ])'''
new_finish = '''            byID = [id: candidate]
            candidates = [candidate]
            selectedID = nil
            correlationSession = nil
            phase = .correlated
            message = "Scooter signal found by the complete repeated power-cycle series. Confirm this correlated Bluetooth target before Tuya may take BLE ownership. Correlation is current-session evidence, not permanent scooter identity."
            log("candidate_correlation_ready", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])'''
app = replace_once(app, old_finish, new_finish, "separate correlation from explicit confirmation")

confirm_method = '''
    func confirmCorrelatedCandidate(_ candidate: Candidate) {
        guard phase == .correlated,
              selectedID == nil,
              candidate.freshlyCorrelated,
              byID[candidate.id] == candidate else {
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
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This confirmation does not establish durable scooter identity. Tuya may now take sole BLE ownership for the read-only authentication test."
        log("candidate_confirmed", [
            "id": candidate.id.uuidString,
            "authority": "operator-confirmed-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

'''
app = replace_once(
    app,
    "    func invalidateSDKMembership() {",
    confirm_method + "    func invalidateSDKMembership() {",
    "explicit target confirmation method",
)

app = replace_once(
    app,
    "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
    "source invalidation covers correlated phase",
)

app = replace_once(
    app,
    "        sdkLocalBLEOnline = false\n        phase = .authenticating",
    "        sdkLocalBLEOnline = false\n        localBLESettlementToken = nil\n        phase = .authenticating",
    "clear settlement owner at auth start",
)

new_authenticated = '''    private func authenticated(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_success_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        if phase == .observing {
            log("duplicate_connect_success_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard phase == .authenticating else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya transport success arrived outside the active authentication phase. The generation was retired instead of being left hidden.",
                kind: "sdk_transport_success_outside_authentication"
            )
            return
        }
        guard localBLESettlementToken != token else {
            log("duplicate_connect_success_settlement_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before transport success could enter local-BLE settlement.",
                kind: "sdk_source_authority_lost_before_local_ble_settlement"
            )
            return
        }
        guard let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "Official Tuya driver authority disappeared before local-BLE settlement.",
                kind: "sdk_driver_authority_lost_before_local_ble_settlement"
            )
            return
        }

        localBLESettlementToken = token
        defer {
            if localBLESettlementToken == token {
                localBLESettlementToken = nil
            }
        }

        let acquisitionStarted = DispatchTime.now().uptimeNanoseconds
        while currentConnectionToken == token, phase == .authenticating {
            guard accountIdentityLeaseIsAuthorized else {
                await invalidateSourceAuthority(
                    token: token,
                    message: "Tuya account/device source authority changed while local BLE status was settling.",
                    kind: "sdk_source_authority_lost_during_local_ble_settlement"
                )
                return
            }

            let observedAt = DispatchTime.now().uptimeNanoseconds
            let isLocallyOnline = driver.isLocallyConnected(uuid: tuyaUUID)
            switch TuyaLocalBLEAcquisitionWindow.verdict(
                startedAtUptimeNanoseconds: acquisitionStarted,
                observedAtUptimeNanoseconds: observedAt,
                isLocallyOnline: isLocallyOnline,
                maximumWaitNanoseconds: TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds
            ) {
            case .observedOnline:
                sdkLocalBLEOnline = true
                do {
                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
                    message = "Authenticated generation \(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…"
                    log("sdk_local_ble_authenticated", [
                        "generation": String(token.diagnosticGeneration),
                        "localBLEOnline": "true"
                    ])
                    startWatchdog(token: token)
                } catch {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
                return

            case .keepWaiting:
                try? await Task.sleep(for: .milliseconds(200))

            case .timedOut:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Tuya reported transport success, but current local-BLE status did not become authoritative within the bounded settlement window.",
                    kind: "sdk_local_ble_settlement_timed_out"
                )
                return

            case .invalidClock:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
            }
        }
    }

    private func authenticationFailed'''
app = sub_once(
    app,
    r"    private func authenticated\(token: TuyaReadOnlyConnectionToken\) async \{.*?^    private func authenticationFailed",
    new_authenticated,
    "restore transport-success lifecycle authority",
)

app = replace_once(
    app,
    "        try? await sessionLedger.markAuthenticationFailed(for: token)\n        currentConnectionToken = nil\n        sdkLocalBLEOnline = false",
    "        try? await sessionLedger.markAuthenticationFailed(for: token)\n        currentConnectionToken = nil\n        localBLESettlementToken = nil\n        sdkLocalBLEOnline = false",
    "clear settlement owner on auth acquisition failure",
)

for label, terminal_call in [
    ("transport loss", "sessionLedger.endConnection(for: token)"),
    ("source invalidation", "sessionLedger.markSourceAuthorityInvalidated(for: token)"),
    ("continuity invalidation", "sessionLedger.markObservationContinuityInvalidated(for: token)"),
]:
    old = f"        try? await {terminal_call}\n        currentConnectionToken = nil\n        sdkLocalBLEOnline = false"
    new = f"        try? await {terminal_call}\n        currentConnectionToken = nil\n        localBLESettlementToken = nil\n        sdkLocalBLEOnline = false"
    app = replace_once(app, old, new, f"clear settlement owner on {label}")

app = replace_once(
    app,
    "        watchdog = nil\n        driver = nil\n        byID.removeAll()",
    "        watchdog = nil\n        driver = nil\n        localBLESettlementToken = nil\n        byID.removeAll()",
    "clear settlement owner on discovery reset",
)

app = replace_once(
    app,
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance verified" : "Not authoritative")',
    "field build row uses build authority",
)

app = replace_once(
    app,
    "            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "NO-GO banner includes build authority",
)

app = replace_once(
    app,
    "                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "OFF1 action includes build authority",
)

correlated_ui = '''            case .correlated:
                Text("Scooter signal found")
                    .font(.headline)
                Text("The complete four-window series found one repeatable full CoreBluetooth target. Confirm it explicitly before authentication. This is not durable scooter identity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let candidate = test.candidates.first(where: { $0.freshlyCorrelated }) {
                    Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedCandidate(candidate) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)
                }

            default:'''
app = replace_once(
    app,
    "            default:\n                EmptyView()",
    correlated_ui + "\n                EmptyView()",
    "explicit confirmation UI",
)

APP.write_text(app)

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture final convergence authority")
struct TuyaFinalConvergenceAuthoritySourceTests {
    @Test("fresh correlation remains non-authorizing until explicit operator confirmation")
    func correlationRequiresExplicitConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let finish = app.range(of: "private func finishCorrelationSeries"),
              let confirm = app.range(of: "func confirmCorrelatedCandidate", range: finish.upperBound..<app.endIndex),
              let invalidate = app.range(of: "func invalidateSDKMembership", range: confirm.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate correlation/confirmation boundaries.")
            return
        }
        let finishBody = String(app[finish.lowerBound..<confirm.lowerBound])
        let confirmBody = String(app[confirm.lowerBound..<invalidate.lowerBound])

        #expect(finishBody.contains("selectedID = nil"))
        #expect(finishBody.contains("phase = .correlated"))
        #expect(finishBody.contains("candidate_correlation_ready"))
        #expect(!finishBody.contains("selectedID = id"))
        #expect(!finishBody.contains("candidate_selected"))

        #expect(confirmBody.contains("phase == .correlated"))
        #expect(confirmBody.contains("candidate.freshlyCorrelated"))
        #expect(confirmBody.contains("selectedID = candidate.id"))
        #expect(confirmBody.contains("phase = .selected"))
        #expect(confirmBody.contains("candidate_confirmed"))
        #expect(app.contains("Confirm correlated Bluetooth target"))
    }

    @Test("current transport-success generation cannot strand or duplicate local-BLE settlement")
    func transportSuccessUsesTerminalSourceAuthorityAndOneSettlementOwner() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let next = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate transport-success handler.")
            return
        }
        let handler = String(app[authenticated.lowerBound..<next.lowerBound])

        #expect(app.contains("private var localBLESettlementToken: TuyaReadOnlyConnectionToken?"))
        #expect(handler.contains("currentConnectionToken == token"))
        #expect(handler.contains("stale_connect_success_ignored"))
        #expect(handler.contains("localBLESettlementToken != token"))
        #expect(handler.contains("duplicate_connect_success_settlement_ignored"))
        #expect(handler.contains("sdk_source_authority_lost_before_local_ble_settlement"))
        #expect(handler.contains("sdk_driver_authority_lost_before_local_ble_settlement"))
        #expect(handler.contains("session_auth_callback_rejected"))
        #expect(handler.contains("invalidateSourceAuthority"))
        #expect(!handler.contains("sdkDeviceMembershipVerified,\n              accountIdentityLeaseIsAuthorized,\n              let driver else { return }"))
    }

    @Test("field-build authority is visible before OFF1 is actionable")
    func fieldBuildPresentationMatchesRuntimeAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(app.contains("LabeledContent(\"Field build\", value: test.fieldBuildIsAuthoritative"))
        #expect(app.contains("if !test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(app.contains(".disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(app.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
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
''')
