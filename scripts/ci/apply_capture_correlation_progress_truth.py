from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")

anchor = "    private var correlationPanel: some View {\n"
property_source = """    private var correlationDisplayedWindowOrdinal: Int {
        test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)
    }

"""

if source.count(anchor) != 1:
    raise SystemExit(f"expected exactly one correlation panel anchor, found {source.count(anchor)}")
if "private var correlationDisplayedWindowOrdinal: Int" in source:
    raise SystemExit("correlationDisplayedWindowOrdinal already exists")

source = source.replace(anchor, property_source + anchor, 1)
old = 'Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")'
new = 'Text("\\(correlationDisplayedWindowOrdinal)/4")'
if source.count(old) != 1:
    raise SystemExit(f"expected exactly one visible raw ordinal, found {source.count(old)}")
source = source.replace(old, new, 1)

path.write_text(source, encoding="utf-8")
