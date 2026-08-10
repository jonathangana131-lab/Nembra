from pathlib import Path
import re

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    source = source.replace(old, new, 1)


replace_once(
    "        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed\n",
    "        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed\n",
    "correlated phase",
)

replace_once("    static let fd50 = CBUUID(string: \"FD50\")\n", "", "legacy FD50 scanner constant")
replace_once("    private var central: CBCentralManager!\n", "", "legacy central manager")
replace_once("    private var baseline = Set<UUID>()\n", "", "legacy baseline set")
replace_once("        central = CBCentralManager(delegate: self, queue: .main)\n", "", "legacy manager init")

replace_once(
    "    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n",
    "    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var targetCorrelationIsOperatorConfirmed: Bool { targetCorrelationOperatorConfirmed }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n",
    "presentation authority properties",
)

old_single = '''            byID = [id: candidate]\n            candidates = [candidate]\n            selectedID = id\n            correlationSession = nil\n            phase = .selected\n            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Discovery is retired before Tuya's SDK takes BLE ownership."\n            log("candidate_selected", [\n                "id": id.uuidString,\n                "authority": "fresh-repeated-off-on-full-corebluetooth-id",\n                "historicalCaptureUUIDMatch": String(historicalCaptureID),\n                "windows": String(result.windows.count)\n            ])\n'''
new_single = '''            byID = [id: candidate]\n            candidates = [candidate]\n            selectedID = nil\n            correlationSession = nil\n            phase = .correlated\n            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Confirm this correlated target explicitly before Tuya's SDK may take BLE ownership. This is current-session correlation evidence, not permanent scooter identity."\n            log("candidate_correlated", [\n                "id": id.uuidString,\n                "authority": "fresh-repeated-off-on-full-corebluetooth-id-pending-operator-confirmation",\n                "historicalCaptureUUIDMatch": String(historicalCaptureID),\n                "windows": String(result.windows.count)\n            ])\n'''
replace_once(old_single, new_single, "correlation auto-promotion")

replace_once(
    "    func invalidateSDKMembership() {\n",
    '''    func confirmCorrelatedTarget() {\n        guard phase == .correlated,\n              buildIdentity.isAuthoritativeFieldBuild,\n              sdkAccountLoggedIn,\n              sdkDeviceMembershipVerified,\n              accountIdentityLeaseIsAuthorized,\n              selectedID == nil,\n              candidates.count == 1,\n              let candidate = candidates.first,\n              candidate.likely,\n              byID[candidate.id] == candidate else {\n            targetCorrelationOperatorConfirmed = false\n            byID.removeAll()\n            candidates.removeAll()\n            selectedID = nil\n            failLocally("Correlated-target confirmation authority changed or became ambiguous. Restart from OFF1 after re-verifying the exact current SDK account and scooter membership.", "target_correlation_confirmation_rejected")\n            return\n        }\n\n        selectedID = candidate.id\n        targetCorrelationOperatorConfirmed = true\n        phase = .selected\n        message = "Correlated Bluetooth target explicitly confirmed for this capture attempt. This does not establish permanent scooter identity. Tuya same-account membership remains separate authentication authority."\n        log("candidate_selected", [\n            "id": candidate.id.uuidString,\n            "authority": "explicit-operator-confirmation-of-fresh-repeated-correlation",\n            "correlation": "off1-on1-off2-on2-full-corebluetooth-id",\n            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)\n        ])\n    }\n\n    func invalidateSDKMembership() {\n''',
    "explicit confirmation action",
)

source = source.replace(
    "if phase == .baseline || phase == .powerOn || phase == .scanning {",
    "if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {",
)
replace_once(
    "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {\n",
    "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {\n",
    "membership invalidation phases",
)

replace_once(
    "        guard let candidate = selected, candidate.likely else {\n",
    "        guard let candidate = selected, candidate.likely, targetCorrelationOperatorConfirmed else {\n",
    "authentication requires explicit confirmation",
)

source = source.replace("        central.stopScan()\n", "")
source = source.replace("        baseline.removeAll()\n", "")

scanner_pattern = re.compile(
    r"\n    private static func hasTuyaCompanyID\(_ data: Data\?\) -> Bool \{.*?\n\}\n\nextension SecureLinkController: @preconcurrency CBCentralManagerDelegate \{.*?\n\}\n\n@MainActor\nprivate protocol OfficialTuyaDriver",
    re.S,
)
source, scanner_count = scanner_pattern.subn(
    "\n}\n\n@MainActor\nprivate protocol OfficialTuyaDriver",
    source,
    count=1,
)
if scanner_count != 1:
    raise SystemExit(f"legacy app scanner removal: expected exactly one block, found {scanner_count}")

replace_once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")\n',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Authoritative" : "Not authoritative")\n',
    "field build row",
)
replace_once(
    "            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n",
    "            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n",
    "NO-GO build authority",
)
replace_once(
    "                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n",
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n",
    "OFF1 build authority",
)

replace_once(
    '''            case .powerOn:\n                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")\n                    .foregroundStyle(.secondary)\n                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }\n                    .buttonStyle(.borderedProminent)\n\n            default:\n''',
    '''            case .powerOn:\n                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")\n                    .foregroundStyle(.secondary)\n                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }\n                    .buttonStyle(.borderedProminent)\n\n            case .correlated:\n                Text("One repeatable full CoreBluetooth target is correlated for this capture attempt. Confirm it explicitly before authentication; this does not establish permanent scooter identity.")\n                    .font(.footnote)\n                    .foregroundStyle(.secondary)\n                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }\n                    .buttonStyle(.borderedProminent)\n                    .disabled(!test.fieldBuildIsAuthoritative || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)\n\n            default:\n''',
    "confirmation UI",
)

replace_once(
    '''                    !candidate.likely\n                        || !test.privateConfig\n''',
    '''                    !candidate.likely\n                        || !test.fieldBuildIsAuthoritative\n                        || !test.targetCorrelationIsOperatorConfirmed\n                        || !test.privateConfig\n''',
    "authentication UI authority",
)

path.write_text(source)

# Fail closed if any competing app-owned scanner survived.
for forbidden in [
    "private var central: CBCentralManager",
    "CBCentralManager(delegate: self",
    "CBCentralManagerDelegate",
    "central.scanForPeripherals",
    "central.stopScan",
    "private func updateCandidate",
    "didDiscover peripheral",
    "CBAdvertisementDataServiceUUIDsKey",
    "CBAdvertisementDataManufacturerDataKey",
    "CBAdvertisementDataIsConnectableKey",
]:
    if forbidden in source:
        raise SystemExit(f"legacy discovery authority survived: {forbidden}")

required = [
    "case idle, baseline, powerOn, scanning, correlated, selected",
    "func confirmCorrelatedTarget()",
    "phase = .correlated",
    "targetCorrelationOperatorConfirmed = true",
    "explicit-operator-confirmation-of-fresh-repeated-correlation",
    "var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }",
    'LabeledContent("Field build", value: test.fieldBuildIsAuthoritative',
    'Button("Start OFF1 correlation")',
    'Button("Confirm correlated Bluetooth target")',
    "PassiveBluetoothPowerCycleObservationSession",
]
for needle in required:
    if needle not in source:
        raise SystemExit(f"missing repaired product authority: {needle}")

finish = source[source.index("private func finishCorrelationSeries"):source.index("func confirmCorrelatedTarget")]
for forbidden in ["selectedID = id", "phase = .selected", 'log("candidate_selected"']:
    if forbidden in finish:
        raise SystemExit(f"correlation still auto-promotes target: {forbidden}")

print("Capture product-authority patch assertions PASS")
