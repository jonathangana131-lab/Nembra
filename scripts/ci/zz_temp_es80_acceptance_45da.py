from pathlib import Path
import re


def load(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def save(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)

# Shell: compact-height rhythm + deterministic real scroll surface.
p = 'NembraApp/Features/Research/ES80CaptureShellView.swift'
s = load(p)
s = one(s,
    '    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.accessibilityReduceTransparency) private var accessibilityReduceTransparency\n',
    '    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.verticalSizeClass) private var verticalSizeClass\n    @Environment(\\.accessibilityReduceTransparency) private var accessibilityReduceTransparency\n',
    'shell size class')
s = one(s,
    '            ScrollView {\n                VStack(alignment: .leading, spacing: 24) {\n',
    '            ScrollView {\n                VStack(alignment: .leading, spacing: captureVerticalSpacing) {\n',
    'shell root spacing')
s = one(s,
    '                .frame(maxWidth: 660)\n                .padding(.horizontal, 22)\n                .padding(.top, 18)\n                .padding(.bottom, 42)\n                .frame(maxWidth: .infinity)\n            }\n            .background(Color.black.ignoresSafeArea())\n',
    '                .frame(maxWidth: 660)\n                .padding(.horizontal, 22)\n                .padding(.top, captureTopPadding)\n                .padding(.bottom, captureBottomPadding)\n                .frame(maxWidth: .infinity)\n            }\n            .accessibilityIdentifier("es80.capture.scroll")\n            .background(Color.black.ignoresSafeArea())\n',
    'shell root padding')
s = one(s,
    '    private func hero(for phase: Phase) -> some View {\n',
    '    private var captureVerticalSpacing: CGFloat { verticalSizeClass == .compact ? 16 : 24 }\n\n    private var captureTopPadding: CGFloat { verticalSizeClass == .compact ? 10 : 18 }\n\n    private var captureBottomPadding: CGFloat { verticalSizeClass == .compact ? 20 : 42 }\n\n    private func hero(for phase: Phase) -> some View {\n',
    'shell compact metrics')
save(p, s)

# Locked physical NO-GO: remove only excess compact-height chrome.
p = 'NembraApp/App/NembraApp.swift'
a = load(p)
marker = '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n'
pos = a.find(marker)
if pos < 0: raise SystemExit('NO-GO marker missing')
pre, n = a[:pos], a[pos:]
n = one(n,
    '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n    @State private var engineeringDetailsExpanded = false\n',
    '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n    @Environment(\\.verticalSizeClass) private var verticalSizeClass\n    @State private var engineeringDetailsExpanded = false\n',
    'NO-GO size class')
n = one(n,
    '        ScrollView {\n            VStack(alignment: .leading, spacing: 28) {\n                VStack(alignment: .leading, spacing: 14) {\n',
    '        ScrollView {\n            VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 16 : 28) {\n                VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 9 : 14) {\n',
    'NO-GO compact rhythm')
old_padding = '                .padding(18)\n'
new_padding = '                .padding(verticalSizeClass == .compact ? 12 : 18)\n'
for label in ('physical lock card', 'engineering details card'):
    at = n.find(old_padding)
    if at < 0:
        raise SystemExit(f'{label}: padding match missing')
    n = n[:at] + new_padding + n[at + len(old_padding):]
n = one(n,
    '            .frame(maxWidth: 660)\n            .padding(.horizontal, 22)\n            .padding(.top, 18)\n            .padding(.bottom, 42)\n            .frame(maxWidth: .infinity)\n        }\n        .background(Color.black.ignoresSafeArea())\n',
    '            .frame(maxWidth: 660)\n            .padding(.horizontal, 22)\n            .padding(.top, verticalSizeClass == .compact ? 8 : 18)\n            .padding(.bottom, verticalSizeClass == .compact ? 20 : 42)\n            .frame(maxWidth: .infinity)\n        }\n        .accessibilityIdentifier("es80.capture.field-no-go-scroll")\n        .background(Color.black.ignoresSafeArea())\n',
    'NO-GO root padding')
save(p, pre + n)

# App source contract: assert current display-only timer + accepted Horizon gate.
p = 'NembraAppTests/NembraAppTests.swift'
t = load(p)
t = one(t,
    '        XCTAssertTrue(shell.contains("observation timer"))\n        XCTAssertTrue(shell.contains("seconds of display guidance remaining"))\n        XCTAssertTrue(shell.contains("The package producer, not this timer"))\n        XCTAssertTrue(shell.contains("Unavailable; waiting for accepted Horizon authority"))\n',
    '        XCTAssertTrue(shell.contains("seconds of display guidance remaining"))\n        XCTAssertTrue(shell.contains("The displayed timer is guidance only."))\n        XCTAssertTrue(shell.contains("presentationCanFinalizeObservationHorizon(status: status)"))\n        XCTAssertTrue(shell.contains("Available only after Nembra verifies the required observation time."))\n',
    'timer/Horizon source contract')
save(p, t)

# UI acceptance: current exact source contract + test isolation + target the real ScrollView.
p = 'NembraUITests/ES80ResearchCaptureUITests.swift'
u = load(p)
u = one(u,
    '            source.contains("if let data = finalShareData"),\n            "A temporary Share-file retry must reuse retained verified bytes rather than mint a new evidence artifact."\n',
    '            source.contains("guard let data = finalShareData"),\n            "A temporary Share-file retry must reuse retained verified bytes rather than mint a new evidence artifact."\n',
    'verified final Share retained-byte source contract')
pat = re.compile(r'(    @MainActor\n    func test[^\n]+\{\n)')
u, inserted = pat.subn(lambda m: m.group(1) + '        XCUIDevice.shared.orientation = .portrait\n', u)
if inserted < 10: raise SystemExit(f'orientation isolation count too small: {inserted}')
u = one(u,
    '            app.swipeUp()\n            remaining -= 1\n',
    '            let captureScroll = app.scrollViews["es80.capture.scroll"]\n            if captureScroll.exists {\n                captureScroll.swipeUp()\n            } else {\n                app.swipeUp()\n            }\n            remaining -= 1\n',
    'viewport scroll target')
save(p, u)

# Hard truth guards.
combined = load('NembraApp/App/NembraApp.swift') + load('NembraApp/Features/Research/ES80CaptureShellView.swift') + load('NembraUITests/ES80ResearchCaptureUITests.swift')
for needle in [
    '.makeResearchAuthorizedES80ForCurrentApplication()',
    'ES80ExperimentOneFieldNoGoView()',
    'guard status.physicalProcedurePermitted else',
    'Synthetic Simulator QA presentation only',
    'es80.capture.scroll',
]:
    if needle not in combined: raise SystemExit(f'missing truth marker: {needle}')
controller = load('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
if 'writeValue(' in controller: raise SystemExit('unexpected characteristic-value write path')
print(f'portrait isolation inserted in {inserted} MainActor UI tests')
print('converged Capture acceptance transform: PASS')
