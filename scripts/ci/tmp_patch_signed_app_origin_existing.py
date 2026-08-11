#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
INSTALL_BLOCK = ROOT / "scripts/ci/tmp_signed_app_origin_installer_block.txt"
INSTALL_HELPER = ROOT / "scripts/ci/capture_signed_app_install_custody.py"
INSTALL_TEST = ROOT / "scripts/ci/tests/test_capture_signed_app_install_custody.py"
INSTALL_WORKFLOW = ROOT / ".github/workflows/capture-signed-app-install-custody.yml"
FIELD_WORKFLOW = ROOT / ".github/workflows/capture-field-build-provenance.yml"


def require_once(text: str, needle: str, label: str) -> None:
    count = text.count(needle)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    require_once(text, old, label)
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    require_once(text, start, f"{label} start")
    require_once(text, end, f"{label} end")
    start_index = text.index(start)
    end_index = text.index(end, start_index)
    return text[:start_index] + replacement + text[end_index:]


def patch_installer() -> None:
    source = INSTALLER.read_text(encoding="utf-8")
    start = 'DERIVED="${TMPDIR:-/tmp}/NembraAuthenticatedCaptureDerived"'
    end = 'APP_INFO_PLIST="$APP/Info.plist"'
    vulnerable = source[source.index(start):source.index(end)]
    for marker in (
        'APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"',
        "SOURCE_APP_TREE_SHA256=",
        '/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"',
        "/usr/bin/sudo -K",
    ):
        if marker not in vulnerable:
            raise RuntimeError(f"legacy origin seam marker disappeared before patch: {marker}")

    block = INSTALL_BLOCK.read_text(encoding="utf-8").rstrip() + "\n\n"
    source = replace_between(source, start, end, block, "installer build-origin handoff")
    old_unset = (
        "unset SOURCE_APP_TREE_SHA256 STAGED_APP_TREE_SHA256 "
        "SIGNED_APP_CUSTODY_HELPER_PATH SIGNED_APP_CUSTODY_HELPER_BLOB "
        "SIGNED_APP_CUSTODY_HELPER_BASE64 APP_INSTALL_STAGE"
    )
    new_unset = (
        "unset STAGED_APP_TREE_SHA256 SIGNED_APP_CUSTODY_HELPER_PATH "
        "SIGNED_APP_CUSTODY_HELPER_BLOB SIGNED_APP_CUSTODY_HELPER_BASE64 "
        "BUILD_ORIGIN_CUSTODY_HELPER_PATH BUILD_ORIGIN_CUSTODY_HELPER_BLOB "
        "BUILD_ORIGIN_CUSTODY_HELPER_BASE64 APP_INSTALL_STAGE"
    )
    source = replace_once(source, old_unset, new_unset, "installer final custody cleanup")

    for forbidden in (
        'APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"',
        "SOURCE_APP_TREE_SHA256=",
        '/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"',
    ):
        if forbidden in source:
            raise RuntimeError(f"legacy mutable-origin authority survived installer patch: {forbidden}")
    INSTALLER.write_text(source, encoding="utf-8")


def patch_install_helper_truth() -> None:
    source = INSTALL_HELPER.read_text(encoding="utf-8")
    old = (
        '"""Bind the exact signed Capture.app bytes consumed by the physical install side effect.\n\n'
        'The normal build output lives in a user-writable DerivedData tree. The field installer snapshots\n'
        'that app, copies it through root into a root-owned staging directory, then runs every provenance,\n'
        'signature, entitlement, and provisioning-profile check against the protected staging copy. This\n'
        'helper fingerprints the finite bundle and proves the staged path cannot be replaced or modified by\n'
        'the invoking non-root user before devicectl consumes it.\n"""'
    )
    new = (
        '"""Bind the exact signed Capture.app bytes consumed by the physical install side effect.\n\n'
        'The field installer admits xcodebuild output only through the root-supervised build-origin handoff.\n'
        'That supervisor locks its isolated DerivedData root, snapshots the exact bundle into a root-owned\n'
        'staging directory, and returns only that protected stage. This helper fingerprints the finite bundle\n'
        'and proves the staged path cannot be replaced or modified by the invoking non-root user before\n'
        'devicectl consumes it.\n"""'
    )
    source = replace_once(source, old, new, "install-custody truth doc")
    INSTALL_HELPER.write_text(source, encoding="utf-8")


def patch_install_test() -> None:
    source = INSTALL_TEST.read_text(encoding="utf-8")
    start = "    def test_installer_moves_authority_to_protected_stage_before_codesign(self) -> None:\n"
    end = "\n\nif __name__ == \"__main__\":"
    method = '''    def test_installer_moves_authority_to_protected_stage_before_codesign(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        markers = {
            "origin_helper": 'BUILD_ORIGIN_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1',
            "install_helper": 'SIGNED_APP_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1',
            "supervisor": '/usr/bin/sudo /usr/bin/python3 -I -c',
            "derived": '-derivedDataPath "$DERIVED_PLACEHOLDER"',
            "result": 'APP_INSTALL_STAGE_ROOT="${BUILD_ORIGIN_CUSTODY_RESULT%%',
            "switch": 'APP="$APP_INSTALL_STAGE"',
            "verify_stage": '/usr/bin/python3 -I - verify-stage',
            "no_sudo": '/usr/bin/sudo -n /usr/bin/true',
            "codesign": '/usr/bin/codesign --verify --deep --strict "$APP"',
            "install": 'xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"',
        }
        indexes = {}
        for name, marker in markers.items():
            indexes[name] = source.find(marker)
            self.assertGreaterEqual(indexes[name], 0, f"installer is missing {name} custody marker")

        self.assertLess(indexes["origin_helper"], indexes["supervisor"])
        self.assertLess(indexes["install_helper"], indexes["supervisor"])
        self.assertLess(indexes["supervisor"], indexes["result"])
        self.assertLess(indexes["result"], indexes["switch"])
        self.assertLess(indexes["switch"], indexes["no_sudo"])
        self.assertLess(indexes["no_sudo"], indexes["verify_stage"])
        self.assertLess(indexes["verify_stage"], indexes["codesign"])
        self.assertLess(indexes["codesign"], indexes["install"])

        self.assertIn('DERIVED_PLACEHOLDER="__NEMBRA_PROTECTED_DERIVED__"', source)
        self.assertIn('--install-custody-helper-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64"', source)
        self.assertIn('[[ "$VERIFIED_STAGE_TREE_SHA256" == "$STAGED_APP_TREE_SHA256" ]]', source)
        self.assertIn('APP_INSTALL_STAGE_ROOT=""', source)
        self.assertIn('cleanup_install_subject()', source)
        self.assertIn('/usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
        self.assertIn('Noninteractive sudo authority remained after build-origin custody', source)

        self.assertNotIn('APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"', source)
        self.assertNotIn('SOURCE_APP_TREE_SHA256=', source)
        self.assertNotIn('/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"', source)
        self.assertNotIn('/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX', source)
'''
    source = replace_between(source, start, end, method.rstrip() + "\n\n", "install-custody source contract")
    INSTALL_TEST.write_text(source, encoding="utf-8")


def patch_install_workflow() -> None:
    source = INSTALL_WORKFLOW.read_text(encoding="utf-8")
    source = replace_once(
        source,
        "      - scripts/ci/capture_signed_app_install_custody.py\n",
        "      - scripts/ci/capture_signed_app_install_custody.py\n"
        "      - scripts/ci/capture_signed_app_build_origin_custody.py\n"
        "      - scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py\n",
        "install workflow origin paths",
    )
    source = replace_once(
        source,
        "            scripts/ci/capture_signed_app_install_custody.py \\\n"
        "            scripts/ci/tests/test_capture_signed_app_install_custody.py \\\n",
        "            scripts/ci/capture_signed_app_install_custody.py \\\n"
        "            scripts/ci/capture_signed_app_build_origin_custody.py \\\n"
        "            scripts/ci/tests/test_capture_signed_app_install_custody.py \\\n"
        "            scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py \\\n",
        "install workflow portable compile",
    )
    source = replace_once(
        source,
        "          /usr/bin/python3 -B -I scripts/ci/tests/test_capture_signed_app_install_custody.py\n",
        "          /usr/bin/python3 -B -I scripts/ci/tests/test_capture_signed_app_install_custody.py\n"
        "          /usr/bin/python3 -B -I scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py\n",
        "install workflow portable origin regression",
    )
    macos_job = '''  macos-build-origin-isolation:
    name: Prove compiler-output capability isolation on real macOS
    runs-on: macos-15
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}

      - name: Bind build-origin evidence to exact checked-out source
        shell: bash
        env:
          EXPECTED_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
        run: |
          set -euo pipefail
          expected="$(printf '%s' "$EXPECTED_HEAD_SHA" | tr '[:upper:]' '[:lower:]')"
          actual="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
          [[ "$expected" =~ ^[0-9a-f]{40}$ ]]
          test "$actual" = "$expected"
          test -z "$(git status --porcelain=v1 --untracked-files=all)"

      - name: Prove one-run group capability and root lock
        shell: bash
        run: |
          set -euo pipefail
          /usr/bin/python3 -m py_compile \
            scripts/ci/capture_signed_app_build_origin_custody.py \
            scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py
          sudo /usr/bin/python3 -B -I scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py
          test -z "$(git status --porcelain=v1 --untracked-files=all)"

'''
    source = replace_once(
        source,
        "  accepted-runner-transport:\n",
        macos_job + "  accepted-runner-transport:\n",
        "install workflow macOS origin job",
    )
    INSTALL_WORKFLOW.write_text(source, encoding="utf-8")


def patch_field_workflow() -> None:
    source = FIELD_WORKFLOW.read_text(encoding="utf-8")
    source = replace_once(
        source,
        "      - scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py\n",
        "      - scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py\n"
        "      - scripts/ci/capture_signed_app_build_origin_custody.py\n"
        "      - scripts/ci/capture_signed_app_install_custody.py\n"
        "      - scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py\n"
        "      - scripts/ci/tests/test_capture_signed_app_install_custody.py\n",
        "field workflow origin paths",
    )
    source = replace_once(
        source,
        "          bash -n scripts/field/install_one_time_capture.command\n",
        "          /usr/bin/python3 -m py_compile scripts/ci/capture_signed_app_build_origin_custody.py\n"
        "          /usr/bin/python3 -B -I scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py\n"
        "          /usr/bin/python3 -B -I scripts/ci/tests/test_capture_signed_app_install_custody.py\n"
        "          bash -n scripts/field/install_one_time_capture.command\n",
        "field workflow origin tests",
    )
    source = replace_once(
        source,
        "          signed_field_inspector='scripts/ci/es80_signed_field_artifact_evidence.py'\n",
        "          signed_field_inspector='scripts/ci/es80_signed_field_artifact_evidence.py'\n"
        "          build_origin_custody='scripts/ci/capture_signed_app_build_origin_custody.py'\n"
        "          signed_install_custody='scripts/ci/capture_signed_app_install_custody.py'\n",
        "field workflow origin helper variables",
    )
    source = replace_once(
        source,
        "          build_line=\"$(grep -nF -- '-- xcodebuild \\\\' \"$installer\" | sed -n '1s/:.*//p')\"\n",
        "          build_line=\"$(grep -nF -- '-- /usr/bin/xcodebuild \\\\' \"$installer\" | sed -n '1s/:.*//p')\"\n",
        "field workflow guarded xcodebuild marker",
    )

    stage_start = "          grep -Fq 'cleanup_install_subject()' \"$installer\"\n"
    stage_end = "          grep -Fq 'devicectl device install app --device \"$COREDEVICE_ID\" \"$APP\"' \"$installer\"\n"
    new_stage = '''          grep -Fq 'cleanup_install_subject()' "$installer"
          grep -Fq 'trap cleanup_install_subject EXIT' "$installer"
          grep -Fq 'BUILD_ORIGIN_CUSTODY_HELPER_PATH="scripts/ci/capture_signed_app_build_origin_custody.py"' "$installer"
          grep -Fq 'BUILD_ORIGIN_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse' "$installer"
          grep -Fq 'SIGNED_APP_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse' "$installer"
          grep -Fq 'DERIVED_PLACEHOLDER="__NEMBRA_PROTECTED_DERIVED__"' "$installer"
          grep -Fq '/usr/bin/sudo /usr/bin/python3 -I -c' "$installer"
          grep -Fq -- '--install-custody-helper-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64"' "$installer"
          grep -Fq -- '-derivedDataPath "$DERIVED_PLACEHOLDER"' "$installer"
          grep -Fq 'APP_INSTALL_STAGE_ROOT="${BUILD_ORIGIN_CUSTODY_RESULT%%' "$installer"
          grep -Fq 'STAGED_APP_TREE_SHA256="${BUILD_ORIGIN_CUSTODY_RESULT#*' "$installer"
          grep -Fq 'APP_INSTALL_STAGE="$APP_INSTALL_STAGE_ROOT/Nembra Capture.app"' "$installer"
          grep -Fq 'APP="$APP_INSTALL_STAGE"' "$installer"
          grep -Fq '/usr/bin/python3 -I - verify-stage' "$installer"
          if grep -Fq 'APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"' "$installer"; then
            echo 'ERROR: field installer must never reacquire install authority from mutable DerivedData after xcodebuild.' >&2
            exit 1
          fi
          grep -Fq 'def _invalidate_invoker_sudo(' "$build_origin_custody"
          grep -Fq 'os.chmod(derived, 0o770)' "$build_origin_custody"
          grep -Fq 'os.chmod(derived_root, 0o700)' "$build_origin_custody"
          grep -Fq 'stage_root, stage_app = _copy_to_stage(source_app, private_tmp)' "$build_origin_custody"
          grep -Fq 'if staged_fingerprint != source_fingerprint:' "$build_origin_custody"
          grep -Fq 'def verify_stage(' "$signed_install_custody"
          grep -Fq 'INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install-log.XXXXXX")"' "$installer"
          grep -Fq 'chmod 600 "$INSTALL_LOG"' "$installer"
          grep -Fq '/bin/rm -f -- "$INSTALL_LOG" || true' "$installer"
          grep -Fq '/usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"' "$installer"
          grep -Fq 'rm -f -- "$INSTALL_LOG"' "$installer"
          grep -Fq 'INSTALL_LOG=""' "$installer"
          grep -Fq 'APP_INSTALL_STAGE_ROOT=""' "$installer"
'''
    source = replace_between(
        source,
        stage_start,
        stage_end,
        new_stage,
        "field workflow protected-stage contract",
    )
    FIELD_WORKFLOW.write_text(source, encoding="utf-8")


def main() -> None:
    patch_installer()
    patch_install_helper_truth()
    patch_install_test()
    patch_install_workflow()
    patch_field_workflow()


if __name__ == "__main__":
    main()
