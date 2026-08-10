from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldBuildPresentationAuthoritySourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return text.replace(old, new, 1)


app = app_path.read_text()

app = replace_once(
    app,
    "        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
    "phase enum",
)
app = replace_once(
    app,
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var sdkLocalBLEOnline = false",
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var correlatedTargetID: UUID?\n    @Published private(set) var sdkLocalBLEOnline = false",
    "correlated target state",
)
app = replace_once(
    app,
    "    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }",
    "    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }",
    "field build presentation authority",
)

confirmation = '''    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = correlatedTargetID,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            failLocally("A fresh correlation candidate is not available for explicit confirmation. Restart from OFF1.", "correlated_target_confirmation_unavailable")
            return
        }
        guard fieldBuildIsAuthoritative,
              privateConfig,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Build or Tuya account/device authority changed before correlated-target confirmation. Restart only after authority is restored.", "correlated_target_confirmation_authority_changed")
            return
        }

        selectedID = id
        correlatedTargetID = nil
        phase = .selected
        message = "Fresh repeated Bluetooth correlation explicitly confirmed for this attempt. Tuya authentication may now consume this selected current-session target; it is not permanent scooter identity."
        log("candidate_selected", [
            "id": id.uuidString,
            "authority": "operator-confirmed-fresh-correlation",
            "correlation": "fresh-repeated-off-on-full-corebluetooth-id"
        ])
    }

'''
app = replace_once(
    app,
    "    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {",
    confirmation + "    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {",
    "explicit target confirmation method",
)

app = replace_once(
    app,
    '''            selectedID = id
            correlationSession = nil
            phase = .selected
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Discovery is retired before Tuya's SDK takes BLE ownership."
            log("candidate_selected", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])''',
    '''            selectedID = nil
            correlatedTargetID = id
            correlationSession = nil
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Explicitly confirm this correlated current-session candidate before Tuya authentication; it is not permanent scooter identity."
            log("candidate_correlated", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])''',
    "correlation stops before selection",
)

app = replace_once(
    app,
    "        sdkDeviceMembershipVerified = false\n        membershipAccountUID = nil",
    "        sdkDeviceMembershipVerified = false\n        correlatedTargetID = nil\n        membershipAccountUID = nil",
    "membership invalidates pending correlation",
)
app = replace_once(
    app,
    "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
    "membership correlated phase failure",
)
app = replace_once(
    app,
    "        baseline.removeAll()\n        selectedID = nil\n        sdkLocalBLEOnline = false",
    "        baseline.removeAll()\n        selectedID = nil\n        correlatedTargetID = nil\n        sdkLocalBLEOnline = false",
    "reset pending correlation",
)
app = replace_once(
    app,
    "    private func failLocally(_ text: String, _ kind: String) {\n        if phase == .baseline || phase == .powerOn || phase == .scanning {",
    "    private func failLocally(_ text: String, _ kind: String) {\n        correlatedTargetID = nil\n        if phase == .baseline || phase == .powerOn || phase == .scanning {",
    "failure clears pending correlation",
)

app = replace_once(
    app,
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance" : "Not authoritative")',
    "field build row",
)
app = replace_once(
    app,
    '''            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before even the OFF baseline scan can start.")''',
    '''            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: exact compiled field-build provenance, the current SDK account identity, and exact scooter membership must all be proven before OFF1 correlation can start.")''',
    "physical no-go authority",
)
app = replace_once(
    app,
    "                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "OFF1 affordance authority",
)

correlated_ui = '''            case .correlated:
                Text("Fresh correlation found exactly one repeatable full Bluetooth target. Confirm this correlated current-session candidate before authentication.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Confirm correlated target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

'''
app = replace_once(
    app,
    "            default:\n                EmptyView()\n            }\n\n            ForEach(test.candidates.prefix(8))",
    correlated_ui + "            default:\n                EmptyView()\n            }\n\n            ForEach(test.candidates.prefix(8))",
    "correlated confirmation UI",
)
app = replace_once(
    app,
    "                    !candidate.likely\n                        || !test.privateConfig",
    "                    !candidate.likely\n                        || !test.fieldBuildIsAuthoritative\n                        || !test.privateConfig",
    "authentication build authority",
)

app_path.write_text(app)

tests = test_path.read_text()
tests = replace_once(
    tests,
    '#expect(discoveryCard.contains("Button(\\"Start scooter-OFF baseline\\")"))',
    '#expect(discoveryCard.contains("Button(\\"Start OFF1 correlation\\")"))',
    "current OFF1 source-test anchor",
)
tests = replace_once(
    tests,
    '            to: "private func beginBaselineScan"',
    '            to: "private func beginCorrelationSeries"',
    "current correlation source-test anchor",
)
test_path.write_text(tests)
