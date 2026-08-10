#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[3]
entry = (root / "NembraApp/App/NembraCaptureEntrypoint.swift").read_text(encoding="utf-8")
harness = (root / "scripts/ci/capture_guided_visual_matrix.sh").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-guided-visual-matrix.yml").read_text(encoding="utf-8")

required_entry = [
    '#if targetEnvironment(simulator)\nprivate enum CaptureGuidedVisualState: String, CaseIterable',
    'NEMBRA_CAPTURE_GUIDED_VISUAL_STATE',
    'init(guidedVisualState: CaptureGuidedVisualState)',
    'private var guidedVisualState: CaptureGuidedVisualState?',
    'var isGuidedVisualFixture: Bool',
    'private func applyGuidedVisualState(_ state: CaptureGuidedVisualState)',
    'guard !test.isGuidedVisualFixture else { return }',
    '.allowsHitTesting(!test.isGuidedVisualFixture)',
]
for needle in required_entry:
    assert needle in entry, f"missing guided visual source contract: {needle}"

# The state router and fixture enum must be compile-time Simulator-only, not merely runtime hidden.
enum_pos = entry.index('private enum CaptureGuidedVisualState: String, CaseIterable')
assert entry.rfind('#if targetEnvironment(simulator)', 0, enum_pos) >= 0
assert entry.index('#endif', enum_pos) > enum_pos
route_pos = entry.index('NEMBRA_CAPTURE_GUIDED_VISUAL_STATE')
assert entry.rfind('#if targetEnvironment(simulator)', 0, route_pos) >= 0

# Presentation fixtures may shape private state, but must never call transport/protocol authority APIs.
fixture_start = entry.index('private func applyGuidedVisualState(_ state: CaptureGuidedVisualState)')
fixture_end = entry.index('\n#endif', fixture_start)
fixture = entry[fixture_start:fixture_end]
for forbidden in [
    'scanForPeripherals',
    'connectBLE',
    'publishDps',
    'queryDps',
    'writeValue',
    'beginCorrelationSeries(',
    'OfficialTuyaFactory.acquirePackageCorrelationLease',
    'sessionLedger.beginConnection',
    'sessionLedger.record',
]:
    assert forbidden not in fixture, f"guided visual fixture minted authority: {forbidden}"

states = [
    'correlation-off1',
    'correlated-confirm',
    'secure-link',
    'authenticating',
    'observing',
    'failed-recovery',
    'accepted',
]
for state in states:
    assert state in entry, f"missing app fixture state: {state}"
    assert state in harness, f"missing harness fixture state: {state}"

for needle in [
    'EXPECTED_DEVICE_NAME="iPhone 12"',
    'EXPECTED_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-12"',
    'content_size accessibility-extra-extra-extra-large',
    'SIMCTL_CHILD_NEMBRA_CAPTURE_GUIDED_VISUAL_STATE',
    'visualAcceptanceRequiresHumanReview',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
    '"fixtureAuthorityCreated": False',
]:
    assert needle in harness, f"missing harness safety/evidence contract: {needle}"

assert 'runs-on: xcode-27' in workflow
assert "scripts/ci/tests/test_capture_guided_visual_matrix.py" in workflow
assert "capture_guided_visual_matrix.sh" in workflow
assert "CODE_SIGNING_ALLOWED=NO" in workflow
assert 'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=""' in workflow
print("guided Capture visual matrix source contract: PASS")
