from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one patch anchor, got {count}: {old[:120]!r}")
    s = s.replace(old, new, 1)


replace_once(
    "case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
)

replace_once(
    "@Published private(set) var selectedID: UUID?\n",
    "@Published private(set) var selectedID: UUID?\n    @Published private(set) var pendingCorrelatedTargetID: UUID?\n",
)

finish_anchor = "    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {"
confirmation = '''    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.likely else {
            failLocally("A current-session correlated Bluetooth target is not awaiting confirmation.", "correlated_target_confirmation_unavailable")
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            pendingCorrelatedTargetID = nil
            failLocally("Tuya account/device authority changed before correlated-target confirmation. Restart correlation after re-verifying membership.", "sdk_authority_changed_before_target_confirmation")
            return
        }
        guard currentConnectionToken == nil else {
            pendingCorrelatedTargetID = nil
            failLocally("An authenticated generation already owns session authority. Relaunch Capture before confirming another target.", "active_generation_blocks_target_confirmation")
            return
        }

        selectedID = id
        pendingCorrelatedTargetID = nil
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This is current-session correlation evidence, not permanent scooter identity. Tuya SDK membership remains the separate authentication authority."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "explicit-operator-confirmation-of-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

'''
replace_once(finish_anchor, confirmation + finish_anchor)

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
            ])
''',
'''            byID = [id: candidate]
            candidates = [candidate]
            pendingCorrelatedTargetID = id
            correlationSession = nil
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Confirm that correlated target before Tuya authentication. Correlation evidence is current-session only and is not permanent scooter identity."
            log("candidate_correlated", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])
''')

replace_once(
'''        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
''',
'''        pendingCorrelatedTargetID = nil
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
''')

replace_once(
    "if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
)

replace_once(
'''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            default:
''',
'''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("One full CoreBluetooth target repeated across the required OFF1→ON1→OFF2→ON2 series. Confirm it for this attempt before Tuya authentication.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

            default:
''')

replace_once(
    "        selectedID = nil\n        sdkLocalBLEOnline = false\n",
    "        selectedID = nil\n        pendingCorrelatedTargetID = nil\n        sdkLocalBLEOnline = false\n",
)

path.write_text(s)
