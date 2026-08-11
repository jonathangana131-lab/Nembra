from pathlib import Path

entry_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = entry_path.read_text(encoding="utf-8")

old_state = '''    @StateObject private var tuya = TuyaAccountBridge()\n    @State private var showEngineeringDetails = false\n    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n\n    private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }\n'''
new_state = '''    @StateObject private var tuya = TuyaAccountBridge()\n    @State private var showEngineeringDetails = false\n    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    private let buildIdentity = NembraCaptureBuildIdentity.current\n\n    private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }\n    private var isAuthoritativeFieldBuild: Bool { buildIdentity.isAuthoritativeFieldBuild }\n'''
if source.count(old_state) != 1:
    raise SystemExit("CaptureP0Root state/identity anchor drifted")
source = source.replace(old_state, new_state, 1)

old_intro_copy = '''            Text(\n                isAccessibilityLayout\n                    ? "Link the Tuya account that owns this scooter. Bluetooth stays off until account and device checks are complete."\n                    : "Link the account that owns this scooter. Nembra verifies the account and device again before any passive Bluetooth correlation begins."\n            )\n            .font(isAccessibilityLayout ? .callout : .body)\n            .foregroundStyle(Color.white.opacity(0.76))\n            .fixedSize(horizontal: false, vertical: true)\n'''
new_intro_copy = '''            Label(\n                isAuthoritativeFieldBuild ? "Field build ready" : "Physical capture locked",\n                systemImage: isAuthoritativeFieldBuild ? "checkmark.shield.fill" : "lock.shield.fill"\n            )\n            .font(.subheadline.weight(.semibold))\n            .foregroundStyle(isAuthoritativeFieldBuild ? Color.green : Color.orange)\n\n            Text(introSupportCopy)\n                .font(isAccessibilityLayout ? .callout : .body)\n                .foregroundStyle(Color.white.opacity(0.76))\n                .fixedSize(horizontal: false, vertical: true)\n'''
if source.count(old_intro_copy) != 1:
    raise SystemExit("CaptureP0Root intro copy anchor drifted")
source = source.replace(old_intro_copy, new_intro_copy, 1)

intro_end = '''        .accessibilityElement(children: .combine)\n    }\n\n    private var accountSection: some View {\n'''
intro_end_replacement = '''        .accessibilityElement(children: .combine)\n    }\n\n    private var introSupportCopy: String {\n        if !isAuthoritativeFieldBuild {\n            return "This public build can prepare account metadata. It cannot scan or collect physical scooter evidence."\n        }\n        if isAccessibilityLayout {\n            return "Nembra does not begin passive Bluetooth correlation until account and device checks are complete."\n        }\n        return "Link the account that owns this scooter. Nembra verifies the account and device again before any passive Bluetooth correlation begins."\n    }\n\n    private var accountSection: some View {\n'''
if source.count(intro_end) != 1:
    raise SystemExit("CaptureP0Root intro terminator drifted")
source = source.replace(intro_end, intro_end_replacement, 1)

heading = '''                        Text(tuya.isLinked ? "Account link ready" : "Link your scooter account")\n                            .font(.title3.bold())\n                            .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)\n'''
heading_replacement = '''                        Text(tuya.isLinked ? "Account link ready" : "Link your scooter account")\n                            .font(.title3.bold())\n                            .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)\n                            .accessibilityAddTraits(.isHeader)\n'''
if source.count(heading) != 1:
    raise SystemExit("account heading anchor drifted")
source = source.replace(heading, heading_replacement, 1)

old_hint = '''                    .accessibilityHint("Creates the Tuya approval QR code for this account. Bluetooth remains off.")\n'''
new_hint = '''                    .accessibilityHint("Creates the Tuya approval QR code for this account; passive scooter correlation has not begun.")\n'''
if source.count(old_hint) != 1:
    raise SystemExit("approval hint anchor drifted")
source = source.replace(old_hint, new_hint, 1)

old_continue = '''        if tuya.selectedDeviceID == device.id,\n           tuya.phase == .ready,\n           !device.productID.isEmpty,\n           !device.uuid.isEmpty {\n            NavigationLink("Continue to Capture") { SecureLinkView(device: device) }\n                .buttonStyle(.borderedProminent)\n                .controlSize(.large)\n        }\n'''
new_continue = '''        if tuya.selectedDeviceID == device.id,\n           tuya.phase == .ready,\n           !device.productID.isEmpty,\n           !device.uuid.isEmpty {\n            if isAuthoritativeFieldBuild {\n                NavigationLink("Continue to Capture") { SecureLinkView(device: device) }\n                    .buttonStyle(.borderedProminent)\n                    .controlSize(.large)\n            } else {\n                NavigationLink("View locked preflight") { SecureLinkView(device: device) }\n                    .buttonStyle(.bordered)\n                    .controlSize(.large)\n            }\n        }\n'''
if source.count(old_continue) != 1:
    raise SystemExit("continue button anchor drifted")
source = source.replace(old_continue, new_continue, 1)

for forbidden in ("writeValue", "publishDps", "queryDps", "SIMCTL_CHILD_", "NEMBRA_SIMULATION_"):
    root = source[source.index("private struct CaptureP0Root: View"):source.index("private final class SecureLinkController")]
    if forbidden in root:
        raise SystemExit(f"forbidden authority token entered root: {forbidden}")
if ".dynamicTypeSize(" in root:
    raise SystemExit("Dynamic Type cap detected")

required = [
    "NembraCaptureBuildIdentity.current",
    "isAuthoritativeFieldBuild",
    "Field build ready",
    "Physical capture locked",
    "account metadata",
    "cannot scan",
    "physical scooter evidence",
    "Nembra does not begin passive Bluetooth correlation until account and device checks are complete.",
    "passive scooter correlation has not begun.",
    ".accessibilityAddTraits(.isHeader)",
    "View locked preflight",
]
for marker in required:
    if marker not in root:
        raise SystemExit(f"missing transformed marker: {marker}")
entry_path.write_text(source, encoding="utf-8")

visual_test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductVisualAccessibilitySourceTests.swift")
visual = visual_test_path.read_text(encoding="utf-8")
old_expect = '''        #expect(account.contains("Bluetooth remains off"))\n'''
new_expect = '''        #expect(root.contains("Nembra does not begin passive Bluetooth correlation until account and device checks are complete."))\n        #expect(account.contains("passive scooter correlation has not begun."))\n        #expect(account.contains(".accessibilityAddTraits(.isHeader)"))\n'''
if visual.count(old_expect) != 1:
    raise SystemExit("visual accessibility Bluetooth assertion drifted")
visual = visual.replace(old_expect, new_expect, 1)
visual_test_path.write_text(visual, encoding="utf-8")
