from pathlib import Path
import re

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
LEDGER = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")
FRESH_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFreshTargetAndAcquisitionTerminalSourceTests.swift")
CLOCK_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaChronologyIntegrityTerminalTests.swift")
FINAL_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFinalConvergenceAuthoritySourceTests.swift")

def once(text, old, new, label):
    n = text.count(old)
    if n != 1: raise SystemExit(f"{label}: expected 1 match, found {n}")
    return text.replace(old, new, 1)

def sub_once(text, pattern, replacement, label):
    rx = re.compile(pattern, re.M | re.S)
    if len(list(rx.finditer(text))) != 1: raise SystemExit(f"{label}: non-unique regex")
    return rx.sub(lambda _: replacement, text, count=1)

ledger = LEDGER.read_text()
ledger = once(ledger,
'''    private static let sourceAuthorityFailureReason =
        "Tuya SDK source authority was invalidated."
''',
'''    private static let sourceAuthorityFailureReason =
        "Tuya SDK source authority was invalidated."
    private static let chronologyIntegrityFailureReason =
        "Read-only session chronology integrity was invalidated."
''', "chronology reason")
ledger = once(ledger,
'''    /// Retires the current generation when its source identity/ownership authority is no longer
''',
'''    /// Fail-closed retirement for a session whose chronology machinery itself can no longer be
    /// trusted to take another monotonic sample.
    ///
    /// This is deliberately not source-authority loss, observation-gap evidence, SDK failure, or a
    /// transport disconnect. It never advances `latestObserved...`. Pre-authentication evidence is
    /// cleared; genuinely earned post-authentication chronology remains diagnostic-only. The exact
    /// current token is always retired so a failed clock cannot leave hidden callback authority.
    public func markChronologyIntegrityInvalidated(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        switch authenticationState {
        case .waitingForAuthentication, .authenticating:
            authenticationMethod = nil
            authenticatedAtUptimeNanoseconds = nil
            applicationPayloadCount = 0
            latestApplicationPayloadUptimeNanoseconds = nil
        case .authenticated:
            break
        case .unavailable, .failed:
            throw MutationError.invalidAuthenticationTransition
        }

        authenticationState = .failed(reason: Self.chronologyIntegrityFailureReason)
        currentToken = nil
    }

    /// Retires the current generation when its source identity/ownership authority is no longer
''', "chronology terminal")
LEDGER.write_text(ledger)

app = APP.read_text()
app = once(app,
"        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
"        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
"correlated phase")
app = once(app,
"    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
"    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
"field build property")

old = '''            byID = [id: candidate]
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
new = '''            byID = [id: candidate]
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
            ])'''
app = once(app, old, new, "do not auto-select correlation")

confirm = '''    func confirmCorrelatedTarget(_ candidate: Candidate) {
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
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "operator-confirmed-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

'''
app = once(app, "    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {", confirm + "    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {", "confirmation action")
app = once(app, "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {", "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {", "membership invalidates correlated result")

# Chronology failures must retire package authority without another clock sample.
app = once(app,
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
''', "auth promotion chronology terminal")
app = once(app,
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
''', "local settlement invalid clock")

chronology_helper = '''    private func invalidateChronologyIntegrity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)
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
app = once(app, "    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {", chronology_helper + "    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {", "chronology app helper")

app = once(app,
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
''', "auth terminal clock fallback")
app = once(app,
'''        try? await sessionLedger.endConnection(for: token)
        currentConnectionToken = nil
''',
'''        do {
            try await sessionLedger.endConnection(for: token)
        } catch {
            await invalidateChronologyIntegrity(token: token, message: message, kind: kind + "_chronology_fallback")
            return
        }
        currentConnectionToken = nil
''', "transport terminal clock fallback") if False else app
# recordObservedTransportLoss has fixed local text rather than message/kind parameters.
app = once(app,
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
''', "transport terminal fallback")
app = once(app,
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
''', "source terminal fallback")
app = once(app,
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
''', "continuity terminal fallback")

# UI must expose exact build authority and explicit confirmation before auth.
app = once(app,
'            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
'            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance verified" : "Not authoritative")',
"field build UI")
app = once(app,
"            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
"            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
"NO-GO build UI")
app = once(app,
"                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
"                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
"OFF1 build UI")
app = once(app,
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
                Text("Scooter signal found").font(.headline)
                Text("One full CoreBluetooth target repeated across the complete four-window series. Confirm it explicitly before authentication. This is current-session correlation evidence, not permanent scooter identity.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let candidate = test.candidates.first(where: { $0.freshlyCorrelated }) {
                    Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget(candidate) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)
                }

            default:
''', "confirmation UI")
APP.write_text(app)

fresh = FRESH_TEST.read_text()
fresh = once(fresh,
'''        #expect(invalidClockBranch.contains("authenticationAcquisitionFailed"))
        #expect(!timeoutBranch.contains("invalidateSourceAuthority"))
''',
'''        #expect(invalidClockBranch.contains("invalidateChronologyIntegrity"))
        #expect(!timeoutBranch.contains("invalidateSourceAuthority"))
''', "source contract accepts no-clock invalidClock terminal")
FRESH_TEST.write_text(fresh)

CLOCK_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya chronology-integrity terminal")
struct TuyaChronologyIntegrityTerminalTests {
    @Test("authentication clock regression retires generation without another clock sample")
    func authenticationRegressionCannotStrandCallbackAuthority() async throws {
        let clock = MutableUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: { clock.now() })
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 1_499)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        try await ledger.markChronologyIntegrityInvalidated(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Read-only session chronology integrity was invalidated."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        clock.advance(to: 2_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
    }
}

private final class MutableUptimeClock: @unchecked Sendable {
    private let lock = NSLock(); private var value: UInt64
    init(_ value: UInt64) { self.value = value }
    func now() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance(to value: UInt64) { lock.lock(); self.value = value; lock.unlock() }
}
''')

FINAL_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture final convergence authority")
struct TuyaFinalConvergenceAuthoritySourceTests {
    @Test("correlation cannot authorize selection without operator action")
    func explicitTargetConfirmationOwnsSelection() throws {
        let app = try source()
        let finish = try section(app, "private func finishCorrelationSeries", "func invalidateSDKMembership")
        #expect(finish.contains("selectedID = nil"))
        #expect(finish.contains("phase = .correlated"))
        #expect(!finish.contains("selectedID = id"))
        let confirm = try section(app, "func confirmCorrelatedTarget", "func verifySDKMembership")
        #expect(confirm.contains("selectedID = candidate.id"))
        #expect(confirm.contains("phase = .selected"))
        #expect(confirm.contains("candidate_selected"))
        #expect(app.contains("Confirm correlated Bluetooth target"))
    }

    @Test("field build and chronology are first-class physical preflight authority")
    func buildAndChronologyAuthorityAreVisibleAndTerminal() throws {
        let app = try source()
        #expect(app.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(app.contains("LabeledContent(\"Field build\", value: test.fieldBuildIsAuthoritative"))
        #expect(app.contains("!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(app.contains("markChronologyIntegrityInvalidated"))
        #expect(app.contains("sdk_local_ble_settlement_clock_invalid"))
        #expect(app.contains("localBLESettlementToken != token"))
    }

    private func source() throws -> String { try read("NembraApp/App/NembraCaptureEntrypoint.swift") }
    private func section(_ s: String, _ a: String, _ b: String) throws -> Substring {
        guard let x=s.range(of:a), let y=s.range(of:b, range:x.upperBound..<s.endIndex) else { throw E.missing }
        return s[x.lowerBound..<y.lowerBound]
    }
    private func read(_ p: String) throws -> String {
        let r=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf:r.appendingPathComponent(p), encoding:.utf8)
    }
    private enum E: Error { case missing }
}
''')
