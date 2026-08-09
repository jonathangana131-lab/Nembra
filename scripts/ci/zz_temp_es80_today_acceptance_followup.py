from __future__ import annotations

from pathlib import Path
import re

ROOT = Path('.')


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Product: make the real Capture scroll surface deterministic in landscape,
# and compact only the vertical rhythm when height is constrained.
# ---------------------------------------------------------------------------
shell_path = 'NembraApp/Features/Research/ES80CaptureShellView.swift'
shell = read(shell_path)

shell = replace_once(
    shell,
    '    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n'
    '    @Environment(\\.accessibilityReduceTransparency) private var accessibilityReduceTransparency\n',
    '    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n'
    '    @Environment(\\.verticalSizeClass) private var verticalSizeClass\n'
    '    @Environment(\\.accessibilityReduceTransparency) private var accessibilityReduceTransparency\n',
    'Capture vertical size-class environment',
)

shell = replace_once(
    shell,
    '            ScrollView {\n'
    '                VStack(alignment: .leading, spacing: 24) {\n',
    '            ScrollView {\n'
    '                VStack(alignment: .leading, spacing: captureVerticalSpacing) {\n',
    'Capture root vertical spacing',
)

shell = replace_once(
    shell,
    '                .frame(maxWidth: 660)\n'
    '                .padding(.horizontal, 22)\n'
    '                .padding(.top, 18)\n'
    '                .padding(.bottom, 42)\n'
    '                .frame(maxWidth: .infinity)\n'
    '            }\n'
    '            .background(Color.black.ignoresSafeArea())\n',
    '                .frame(maxWidth: 660)\n'
    '                .padding(.horizontal, 22)\n'
    '                .padding(.top, captureTopPadding)\n'
    '                .padding(.bottom, captureBottomPadding)\n'
    '                .frame(maxWidth: .infinity)\n'
    '            }\n'
    '            .accessibilityIdentifier("es80.capture.scroll")\n'
    '            .background(Color.black.ignoresSafeArea())\n',
    'Capture root paddings and scroll identifier',
)

shell = replace_once(
    shell,
    '    private func hero(for phase: Phase) -> some View {\n',
    '    private var captureVerticalSpacing: CGFloat {\n'
    '        verticalSizeClass == .compact ? 16 : 24\n'
    '    }\n\n'
    '    private var captureTopPadding: CGFloat {\n'
    '        verticalSizeClass == .compact ? 10 : 18\n'
    '    }\n\n'
    '    private var captureBottomPadding: CGFloat {\n'
    '        verticalSizeClass == .compact ? 20 : 42\n'
    '    }\n\n'
    '    private func hero(for phase: Phase) -> some View {\n',
    'Capture compact-height metrics',
)
write(shell_path, shell)


# ---------------------------------------------------------------------------
# Product: the physical NO-GO screen is deliberately glanceable in landscape.
# The first retained failure clipped the lock boundary by ~3.7 pt. Compact-height
# rhythm removes waste without hiding content or weakening the lock hierarchy.
# ---------------------------------------------------------------------------
app_path = 'NembraApp/App/NembraApp.swift'
app = read(app_path)
marker = '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n'
start = app.find(marker)
if start < 0:
    raise SystemExit('NO-GO view marker not found')
prefix = app[:start]
no_go = app[start:]

no_go = replace_once(
    no_go,
    '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n'
    '    @State private var engineeringDetailsExpanded = false\n',
    '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n'
    '    @Environment(\\.verticalSizeClass) private var verticalSizeClass\n'
    '    @State private var engineeringDetailsExpanded = false\n',
    'NO-GO vertical size-class environment',
)
no_go = replace_once(
    no_go,
    '        ScrollView {\n'
    '            VStack(alignment: .leading, spacing: 28) {\n'
    '                VStack(alignment: .leading, spacing: 14) {\n',
    '        ScrollView {\n'
    '            VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 16 : 28) {\n'
    '                VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 9 : 14) {\n',
    'NO-GO compact root rhythm',
)

# Only the first two card paddings inside this view are the physical-lock and
# Engineering Details surfaces; both keep 44pt action semantics while shedding
# excess vertical chrome in compact-height landscape.
first_padding = no_go.find('                .padding(18)\n')
if first_padding < 0:
    raise SystemExit('NO-GO physical card padding not found')
no_go = (
    no_go[:first_padding]
    + '                .padding(verticalSizeClass == .compact ? 12 : 18)\n'
    + no_go[first_padding + len('                .padding(18)\n'):]
)
second_padding = no_go.find('                .padding(18)\n', first_padding + 1)
if second_padding < 0:
    raise SystemExit('NO-GO Engineering Details card padding not found')
no_go = (
    no_go[:second_padding]
    + '                .padding(verticalSizeClass == .compact ? 12 : 18)\n'
    + no_go[second_padding + len('                .padding(18)\n'):]
)

no_go = replace_once(
    no_go,
    '            .frame(maxWidth: 660)\n'
    '            .padding(.horizontal, 22)\n'
    '            .padding(.top, 18)\n'
    '            .padding(.bottom, 42)\n'
    '            .frame(maxWidth: .infinity)\n'
    '        }\n'
    '        .background(Color.black.ignoresSafeArea())\n',
    '            .frame(maxWidth: 660)\n'
    '            .padding(.horizontal, 22)\n'
    '            .padding(.top, verticalSizeClass == .compact ? 8 : 18)\n'
    '            .padding(.bottom, verticalSizeClass == .compact ? 20 : 42)\n'
    '            .frame(maxWidth: .infinity)\n'
    '        }\n'
    '        .accessibilityIdentifier("es80.capture.field-no-go-scroll")\n'
    '        .background(Color.black.ignoresSafeArea())\n',
    'NO-GO compact root paddings',
)
app = prefix + no_go
write(app_path, app)


# ---------------------------------------------------------------------------
# Source-contract tests: retain the safety contract while following the current
# architecture/copy instead of stale implementation strings from older V14.
# ---------------------------------------------------------------------------
app_tests_path = 'NembraAppTests/NembraAppTests.swift'
app_tests = read(app_tests_path)
app_tests = replace_once(
    app_tests,
    '        XCTAssertTrue(shell.contains("observation timer"))\n'
    '        XCTAssertTrue(shell.contains("seconds of display guidance remaining"))\n'
    '        XCTAssertTrue(shell.contains("The package producer, not this timer"))\n'
    '        XCTAssertTrue(shell.contains("Unavailable; waiting for accepted Horizon authority"))\n',
    '        XCTAssertTrue(shell.contains("seconds of display guidance remaining"))\n'
    '        XCTAssertTrue(shell.contains("The displayed timer is guidance only."))\n'
    '        XCTAssertTrue(shell.contains("presentationCanFinalizeObservationHorizon(status: status)"))\n'
    '        XCTAssertTrue(shell.contains("Available only after Nembra verifies the required observation time."))\n',
    'Capture timer/Horizon source contract',
)
write(app_tests_path, app_tests)


# ---------------------------------------------------------------------------
# UI acceptance tests: each UI case establishes portrait independently so one
# aborted landscape case cannot contaminate the following test. Scroll the real
# Capture ScrollView when reviewing below-the-fold landscape/AXXXL states.
# ---------------------------------------------------------------------------
ui_path = 'NembraUITests/ES80ResearchCaptureUITests.swift'
ui = read(ui_path)

ui = replace_once(
    ui,
    '        XCTAssertTrue(\n'
    '            appSource.contains("if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"),\n'
    '            "The normal research route must still be downstream of the package field gate."\n'
    '        )\n'
    '        XCTAssertTrue(\n'
    '            appSource.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"),\n'
    '            "The real field route must retain its package-owned attested factory."\n'
    '        )\n',
    '        XCTAssertTrue(\n'
    '            appSource.contains(".makeResearchAuthorizedES80ForCurrentApplication()"),\n'
    '            "The real field route must acquire its coordinator only through the package-owned research-authorized factory."\n'
    '        )\n'
    '        XCTAssertFalse(\n'
    '            appSource.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"),\n'
    '            "The permanently denied public field factory must not become the app research route."\n'
    '        )\n',
    'Simulator seam package-authority source contract',
)

ui = replace_once(
    ui,
    '            source.contains("if let data = finalShareData"),\n'
    '            "A temporary Share-file retry must reuse retained verified bytes rather than mint a new evidence artifact."\n',
    '            source.contains("guard let data = finalShareData"),\n'
    '            "A temporary Share-file retry must reuse retained verified bytes rather than mint a new evidence artifact."\n',
    'Final Share retained-byte source contract',
)

# Make every MainActor UI test self-contained with respect to orientation.
pattern = re.compile(r'(    @MainActor\n    func test[^\n]+\{\n)')
ui, orientation_insertions = pattern.subn(
    lambda match: match.group(1) + '        XCUIDevice.shared.orientation = .portrait\n',
    ui,
)
if orientation_insertions < 10:
    raise SystemExit(f'Expected at least 10 UI orientation isolation insertions, found {orientation_insertions}')

ui = replace_once(
    ui,
    '            app.swipeUp()\n'
    '            remaining -= 1\n',
    '            let captureScroll = app.scrollViews["es80.capture.scroll"]\n'
    '            if captureScroll.exists {\n'
    '                captureScroll.swipeUp()\n'
    '            } else {\n'
    '                app.swipeUp()\n'
    '            }\n'
    '            remaining -= 1\n',
    'Capture viewport navigation uses real ScrollView',
)
write(ui_path, ui)


# Final guards: preserve the truth boundary and ensure the intended acceptance
# seams exist after every transform.
post_shell = read(shell_path)
post_app = read(app_path)
post_tests = read(ui_path)
for needle, label in [
    ('es80.capture.scroll', 'named Capture scroll surface'),
    ('guard status.physicalProcedurePermitted else', 'physical procedure gate in Capture shell'),
    ('Synthetic Simulator QA presentation only', 'synthetic-only completion disclosure'),
    ('makeResearchAuthorizedES80ForCurrentApplication()', 'package research-authorized app factory'),
    ('.noGo(.finalComposedBuildNotAuthorized)', 'static NO-GO source assertion'),
]:
    haystack = post_shell + '\n' + post_app + '\n' + post_tests + '\n' + read('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneFieldExecutionGate.swift')
    if needle not in haystack:
        raise SystemExit(f'Missing required post-repair contract: {label}')

if 'writeValue(' in read('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift'):
    raise SystemExit('Unexpected application characteristic-value write path appeared')

print(f'orientation isolation insertions: {orientation_insertions}')
print('ES80 TODAY Xcode acceptance follow-up transform: PASS')
