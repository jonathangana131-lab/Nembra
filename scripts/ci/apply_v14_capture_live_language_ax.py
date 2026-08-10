from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text(encoding="utf-8")

# Correlation title + 4-window ordinal: preserve compact default, vertically recompose at AX sizes.
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

# Current product language is "Read-only observation". Recompose its timer at AX sizes.
obs_start = text.index("                    let age = test.canonicalObservedAgeSeconds ?? 0")
timer_start = text.index("                        HStack {", obs_start)
timer_end = text.index("\n                        ProgressView(value: min(age / 45, 1))", timer_start)
old_timer = text[timer_start:timer_end]
if "Read-only observation" not in old_timer:
    raise SystemExit("read-only observation header changed")
new_timer = """                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Read-only observation")
                                    .font(.subheadline.weight(.semibold))
                                Text("\\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        } else {
                            HStack {
                                Text("Read-only observation")
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
    + "                            .accessibilityLabel(\"Read-only observation progress\")\n"
    + "                            .accessibilityValue(\"\\(Int(min(age, 45))) of 45 seconds\")\n",
    1,
)

for required in (
    "if dynamicTypeSize.isAccessibilitySize",
    'accessibilityLabel("Correlation progress")',
    'accessibilityLabel("Read-only observation progress")',
    "SignInWithAppleButton(.signIn)",
    "loginByAuth2(",
    'withType: "ap"',
    "test.canRestartFromFreshOFF1 && (!sdkAccount.loggedIn || !test.sdkAccountLoggedIn)",
    "test.canRestartFromFreshOFF1 && test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)",
    "test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)",
):
    if required not in text:
        raise SystemExit(f"required live product contract missing after AX reflow: {required}")

project = Path("NembraCapture.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
if project.count('INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";') != 2:
    raise SystemExit("procedure project mapping is not already canonical")
if project.count('CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;') != 2:
    raise SystemExit("Apple sign-in entitlements mapping regressed")

path.write_text(text, encoding="utf-8")
