#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_shell_visual_matrix.sh").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-shell-visual-matrix.yml").read_text(encoding="utf-8")
entrypoint = (root / "NembraApp/App/NembraCaptureEntrypoint.swift").read_text(encoding="utf-8")
fixture = (root / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSimulatorQAFixture.swift").read_text(encoding="utf-8")

required_script_markers = [
    "git archive --format=tar HEAD",
    'QA_ENTRYPOINT="$QA_WORK_DIR/$ENTRYPOINT_REL"',
    'needle = "@main @MainActor\\nstruct NembraCaptureApp: App {"',
    "NEMBRA_CAPTURE_SHELL_QA_SCENARIO",
    "PassiveBluetoothExperimentOneSimulatorQAFixture.snapshot(for: scenario)",
    "precondition(snapshot.physicalProcedurePermitted == false)",
    "precondition(snapshot.mayUseBluetoothTransport == false)",
    "PassiveBluetoothExperimentOneCoordinator()",
    "temporaryQARunnerSourceMutation",
    '"shippingSourceMutation": False',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
    '"bluetoothTransportUsed": False',
    '"visualAcceptanceRequiresHumanReview": True',
    'capture_one "$scenario" standard large',
    'capture_one "$scenario" accessibility-xxxl accessibility-extra-extra-extra-large',
]
for marker in required_script_markers:
    assert marker in script, marker

scenarios = [
    "stationaryPreflight",
    "targetConfirmation",
    "passiveDiscovery",
    "captureInProgress",
    "observationHorizonReady",
    "horizonSealed",
    "captureComplete",
    "shareRetry",
    "foregroundInterrupted",
]
for scenario in scenarios:
    assert f"  {scenario}\n" in script, scenario

assert "NEMBRA_CAPTURE_SHELL_QA_SCENARIO" not in entrypoint
assert "PassiveBluetoothExperimentOneSimulatorQAFixture" not in entrypoint
assert "#if DEBUG && targetEnvironment(simulator)" in fixture
assert "physicalProcedurePermitted: false" in fixture
assert "mayUseBluetoothTransport: false" in fixture
assert "never constructs the live" in fixture

required_workflow_markers = [
    "github.event.pull_request.head.repo.full_name == github.repository",
    "github.event.pull_request.draft == false",
    "runs-on: xcode-27",
    "Prove shell-matrix QA isolation",
    "Exact iPhone 12 Capture shell matrix",
    "shippingEntrypointFixtureInjectionAbsent",
    "fixturePhysicalProcedurePermitted",
    "visualAcceptanceRequiresHumanReview",
]
for marker in required_workflow_markers:
    assert marker in workflow, marker

print("Capture shell visual-matrix source contract: PASS")
