from pathlib import Path


def load(path): return Path(path).read_text(encoding='utf-8')
def save(path, text): Path(path).write_text(text, encoding='utf-8')
def one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)

# Capture shell: compact-height rhythm + named real scroll surface.
p = 'NembraApp/Features/Research/ES80CaptureShellView.swift'
s = load(p)
s = one(s,
    '    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.accessibilityReduceTransparency) private var accessibilityReduceTransparency\n',
    '    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.verticalSizeClass) private var verticalSizeClass\n    @Environment(\\.accessibilityReduceTransparency) private var accessibilityReduceTransparency\n', 'shell size class')
s = one(s,
    '            ScrollView {\n                VStack(alignment: .leading, spacing: 24) {\n',
    '            ScrollView {\n                VStack(alignment: .leading, spacing: captureVerticalSpacing) {\n', 'shell spacing')
s = one(s,
    '                .frame(maxWidth: 660)\n                .padding(.horizontal, 22)\n                .padding(.top, 18)\n                .padding(.bottom, 42)\n                .frame(maxWidth: .infinity)\n            }\n            .background(Color.black.ignoresSafeArea())\n',
    '                .frame(maxWidth: 660)\n                .padding(.horizontal, 22)\n                .padding(.top, captureTopPadding)\n                .padding(.bottom, captureBottomPadding)\n                .frame(maxWidth: .infinity)\n            }\n            .accessibilityIdentifier("es80.capture.scroll")\n            .background(Color.black.ignoresSafeArea())\n', 'shell root')
s = one(s,
    '    private func hero(for phase: Phase) -> some View {\n',
    '    private var captureVerticalSpacing: CGFloat { verticalSizeClass == .compact ? 16 : 24 }\n\n    private var captureTopPadding: CGFloat { verticalSizeClass == .compact ? 10 : 18 }\n\n    private var captureBottomPadding: CGFloat { verticalSizeClass == .compact ? 20 : 42 }\n\n    private func hero(for phase: Phase) -> some View {\n', 'shell compact metrics')
save(p, s)

# Locked NO-GO surface only: compact vertical chrome without changing authority/copy.
p = 'NembraApp/App/NembraApp.swift'
a = load(p)
marker = '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n'
pos = a.find(marker)
if pos < 0: raise SystemExit('NO-GO marker missing')
pre, n = a[:pos], a[pos:]
n = one(n,
    '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n    @State private var engineeringDetailsExpanded = false\n',
    '@MainActor\nprivate struct ES80ExperimentOneFieldNoGoView: View {\n    @Environment(\\.verticalSizeClass) private var verticalSizeClass\n    @State private var engineeringDetailsExpanded = false\n', 'NO-GO size class')
n = one(n,
    '        ScrollView {\n            VStack(alignment: .leading, spacing: 28) {\n                VStack(alignment: .leading, spacing: 14) {\n',
    '        ScrollView {\n            VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 16 : 28) {\n                VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 9 : 14) {\n', 'NO-GO rhythm')
old = '                .padding(18)\n'
new = '                .padding(verticalSizeClass == .compact ? 12 : 18)\n'
for label in ('physical lock card', 'engineering card'):
    at = n.find(old)
    if at < 0: raise SystemExit(f'{label}: padding missing')
    n = n[:at] + new + n[at + len(old):]
n = one(n,
    '            .frame(maxWidth: 660)\n            .padding(.horizontal, 22)\n            .padding(.top, 18)\n            .padding(.bottom, 42)\n            .frame(maxWidth: .infinity)\n        }\n        .background(Color.black.ignoresSafeArea())\n',
    '            .frame(maxWidth: 660)\n            .padding(.horizontal, 22)\n            .padding(.top, verticalSizeClass == .compact ? 8 : 18)\n            .padding(.bottom, verticalSizeClass == .compact ? 20 : 42)\n            .frame(maxWidth: .infinity)\n        }\n        .accessibilityIdentifier("es80.capture.field-no-go-scroll")\n        .background(Color.black.ignoresSafeArea())\n', 'NO-GO root')
save(p, pre + n)

# Acceptance harness: swipe the real Capture ScrollView, not the application shell.
p = 'NembraUITests/ES80ResearchCaptureUITests.swift'
u = load(p)
u = one(u,
    '            app.swipeUp()\n            remaining -= 1\n',
    '            let captureScroll = app.scrollViews["es80.capture.scroll"]\n            if captureScroll.exists {\n                captureScroll.swipeUp()\n            } else {\n                app.swipeUp()\n            }\n            remaining -= 1\n', 'real Capture scroll target')
save(p, u)

# Preserve current live safety improvements and truth boundaries.
app = load('NembraApp/App/NembraApp.swift')
shell = load('NembraApp/Features/Research/ES80CaptureShellView.swift')
ui = load('NembraUITests/ES80ResearchCaptureUITests.swift')
for needle in (
    'fieldBuildRendezvous(researchBuild)',
    'hasAcceptedPreflightAuthority',
    '.makeResearchAuthorizedES80ForCurrentApplication()',
    'guard status.physicalProcedurePermitted else',
    'Synthetic Simulator QA presentation only',
    'es80.capture.scroll',
    'captureScroll.swipeUp()',
):
    if needle not in app + shell + ui:
        raise SystemExit(f'missing preserved contract: {needle}')
controller = load('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
if 'writeValue(' in controller:
    raise SystemExit('unexpected application characteristic-value write path')
print('retained landscape acceptance repair: PASS')
