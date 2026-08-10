from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = app_path.read_text(encoding="utf-8")

panel_start = text.index("    private var correlationPanel: some View {")
header_start = text.index("                HStack(alignment: .firstTextBaseline) {", panel_start)
header_end = text.index("\n\n                if test.phase == .correlated {", header_start)
old_header = text[header_start:header_end]
if "correlationDisplayedWindowOrdinal" not in old_header:
    raise SystemExit("correlation header no longer contains current ordinal")
new_header = """                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FIND SCOOTER")
                                .font(.caption2.bold())
                                .tracking(1.2)
                                .foregroundStyle(.cyan)
                            Text(test.phase == .correlated ? "Scooter signal found" : test.correlationWindowLabel)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\\(correlationDisplayedWindowOrdinal)/4")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Correlation progress")
                            .accessibilityValue("\\(correlationDisplayedWindowOrdinal) of 4 windows")
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FIND SCOOTER")
                                .font(.caption2.bold())
                                .tracking(1.2)
                                .foregroundStyle(.cyan)
                            Text(test.phase == .correlated ? "Scooter signal found" : test.correlationWindowLabel)
                                .font(.title2.bold())
                        }
                        Spacer()
                        Text("\\(correlationDisplayedWindowOrdinal)/4")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Correlation progress")
                            .accessibilityValue("\\(correlationDisplayedWindowOrdinal) of 4 windows")
                    }
                }"""
text = text[:header_start] + new_header + text[header_end:]

obs_start = text.index("                    let age = test.canonicalObservedAgeSeconds ?? 0")
timer_start = text.index("                        HStack {", obs_start)
timer_end = text.index("\n                        ProgressView(value: min(age / 45, 1))", timer_start)
old_timer = text[timer_start:timer_end]
if "Authenticated observation" not in old_timer:
    raise SystemExit("authenticated observation header changed")
new_timer = """                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Authenticated observation")
                                    .font(.subheadline.weight(.semibold))
                                Text("\\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        } else {
                            HStack {
                                Text("Authenticated observation")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        }"""
text = text[:timer_start] + new_timer + text[timer_end:]
progress = "                        ProgressView(value: min(age / 45, 1))\n"
if text.count(progress) != 1:
    raise SystemExit("observation ProgressView anchor changed")
text = text.replace(
    progress,
    progress
    + "                            .accessibilityLabel(\"Authenticated observation progress\")\n"
    + "                            .accessibilityValue(\"\\(Int(min(age, 45))) of 45 seconds\")\n",
    1,
)

for required in (
    "if dynamicTypeSize.isAccessibilitySize",
    'accessibilityLabel("Correlation progress")',
    'accessibilityLabel("Authenticated observation progress")',
    "func signOut()",
    "Use a different Tuya account",
    "SignInWithAppleButton(.signIn)",
    "loginByAuth2(",
    'withType: "ap"',
    "func retry()",
    "failureRecoveryContextPanel",
    "test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)",
):
    if required not in text:
        raise SystemExit(f"required current product contract missing after AX reflow: {required}")
app_path.write_text(text, encoding="utf-8")

project_path = Path("NembraCapture.xcodeproj/project.pbxproj")
project = project_path.read_text(encoding="utf-8")
anchor = 'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";'
mapping = 'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";'
if project.count(mapping) == 0:
    if project.count(anchor) != 2:
        raise SystemExit(f"expected two procedure mapping anchors, found {project.count(anchor)}")
    project = project.replace(anchor, anchor + "\n\t\t\t\t" + mapping)
elif project.count(mapping) != 2:
    raise SystemExit(f"partial procedure mapping found: {project.count(mapping)}")
if project.count('CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;') != 2:
    raise SystemExit("Apple sign-in entitlements mapping regressed")
project_path.write_text(project, encoding="utf-8")
