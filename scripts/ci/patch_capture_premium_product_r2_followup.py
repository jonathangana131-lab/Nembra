from pathlib import Path
import subprocess

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
VISUAL_DONOR = "bc89e4d69d0f385115c21a933db68760be52129b"
RESTART_DONOR = "76d03dababf3eec3dbec9d965f932eb08f1a612b"


def git_show(ref: str, path: str) -> str:
    return subprocess.check_output(["git", "show", f"{ref}:{path}"], text=True)


def copy_from(ref: str, path: str) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(git_show(ref, path))


source = APP.read_text()
source = source.replace(
    "var failedAttemptCanRestartFromOFF1: Bool { phase == .failed && currentConnectionToken == nil }",
    "var canRestartFromFreshOFF1: Bool { phase == .failed && currentConnectionToken == nil }",
    1,
)
source = source.replace("test.failedAttemptCanRestartFromOFF1", "test.canRestartFromFreshOFF1")

old_failure_gate = '''                if test.canRestartFromFreshOFF1 {
                    Text("The previous attempt is fully retired. Fix the blocker above, then begin a fresh OFF1 correlation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        test.startBaseline()
                    } label: {
                        Label("Restart from scooter OFF", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!authorityReady || test.membershipBusy)
                } else {
'''
new_failure_gate = '''                if test.canRestartFromFreshOFF1 && authorityReady {
                    Text("The previous attempt is fully retired. Fix the blocker above, then begin a fresh OFF1 correlation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        test.startBaseline()
                    } label: {
                        Label("Restart from scooter OFF", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(test.membershipBusy)
                } else if test.canRestartFromFreshOFF1 {
                    Label("Preflight authority required", systemImage: "shield.slash")
                        .font(.headline)
                    Text("Restore the account, exact scooter membership, and field-build authority shown above before starting a fresh OFF1 attempt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
'''
if old_failure_gate not in source:
    raise SystemExit("expected first-pass failure gate not found")
source = source.replace(old_failure_gate, new_failure_gate, 1)
APP.write_text(source)

# Canonicalize the consolidated recovery regression onto the stronger lifecycle property.
recovery = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductRecoveryTruthSourceTests.swift")
recovery_text = recovery.read_text().replace("failedAttemptCanRestartFromOFF1", "canRestartFromFreshOFF1")
recovery.write_text(recovery_text)
copy_from(RESTART_DONOR, "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkRestartAuthoritySourceTests.swift")

# Use the current presentation-only harness that explicitly rejects fake public CI
# dependency provenance and inherited Simulator authority.
copy_from(VISUAL_DONOR, "scripts/ci/capture_standalone_visual_evidence.sh")
copy_from(VISUAL_DONOR, "scripts/ci/tests/test_capture_standalone_visual_evidence.py")

visual_workflow = '''name: Capture Standalone Visual Acceptance

on:
  push:
    branches:
      - product/v14-capture-premium-secure-link-current-sol
  workflow_dispatch:

permissions:
  contents: read

jobs:
  standalone-visual:
    name: Real standalone Capture presentation
    runs-on: xcode-27
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v4

      - name: Verify exact visual head
        shell: bash
        run: |
          set -euo pipefail
          actual="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
          requested="$(printf '%s' "$GITHUB_SHA" | tr '[:upper:]' '[:lower:]')"
          test "$actual" = "$requested"
          [[ "$actual" =~ ^[0-9a-f]{40}$ ]]

      - name: Verify presentation-evidence source contract
        shell: bash
        run: |
          set -euo pipefail
          bash -n scripts/ci/capture_standalone_visual_evidence.sh
          /usr/bin/python3 scripts/ci/tests/test_capture_standalone_visual_evidence.py

      - name: Build exact public-unprovisioned standalone Capture app
        shell: bash
        run: |
          set -euo pipefail
          source_sha="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
          label="capture-v14-${source_sha:0:12}"
          rm -rf /tmp/NembraCaptureProvenanceDerived
          xcodebuild \\
            -project NembraCapture.xcodeproj \\
            -scheme 'Nembra Capture' \\
            -configuration Debug \\
            -sdk iphonesimulator \\
            -destination 'generic/platform=iOS Simulator' \\
            -derivedDataPath /tmp/NembraCaptureProvenanceDerived \\
            CODE_SIGNING_ALLOWED=NO \\
            NEMBRA_CAPTURE_BUILD_IDENTIFIER="$label" \\
            NEMBRA_CAPTURE_BUILD_COMMIT_SHA="$source_sha" \\
            NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256= \\
            build

          plist='/tmp/NembraCaptureProvenanceDerived/Build/Products/Debug-iphonesimulator/Nembra Capture.app/Info.plist'
          test -f "$plist"
          test "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" = 'com.jonathangana131.nembra.capturelearn'
          test "$(plutil -extract NembraCaptureBuildIdentifier raw -o - "$plist")" = "$label"
          test "$(plutil -extract NembraCaptureSourceCommitSHA raw -o - "$plist")" = "$source_sha"
          dep="$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist" 2>/dev/null || true)"
          test -z "$dep"

      - name: Launch real standalone app and capture fail-closed presentation
        shell: bash
        env:
          EVIDENCE_PROFILE: public-unprovisioned
          EXPECTED_SOURCE_SHA: ${{ github.sha }}
          ARTIFACTS_DIR: ${{ runner.temp }}/NembraCaptureStandaloneVisualEvidence
        run: |
          set -euo pipefail
          bash scripts/ci/capture_standalone_visual_evidence.sh

      - name: Verify retained presentation-only evidence
        shell: bash
        env:
          ARTIFACTS_DIR: ${{ runner.temp }}/NembraCaptureStandaloneVisualEvidence
        run: |
          set -euo pipefail
          /usr/bin/python3 - "$ARTIFACTS_DIR/NembraCaptureStandaloneVisualEvidence.json" "$GITHUB_SHA" <<'PY'
          import json
          import sys
          from pathlib import Path
          record = json.loads(Path(sys.argv[1]).read_text())
          expected = sys.argv[2].lower()
          assert record["authority"] == "standalone-capture-simulator-presentation-only"
          assert record["evidenceProfile"] == "public-unprovisioned"
          assert record["sourceCommitSHA"] == expected
          assert record["buildIdentifier"] == f"capture-v14-{expected[:12]}"
          assert record["tuyaDependencyLockSHA256"] is None
          assert record["tuyaDependencyProvenanceClass"] == "deliberately-absent-public-ci"
          assert record["expectedFieldBuildAuthority"] is False
          assert record["syntheticAuthorityEnvironmentRejected"] is True
          assert record["physicalAuthorityCreated"] is False
          assert record["protocolAuthorityCreated"] is False
          assert record["visualAcceptanceRequiresHumanReview"] is True
          shot = Path(sys.argv[1]).parent / record["screenshot"]["relativePath"]
          assert shot.is_file() and shot.stat().st_size > 0
          PY

      - name: Upload standalone visual evidence
        uses: actions/upload-artifact@v4
        with:
          name: nembra-capture-standalone-visual-${{ github.sha }}
          path: ${{ runner.temp }}/NembraCaptureStandaloneVisualEvidence
          if-no-files-found: error
          retention-days: 14
'''
Path(".github/workflows/capture-standalone-visual-acceptance.yml").write_text(visual_workflow)

final = APP.read_text()
required = [
    "var canRestartFromFreshOFF1: Bool { phase == .failed && currentConnectionToken == nil }",
    "test.canRestartFromFreshOFF1 && authorityReady",
    'Label("Preflight authority required"',
    'Label("Relaunch Capture"',
]
missing = [item for item in required if item not in final]
if missing:
    raise SystemExit(f"restart hardening missing: {missing}")
if ".disabled(!authorityReady" in final[final.index("private var failurePanel"):final.index("private var completionPanel")]:
    raise SystemExit("failure panel still offers a generically disabled OFF1 restart")
print("restart + public visual hardening: PASS")
