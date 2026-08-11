#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_signed_app_install_custody.py"
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
WORKFLOW = REPOSITORY / ".github/workflows/capture-signed-app-install-custody.yml"
PRE_STAGE_ORIGIN_DIAGNOSTIC = REPOSITORY / "scripts/ci/tests/test_capture_signed_app_pre_stage_origin.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("capture_signed_app_install_custody", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-app install custody helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureSignedAppInstallCustodyTests(unittest.TestCase):
    def test_fingerprint_changes_with_bundle_bytes(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-install-custody-") as temporary:
            app = Path(temporary) / "Nembra Capture.app"
            app.mkdir()
            payload = app / "subject.txt"
            payload.write_text("accepted\n", encoding="utf-8")
            first = helper.fingerprint(app)
            payload.write_text("substituted\n", encoding="utf-8")
            second = helper.fingerprint(app)
            self.assertNotEqual(first, second)

    def test_fingerprint_rejects_external_symlink(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-install-custody-") as temporary:
            root = Path(temporary)
            app = root / "Nembra Capture.app"
            app.mkdir()
            outside = root / "outside.txt"
            outside.write_text("mutable\n", encoding="utf-8")
            (app / "escape").symlink_to(outside)
            with self.assertRaises(helper.CustodyError):
                helper.fingerprint(app)

    def test_permanent_workflow_reproves_acl_strip_on_real_macos(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("macos-acl-strip-custody:", workflow)
        self.assertIn("runs-on: macos-15", workflow)
        self.assertIn("ref: ${{ github.event.pull_request.head.sha || github.sha }}", workflow)
        self.assertIn('/bin/chmod +a "$(id -un) allow write,delete,add_file,add_subdirectory,file_inherit,directory_inherit" "$source_app"', workflow)
        self.assertIn('/usr/bin/ditto --noacl "$source_app" "$stage_root/Nembra Capture.app"', workflow)
        self.assertIn('/usr/bin/find "$stage_root" -acl -print -quit', workflow)
        self.assertIn('test -z "$staged_acl"', workflow)

    def test_installer_moves_authority_to_protected_stage_before_codesign(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        app_marker = 'APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"'
        fingerprint_marker = '/usr/bin/python3 -I - fingerprint --app "$APP"'
        stage_marker = '/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX'
        copy_marker = '/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"'
        acl_marker = '/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE_ROOT" -acl -print -quit'
        owner_marker = '/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE_ROOT" -exec /usr/sbin/chown -h root:wheel {} +'
        verify_stage_marker = '/usr/bin/python3 -I - verify-stage'
        revoke_marker = '/usr/bin/sudo -K'
        no_sudo_marker = '/usr/bin/sudo -n /usr/bin/true'
        switch_marker = 'APP="$APP_INSTALL_STAGE"'
        codesign_marker = '/usr/bin/codesign --verify --deep --strict "$APP"'
        install_marker = 'xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"'

        indexes = {}
        for name, marker in (
            ("app", app_marker),
            ("fingerprint", fingerprint_marker),
            ("stage", stage_marker),
            ("copy", copy_marker),
            ("acl", acl_marker),
            ("owner", owner_marker),
            ("verify_stage", verify_stage_marker),
            ("revoke", revoke_marker),
            ("no_sudo", no_sudo_marker),
            ("switch", switch_marker),
            ("codesign", codesign_marker),
            ("install", install_marker),
        ):
            indexes[name] = source.find(marker)
            self.assertGreaterEqual(indexes[name], 0, f"installer is missing {name} custody marker")

        blob_marker = source.find('/usr/bin/git cat-file blob "$SIGNED_APP_CUSTODY_HELPER_BLOB"')
        decode_marker = source.find('/usr/bin/base64 -D')
        hash_marker = source.find('/usr/bin/git hash-object --stdin')
        self.assertGreaterEqual(blob_marker, 0)
        self.assertGreaterEqual(decode_marker, 0)
        self.assertGreaterEqual(hash_marker, 0)
        self.assertIn(
            'SIGNED_APP_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse',
            source,
        )
        self.assertIn(
            'SIGNED_APP_CUSTODY_HELPER_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file blob',
            source,
        )
        self.assertNotIn('SIGNED_APP_CUSTODY_HELPER_BLOB="$(/usr/bin/git rev-parse', source)
        self.assertNotIn('SIGNED_APP_CUSTODY_HELPER_BASE64="$(/usr/bin/git cat-file blob', source)
        self.assertLess(blob_marker, indexes["fingerprint"])
        self.assertLess(decode_marker, indexes["fingerprint"])
        self.assertLess(hash_marker, indexes["fingerprint"])
        self.assertNotIn('/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"', source)
        self.assertNotIn('SIGNED_APP_CUSTODY_HELPER_SOURCE=', source)
        self.assertIn('SIGNED_APP_CUSTODY_HELPER_BASE64=', source)
        self.assertIn("/usr/bin/base64 -D | /usr/bin/python3 -I - fingerprint", source)
        self.assertIn("/usr/bin/base64 -D | /usr/bin/python3 -I - verify-stage", source)
        self.assertIn('Protected signed-app install stage retained an ACL', source)

        self.assertLess(indexes["app"], indexes["fingerprint"])
        self.assertLess(indexes["fingerprint"], indexes["stage"])
        self.assertLess(indexes["stage"], indexes["copy"])
        self.assertLess(indexes["copy"], indexes["acl"])
        self.assertLess(indexes["acl"], indexes["owner"])
        self.assertLess(indexes["owner"], indexes["verify_stage"])
        self.assertLess(indexes["verify_stage"], indexes["revoke"])
        self.assertLess(indexes["revoke"], indexes["no_sudo"])
        self.assertLess(indexes["no_sudo"], indexes["switch"])
        self.assertLess(indexes["switch"], indexes["codesign"])
        self.assertLess(indexes["codesign"], indexes["install"])
        self.assertIn('[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]]', source)
        self.assertIn('APP_INSTALL_STAGE_ROOT=""', source)
        self.assertIn('cleanup_install_subject()', source)
        self.assertNotIn('/usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
        self.assertIn('/usr/bin/sudo -n /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
        self.assertIn('Noninteractive sudo authority remained after invalidation', source)

    def test_build_produced_app_origin_survives_into_protected_stage(self) -> None:
        self.assertTrue(PRE_STAGE_ORIGIN_DIAGNOSTIC.is_file(), "expected-red pre-stage origin diagnostic is missing")
        result = subprocess.run(
            [sys.executable, "-B", "-I", str(PRE_STAGE_ORIGIN_DIAGNOSTIC)],
            cwd=REPOSITORY,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            "post-build/pre-fingerprint substitution became the protected signed-app subject; "
            "the source->stage fingerprint is self-derived after the mutable compiler-output window.\n"
            + result.stdout,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
