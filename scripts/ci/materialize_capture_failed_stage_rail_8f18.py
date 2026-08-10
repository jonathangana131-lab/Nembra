from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureFailedStageRailAccessibilitySourceTests.swift"

STAGE_OLD = '''    @ViewBuilder
    private var stageRail: some View {
        if dynamicTypeSize.isAccessibilitySize {
'''

STAGE_NEW = '''    @ViewBuilder
    private var stageRail: some View {
        if test.phase == .failed {
            VStack(alignment: .leading, spacing: 6) {
                Label("Attempt stopped", systemImage: "stop.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                Text("No Capture step is current. Start a fresh attempt from Target when ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Capture stopped. No Capture step is current. Start a fresh attempt from Target when ready.")
        } else if dynamicTypeSize.isAccessibilitySize {
'''

PHASE_OLD = '        case .failed: return "Capture paused"\n'
PHASE_NEW = '        case .failed: return "Capture stopped"\n'
PANEL_OLD = '                Label("Capture paused", systemImage: "exclamationmark.circle")\n'
PANEL_NEW = '                Label("Capture stopped", systemImage: "exclamationmark.circle")\n'


def replace_exact(source: str, old: str, new: str, expected: int, label: str) -> str:
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"{label}: expected {expected} matches, found {count}")
    return source.replace(old, new)


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "Capture stopped. No Capture step is current." in source:
        raise SystemExit("failed-stage repair already exists; refresh live product")
    source = replace_exact(source, STAGE_OLD, STAGE_NEW, 1, "stage rail insertion")
    source = replace_exact(source, PHASE_OLD, PHASE_NEW, 1, "failed phase title")
    source = replace_exact(source, PANEL_OLD, PANEL_NEW, 2, "failure panel titles")
    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    required = (
        "if test.phase == .failed",
        'Label("Attempt stopped", systemImage: "stop.circle.fill")',
        "No Capture step is current. Start a fresh attempt from Target when ready.",
        '.accessibilityLabel("Capture stopped. No Capture step is current. Start a fresh attempt from Target when ready.")',
        'case .failed: return "Capture stopped"',
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"required failed-state token missing: {token}")
    if 'case .failed: return "Capture paused"' in source:
        raise SystemExit("failed phase still implies resumability")
    if 'Label("Capture paused", systemImage: "exclamationmark.circle")' in source:
        raise SystemExit("failure panel still says paused")
    if source.count('Label("Capture stopped", systemImage: "exclamationmark.circle")') != 2:
        raise SystemExit("failure panel terminal wording not applied consistently")

    start = source.index("private var stageRail: some View")
    end = source.index("private var primarySurface: some View", start)
    rail = source[start:end]
    failed = rail.index("if test.phase == .failed")
    accessibility = rail.index("dynamicTypeSize.isAccessibilitySize")
    if not failed < accessibility:
        raise SystemExit("failed rail does not precede normal stage semantics")
    failed_prefix = rail[failed:accessibility]
    if "stageLabels[currentStageIndex]" in failed_prefix or "Step \\(currentStageIndex + 1)" in failed_prefix:
        raise SystemExit("failed rail still projects a current procedure step")
    if not TEST.exists():
        raise SystemExit("failed-stage regression missing")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
