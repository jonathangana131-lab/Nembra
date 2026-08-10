from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    s = s.replace(old, new, 1)


replace_once(
    "case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
    "correlated phase",
)

replace_once(
    "    @Published private(set) var selectedID: UUID?\n",
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var pendingCorrelatedTargetID: UUID?\n",
    "pending target storage",
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
            pendingCorrelatedTargetID = id
            correlationSession = nil
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Confirm that correlated Bluetooth target for this attempt before Tuya authentication. Correlation is current-session evidence, not permanent scooter identity."
            log("candidate_correlated", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])'''
replace_once(old_finish, new_finish, "correlation cannot auto-select")

confirmation = '''    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            pendingCorrelatedTargetID = nil
            failLocally("A current-session correlated Bluetooth target is not awaiting confirmation. Restart from OFF1.", "correlated_target_confirmation_unavailable")
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            pendingCorrelatedTargetID = nil
            failLocally("Tuya account/device authority changed before target confirmation. Re-verify membership and restart correlation.", "sdk_authority_changed_before_target_confirmation")
            return
        }
        guard currentConnectionToken == nil else {
            pendingCorrelatedTargetID = nil
            failLocally("An authenticated generation already owns session authority. Relaunch Capture before confirming another target.", "active_generation_blocks_target_confirmation")
            return
        }

        selectedID = id
        pendingCorrelatedTargetID = nil
        targetCorrelationOperatorConfirmed = true
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This remains current-session correlation evidence, not permanent scooter identity. Current same-account Tuya membership remains the independent authentication authority."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "explicit-operator-confirmation-of-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

'''
replace_once(
    "    func invalidateSDKMembership() {",
    confirmation + "    func invalidateSDKMembership() {",
    "explicit confirmation action",
)

replace_once(
    "        membershipDeviceID = nil\n        if phase == .baseline || phase == .powerOn || phase == .scanning {",
    "        membershipDeviceID = nil\n        pendingCorrelatedTargetID = nil\n        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {",
    "membership invalidation retires pending correlation",
)
replace_once(
    "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
    "membership invalidation covers correlated phase",
)

replace_once(
    "        selectedID = nil\n        sdkLocalBLEOnline = false\n",
    "        selectedID = nil\n        pendingCorrelatedTargetID = nil\n        sdkLocalBLEOnline = false\n",
    "reset retires pending target",
)

replace_once(
    '''    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        watchdog?.cancel()''',
    '''    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        pendingCorrelatedTargetID = nil
        watchdog?.cancel()''',
    "terminal failure retires pending target",
)

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
                Text("One full CoreBluetooth target repeated across the required OFF1→ON1→OFF2→ON2 series. Confirm it for this attempt before Tuya authentication. This does not establish permanent scooter identity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

            default:''',
    "confirmation UI",
)

path.write_text(s)
