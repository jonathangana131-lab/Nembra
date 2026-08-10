from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one patch anchor, got {count}")
    s = s.replace(old, new, 1)


# Separate current-session correlation evidence from operator-confirmed target authority.
replace_once(
    "        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
    "correlated phase",
)
replace_once(
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var sdkLocalBLEOnline = false",
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var pendingCorrelatedTargetID: UUID?\n    @Published private(set) var sdkLocalBLEOnline = false",
    "pending correlated target",
)
replace_once(
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
            ])''',
    '''            byID = [id: candidate]
            candidates = [candidate]
            selectedID = nil
            pendingCorrelatedTargetID = id
            correlationSession = nil
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Confirm that correlated target before Tuya authentication. Correlation is current-session evidence only and is not permanent scooter identity."
            log("candidate_correlated", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])''',
    "correlation cannot auto-select target",
)

confirm_method = '''
    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              selectedID == nil,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.likely,
              candidates.count == 1,
              targetCorrelationMethod == "package-owned-fresh-manager-off1-on1-off2-on2",
              targetCorrelationWindowCount == 4,
              correlationProvenance?.repeatableCandidateIDs == [id.uuidString] else {
            pendingCorrelatedTargetID = nil
            failLocally("A complete current-session correlated Bluetooth target is not awaiting valid confirmation. Restart from OFF1.", "correlated_target_confirmation_unavailable")
            return
        }
        guard buildIdentity.isAuthoritativeFieldBuild,
              privateConfig,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            pendingCorrelatedTargetID = nil
            failLocally("Build or Tuya account/device authority changed before target confirmation. Re-verify authority and restart correlation from OFF1.", "source_authority_changed_before_target_confirmation")
            return
        }
        guard currentConnectionToken == nil, correlationSession == nil else {
            pendingCorrelatedTargetID = nil
            failLocally("Another Bluetooth/session authority is still active. Relaunch Capture before confirming another target.", "active_authority_blocks_target_confirmation")
            return
        }

        selectedID = id
        pendingCorrelatedTargetID = nil
        targetCorrelationOperatorConfirmed = true
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This confirmation is current-session correlation authority only, not durable scooter identity. Tuya may now take sole BLE ownership for the read-only authentication test."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "explicit-operator-confirmation-of-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

'''
replace_once(
    "    func invalidateSDKMembership() {",
    confirm_method + "    func invalidateSDKMembership() {",
    "explicit target confirmation method",
)
replace_once(
    "        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()",
    "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n            correlationSession?.abandonCurrentWindow()",
    "membership invalidation includes correlated state",
)
replace_once(
    "        membershipStatus = \"Official SDK login changed. Exact scooter membership must be verified again.\"",
    "        pendingCorrelatedTargetID = nil\n        targetCorrelationOperatorConfirmed = false\n        membershipStatus = \"Official SDK login changed. Exact scooter membership must be verified again.\"",
    "membership invalidation clears pending target",
)
replace_once(
    "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
    "correlated membership terminal",
)
replace_once(
    '''    func authenticate() {
        guard let candidate = selected, candidate.likely else {
            failLocally("A fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")''',
    '''    func authenticate() {
        guard targetCorrelationOperatorConfirmed,
              let candidate = selected,
              candidate.likely else {
            failLocally("An explicitly confirmed fresh OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")''',
    "authentication requires explicit confirmation",
)
replace_once(
    "        selectedID = nil\n        sdkLocalBLEOnline = false\n        exportData = nil",
    "        selectedID = nil\n        pendingCorrelatedTargetID = nil\n        sdkLocalBLEOnline = false\n        exportData = nil",
    "reset pending correlation target",
)

# Make exact compiled field-build provenance visible and fail closed before field actions.
replace_once(
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "field build presentation authority",
)
replace_once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance verified" : "Not authoritative")',
    "field build row",
)
replace_once(
    "            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "NO-GO banner build authority",
)
replace_once(
    "                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "OFF1 action build authority",
)

# Present the explicit confirmation rung before authentication becomes visible.
replace_once(
    '''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            default:''',
    '''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("Scooter signal found")
                    .font(.headline)
                Text("The complete OFF1→ON1→OFF2→ON2 series found one repeatable full CoreBluetooth target. Confirm it for this attempt before Tuya authentication. This is not durable scooter identity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

            default:''',
    "explicit confirmation UI",
)
replace_once(
    "                    !candidate.likely\n                        || !test.privateConfig",
    "                    !candidate.likely\n                        || !test.fieldBuildIsAuthoritative\n                        || !test.privateConfig",
    "authentication UI build authority",
)

# Preserve source-authority truth if an SDK failure races account/device drift.
replace_once(
    '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        await authenticationAcquisitionFailed(''',
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
                message: "Tuya account/device source authority changed before the SDK failure callback could be classified.",
                kind: "sdk_source_authority_lost_before_failure_terminal"
            )
            return
        }
        await authenticationAcquisitionFailed(''',
    "failure callback preserves source drift",
)

path.write_text(s)
