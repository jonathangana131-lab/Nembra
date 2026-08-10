from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text(encoding="utf-8")

# Correlation title + ordinal: keep the compact baseline, but stack at accessibility sizes.
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

# Authenticated observation label + seconds: do not squeeze them together at AX sizes.
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
    'accessibilityValue("\\(correlationDisplayedWindowOrdinal) of 4 windows")',
    'accessibilityLabel("Authenticated observation progress")',
    'accessibilityValue("\\(Int(min(age, 45))) of 45 seconds")',
    "func signOut()",
    "Use a different Tuya account",
    "func retry()",
    "failureRecoveryContextPanel",
    "test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)",
):
    if required not in text:
        raise SystemExit(f"required product contract missing after AX reflow: {required}")

path.write_text(text, encoding="utf-8")
