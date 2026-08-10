from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()
start = source.index("    @ViewBuilder\n    private var stageRail: some View")
end = source.index("    @ViewBuilder\n    private var primarySurface: some View", start)
rail = source[start:end]

accessibility_marker = "            .accessibilityElement(children: .combine)\n        } else {"
accessibility_replacement = """            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                test.phase == .accepted
                    ? "All 4 Capture steps complete, Seal"
                    : "Step \\(currentStageIndex + 1) of 4, \\(stageLabels[currentStageIndex])"
            )
        } else {"""
if rail.count(accessibility_marker) != 1:
    raise SystemExit(f"Expected one accessibility-size stage branch boundary; found {rail.count(accessibility_marker)}")
rail = rail.replace(accessibility_marker, accessibility_replacement, 1)

old_label = '                    .accessibilityLabel("Step \\(index + 1), \\(label)\\(index == currentStageIndex ? ", current" : index < currentStageIndex ? ", complete" : ", upcoming")")'
new_label = '                    .accessibilityLabel("Step \\(index + 1), \\(label)\\(test.phase == .accepted || index < currentStageIndex ? ", complete" : index == currentStageIndex ? ", current" : ", upcoming")")'
if rail.count(old_label) != 1:
    raise SystemExit(f"Expected one standard stage VoiceOver label; found {rail.count(old_label)}")
rail = rail.replace(old_label, new_label, 1)

source = source[:start] + rail + source[end:]

assert 'All 4 Capture steps complete, Seal' in rail
assert 'test.phase == .accepted || index < currentStageIndex ? ", complete"' in rail
assert 'index == currentStageIndex ? ", current"' in rail
assert 'while redacted[custodyKey] != nil' in source
assert 'sdk_source_authority_changed_before_application_event_custody' in source

path.write_text(source)
