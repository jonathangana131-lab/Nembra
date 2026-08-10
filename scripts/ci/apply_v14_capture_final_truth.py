from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = app_path.read_text(encoding="utf-8")
old_text = '                    Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")'
new_text = '                    Text("\\(correlationDisplayedWindowOrdinal)/4")'
if source.count(old_text) != 1:
    raise SystemExit(f"expected exactly one stale correlation ordinal, found {source.count(old_text)}")
source = source.replace(old_text, new_text, 1)
anchor = "    private var correlationPanel: some View {\n"
if source.count(anchor) != 1:
    raise SystemExit("correlationPanel anchor changed")
property_source = "    private var correlationDisplayedWindowOrdinal: Int {\n        test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)\n    }\n\n"
source = source.replace(anchor, property_source + anchor, 1)
app_path.write_text(source, encoding="utf-8")

if old_text in source:
    raise SystemExit("stale visible completed+1 correlation ordinal survived")
for required in (
    "private var correlationDisplayedWindowOrdinal: Int",
    "test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)",
    'Text("\\(correlationDisplayedWindowOrdinal)/4")',
    "ES80-AUTHENTICATED-STATIONARY-v1",
    "schemaVersion: 10",
):
    if required not in source:
        raise SystemExit(f"required current-spine contract missing: {required}")
