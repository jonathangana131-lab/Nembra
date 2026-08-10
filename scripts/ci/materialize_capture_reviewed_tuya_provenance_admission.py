#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts" / "field" / "install_one_time_capture.command"
BOOTSTRAP = ROOT / "Scripts" / "bootstrap_capture_tuya_sdk.sh"
TEST = ROOT / "scripts" / "ci" / "tests" / "test_capture_tuya_reviewed_provenance_admission.py"

INSTALLER_OLD = '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\n'
INSTALLER_NEW = '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh" --verify-existing-provenance\n'

BOOTSTRAP_INSERT_AFTER = 'cd "$REPO_ROOT"\n\n'
BOOTSTRAP_MODE_BLOCK = '''# Snapshotting private Tuya inputs is a preparation/review operation. The field\n# installer uses --verify-existing-provenance so a build can only consume a\n# previously preserved fingerprint set and cannot silently approve its own\n# current private inputs.\nPROVENANCE_MODE="snapshot"\ncase "${1:-}" in\n  "")\n    ;;\n  --verify-existing-provenance)\n    PROVENANCE_MODE="verify"\n    ;;\n  *)\n    echo "ERROR: unsupported Capture Tuya bootstrap argument: ${1}" >&2\n    exit 16\n    ;;\nesac\n\n'''

BOOTSTRAP_OLD_SNAPSHOT = '''# Snapshot every ignored input that can materially change the private field\n# build. The helper writes only SHA-256 fingerprints + public reviewed versions;\n# it never serializes credentials, SDK bytes, or device identifiers.\nif ! /usr/bin/python3 "$PROVENANCE_HELPER" snapshot \\\n  --lockfile "$REPO_ROOT/Podfile.lock" \\\n  --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \\\n  --security-build "$TUYA_PRIVATE_SDK/Build" \\\n  --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \\\n  --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \\\n  --record "$DEPENDENCY_PROVENANCE"\nthen\n  echo "ERROR: exact private Tuya build-input provenance could not be snapshotted." >&2\n  exit 12\nfi\n'''

BOOTSTRAP_NEW_ADMISSION = '''# Snapshot every ignored input that can materially change the private field\n# build only during explicit preparation. A physical field build must verify an\n# already-preserved record so the build invocation cannot mint its own review\n# authority from whatever private bytes happen to be present at that moment.\nPROVENANCE_ARGUMENTS=(\n  --lockfile "$REPO_ROOT/Podfile.lock"\n  --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec"\n  --security-build "$TUYA_PRIVATE_SDK/Build"\n  --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec"\n  --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig"\n  --record "$DEPENDENCY_PROVENANCE"\n)\nif [[ "$PROVENANCE_MODE" == "verify" ]]; then\n  [[ -f "$DEPENDENCY_PROVENANCE" ]] || {\n    echo "ERROR: no preserved private Tuya provenance record exists. Prepare and review the private workspace before attempting a field build; the installer will not create its own admission record." >&2\n    exit 12\n  }\n  if ! /usr/bin/python3 "$PROVENANCE_HELPER" verify "${PROVENANCE_ARGUMENTS[@]}"\n  then\n    echo "ERROR: current private Tuya inputs do not match the preserved reviewed provenance record. Stop and review a new field-build candidate instead of refreshing admission during install." >&2\n    exit 12\n  fi\nelse\n  if ! /usr/bin/python3 "$PROVENANCE_HELPER" snapshot "${PROVENANCE_ARGUMENTS[@]}"\n  then\n    echo "ERROR: exact private Tuya build-input provenance could not be snapshotted for review." >&2\n    exit 12\n  fi\nfi\n'''

TEST_CONTENT = r'''#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = (ROOT / "scripts" / "field" / "install_one_time_capture.command").read_text(encoding="utf-8")
BOOTSTRAP = (ROOT / "Scripts" / "bootstrap_capture_tuya_sdk.sh").read_text(encoding="utf-8")


class CaptureTuyaReviewedProvenanceAdmissionTests(unittest.TestCase):
    def test_field_installer_can_only_verify_preexisting_private_provenance(self) -> None:
        invocation = '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh" --verify-existing-provenance'
        self.assertIn(invocation, INSTALLER)
        self.assertNotIn('"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\n', INSTALLER)

    def test_bootstrap_separates_preparation_snapshot_from_field_verification(self) -> None:
        self.assertIn('PROVENANCE_MODE="snapshot"', BOOTSTRAP)
        self.assertIn('--verify-existing-provenance)', BOOTSTRAP)
        self.assertIn('PROVENANCE_MODE="verify"', BOOTSTRAP)
        self.assertIn('if [[ "$PROVENANCE_MODE" == "verify" ]]; then', BOOTSTRAP)
        self.assertIn('"$PROVENANCE_HELPER" verify "${PROVENANCE_ARGUMENTS[@]}"', BOOTSTRAP)
        self.assertIn('"$PROVENANCE_HELPER" snapshot "${PROVENANCE_ARGUMENTS[@]}"', BOOTSTRAP)

    def test_field_verification_fails_when_preserved_record_is_missing_or_drifted(self) -> None:
        start = BOOTSTRAP.index('if [[ "$PROVENANCE_MODE" == "verify" ]]; then')
        end = BOOTSTRAP.index('\nelse\n', start)
        verify_branch = BOOTSTRAP[start:end]
        self.assertIn('[[ -f "$DEPENDENCY_PROVENANCE" ]]', verify_branch)
        self.assertIn('will not create its own admission record', verify_branch)
        self.assertIn('"$PROVENANCE_HELPER" verify', verify_branch)
        self.assertNotIn('"$PROVENANCE_HELPER" snapshot', verify_branch)
        self.assertIn('do not match the preserved reviewed provenance record', verify_branch)

    def test_snapshot_remains_available_only_as_explicit_preparation_behavior(self) -> None:
        start = BOOTSTRAP.index('if [[ "$PROVENANCE_MODE" == "verify" ]]; then')
        else_index = BOOTSTRAP.index('\nelse\n', start)
        end = BOOTSTRAP.index('\nfi\n', else_index) + len('\nfi\n')
        admission = BOOTSTRAP[start:end]
        snapshot_branch = admission[admission.index('\nelse\n') + len('\nelse\n'):]
        self.assertIn('"$PROVENANCE_HELPER" snapshot', snapshot_branch)
        self.assertNotIn('"$PROVENANCE_HELPER" verify', snapshot_branch)


if __name__ == "__main__":
    unittest.main()
'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one source match, found {count}")
    return text.replace(old, new, 1)


def desired() -> tuple[str, str]:
    installer = INSTALLER.read_text(encoding="utf-8")
    bootstrap = BOOTSTRAP.read_text(encoding="utf-8")

    if INSTALLER_NEW not in installer:
        installer = replace_once(installer, INSTALLER_OLD, INSTALLER_NEW, "installer bootstrap invocation")

    if BOOTSTRAP_MODE_BLOCK not in bootstrap:
        bootstrap = replace_once(
            bootstrap,
            BOOTSTRAP_INSERT_AFTER,
            BOOTSTRAP_INSERT_AFTER + BOOTSTRAP_MODE_BLOCK,
            "bootstrap provenance mode insertion",
        )

    if BOOTSTRAP_NEW_ADMISSION not in bootstrap:
        bootstrap = replace_once(
            bootstrap,
            BOOTSTRAP_OLD_SNAPSHOT,
            BOOTSTRAP_NEW_ADMISSION,
            "bootstrap provenance admission block",
        )

    return installer, bootstrap


def verify() -> None:
    installer, bootstrap = desired()
    if INSTALLER.read_text(encoding="utf-8") != installer:
        raise RuntimeError("installer does not match reviewed-provenance admission result")
    if BOOTSTRAP.read_text(encoding="utf-8") != bootstrap:
        raise RuntimeError("bootstrap does not match reviewed-provenance admission result")
    if not TEST.exists() or TEST.read_text(encoding="utf-8") != TEST_CONTENT:
        raise RuntimeError("reviewed-provenance admission regression is missing or stale")


def apply() -> None:
    installer, bootstrap = desired()
    INSTALLER.write_text(installer, encoding="utf-8")
    BOOTSTRAP.write_text(bootstrap, encoding="utf-8")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")
    verify()


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    if mode == "apply":
        apply()
    elif mode == "verify":
        verify()
    else:
        raise SystemExit("usage: materialize_capture_reviewed_tuya_provenance_admission.py {apply|verify}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
