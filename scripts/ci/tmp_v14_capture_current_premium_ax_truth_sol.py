from pathlib import Path
import subprocess

PREMIUM = "3c1d4394b7b443936240131e6d0d91ca01e49383"
ENTRY = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureP0RootVisualAcceptanceTests.swift")
ROOT_START = "@MainActor\nprivate struct CaptureP0Root: View {"
CONTROLLER_START = "@MainActor\nprivate final class SecureLinkController"

current = ENTRY.read_text(encoding="utf-8")
premium = subprocess.check_output(
    ["git", "show", f"{PREMIUM}:NembraApp/App/NembraCaptureEntrypoint.swift"],
    text=True,
)

for label, text in (("current", current), ("premium", premium)):
    if ROOT_START not in text or CONTROLLER_START not in text:
        raise SystemExit(f"{label} Capture root boundaries drifted")

current_prefix, current_after_start = current.split(ROOT_START, 1)
_, current_suffix = current_after_start.split(CONTROLLER_START, 1)
_, premium_after_start = premium.split(ROOT_START, 1)
premium_root, _ = premium_after_start.split(CONTROLLER_START, 1)
root = ROOT_START + premium_root

# Preserve the current final spine's explicit VoiceOver heading semantics while
# adopting the stronger premium/action-first root presentation.
hero_start = root.index("    private var rootHero: some View")
hero_end = root.index("    private var buildAuthorityStatus: some View", hero_start)
hero = root[hero_start:hero_end]
heading_anchor = '''            .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())\n            .fixedSize(horizontal: false, vertical: true)\n'''
if hero.count(heading_anchor) != 1:
    raise SystemExit("premium hero heading anchor drifted")
hero = hero.replace(
    heading_anchor,
    heading_anchor + "            .accessibilityAddTraits(.isHeader)\n",
    1,
)
combined = "        .accessibilityElement(children: .combine)\n"
if hero.count(combined) != 1:
    raise SystemExit("premium hero combined-element anchor drifted")
hero = hero.replace(combined, "", 1)
root = root[:hero_start] + hero + root[hero_end:]

required_root = [
    'Text(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
    'NavigationLink(fieldBuildIsAuthoritative ? "Continue to preflight" : "View locked preflight")',
    'private var isAccessibilityLayout: Bool',
    'private var statusText: some View',
    'private func rootSection<Content: View>',
    '.frame(maxWidth: .infinity, minHeight: 50)',
    '.tint(.cyan)',
    '.accessibilityAddTraits(.isHeader)',
    'Public build: account metadata only. Bluetooth and physical evidence stay locked.',
]
for token in required_root:
    if token not in root:
        raise SystemExit(f"missing premium/current truth token: {token}")
for forbidden in (
    "private func rootPanel<Content: View>",
    "writeValue",
    "publishDps",
    "queryDps",
    "SIMCTL_CHILD_",
    "NEMBRA_SIMULATION_",
):
    if forbidden in root:
        raise SystemExit(f"forbidden root token: {forbidden}")
if ".dynamicTypeSize(" in root:
    raise SystemExit("Dynamic Type cap detected")

# Only the root is transplanted. The current final spine's app prefix and the
# entire SecureLink controller/runtime suffix remain byte-for-byte current.
ENTRY.write_text(current_prefix + root + CONTROLLER_START + current_suffix, encoding="utf-8")

# Strengthen the current final-spine source contract rather than replaying a
# stale test blob. Keep provenance/heading assertions and add the exact
# premium-layout + action-before-status invariants demonstrated by prior pixels.
test = TEST.read_text(encoding="utf-8")
heading_expect = '        #expect(root.contains(".accessibilityAddTraits(.isHeader)"))\n'
if test.count(heading_expect) != 1:
    raise SystemExit("current heading source contract drifted")
layout_expect = '''        #expect(root.contains("private var isAccessibilityLayout: Bool"))\n        #expect(root.contains("private func rootSection<Content: View>"))\n        #expect(!root.contains("private func rootPanel<Content: View>"))\n'''
test = test.replace(heading_expect, heading_expect + layout_expect, 1)

section_marker = "    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n"
if test.count(section_marker) != 1:
    raise SystemExit("visual source-test insertion marker drifted")
ordering_test = '''    @Test("Accessibility setup promotes the primary action ahead of verbose status")\n    func accessibilitySetupPromotesActionBeforeVerboseStatus() throws {\n        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")\n        let panel = String(try section(\n            in: source,\n            from: "private var accountSetupPanel: some View",\n            to: "private var statusText: some View"\n        ))\n\n        let standardBranch = try #require(panel.range(of: "if !isAccessibilityLayout {"))\n        let field = try #require(panel.range(of: "TextField"))\n        let action = try #require(panel.range(of: "Create approval QR"))\n        let standardStatus = try #require(panel.range(\n            of: "statusText",\n            range: standardBranch.upperBound..<field.lowerBound\n        ))\n        let accessibilityBranch = try #require(panel.range(\n            of: "if isAccessibilityLayout {",\n            range: action.upperBound..<panel.endIndex\n        ))\n        let accessibilityStatus = try #require(panel.range(\n            of: "statusText",\n            range: accessibilityBranch.upperBound..<panel.endIndex\n        ))\n\n        #expect(standardStatus.lowerBound < field.lowerBound)\n        #expect(field.lowerBound < action.lowerBound)\n        #expect(action.lowerBound < accessibilityBranch.lowerBound)\n        #expect(accessibilityBranch.lowerBound < accessibilityStatus.lowerBound)\n        #expect(panel.contains(".frame(maxWidth: .infinity, minHeight: 50)"))\n        #expect(panel.contains(".tint(.cyan)"))\n    }\n\n'''
test = test.replace(section_marker, ordering_test + section_marker, 1)
TEST.write_text(test, encoding="utf-8")
