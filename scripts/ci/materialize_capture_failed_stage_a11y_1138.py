from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()

stage_start = source.index("    @ViewBuilder\n    private var stageRail: some View")
stage_end = source.index("    @ViewBuilder\n    private var primarySurface: some View", stage_start)
rail = source[stage_start:stage_end]

old_open = """    @ViewBuilder
    private var stageRail: some View {
        if dynamicTypeSize.isAccessibilitySize {
"""
new_open = """    @ViewBuilder
    private var stageRail: some View {
        if test.phase == .failed {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(heroAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CAPTURE STOPPED")
                        .font(.caption2.bold())
                        .tracking(1.1)
                        .foregroundStyle(heroAccent)
                    Text("No Capture step is current")
                        .font(.headline)
                    Text("Start again from a fresh OFF1 when the blocker is cleared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Capture stopped. No Capture step is current. Start again from a fresh OFF1 when the blocker is cleared.")
        } else if dynamicTypeSize.isAccessibilitySize {
"""
if rail.count(old_open) != 1:
    raise SystemExit(f"Expected one stageRail accessibility opening; found {rail.count(old_open)}")
rail = rail.replace(old_open, new_open, 1)
source = source[:stage_start] + rail + source[stage_end:]

old_title = '        case .failed: return "Capture paused"'
new_title = '        case .failed: return "Capture stopped"'
if source.count(old_title) != 1:
    raise SystemExit(f"Expected one failed phase title; found {source.count(old_title)}")
source = source.replace(old_title, new_title, 1)

# Truth predicates: failed state intercepts the rail before all procedure rendering,
# while accepted and normal stage semantics remain in the source unchanged.
stage_start = source.index("    @ViewBuilder\n    private var stageRail: some View")
stage_end = source.index("    @ViewBuilder\n    private var primarySurface: some View", stage_start)
rail = source[stage_start:stage_end]
assert rail.index("test.phase == .failed") < rail.index("dynamicTypeSize.isAccessibilitySize")
assert "No Capture step is current" in rail
assert ".accessibilityLabel(\"Capture stopped. No Capture step is current." in rail
assert "test.phase == .accepted" in rail
assert 'case .failed: return "Capture stopped"' in source
assert 'case .failed: return "Capture paused"' not in source

path.write_text(source)
