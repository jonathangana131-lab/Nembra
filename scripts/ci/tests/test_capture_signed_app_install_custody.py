#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_signed_app_install_custody.py"
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


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

    def test_fingerprint_rejects_hardlinked_regular_file(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-install-custody-") as temporary:
            root = Path(temporary)
            app = root / "Nembra Capture.app"
            app.mkdir()
            payload = app / "subject.txt"
            payload.write_text("accepted\n", encoding="utf-8")
            os.link(payload, root / "same-inode.txt")
            with self.assertRaises(helper.CustodyError):
                helper.fingerprint(app)

    def test_helper_execution_bytes_are_protected_exact_git_subject(self) -> None:
        """Promoted #2741 invariant: checked helper bytes must be the executed bytes."""
        source = INSTALLER.read_text(encoding="utf-8")
        accepted_blob = 'HELPER_ACCEPTED_BLOB="$(git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE"'
        actual_blob = 'HELPER_ACTUAL_BLOB="$(git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"'
        protected_root = 'HELPER_EXECUTION_STAGE_ROOT="$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-capture-install-helper.XXXXXX)"'
        materialize = 'GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob "$HELPER_ACCEPTED_BLOB"'
        protected_subject = 'HELPER_EXECUTION_SUBJECT="$HELPER_EXECUTION_STAGE_ROOT/capture_signed_app_install_custody.py"'
        root_owner = '/usr/bin/sudo /usr/sbin/chown root:wheel "$HELPER_EXECUTION_SUBJECT"'
        read_only = '/usr/bin/sudo /bin/chmod 0444 "$HELPER_EXECUTION_SUBJECT"'
        expose_parent = '/usr/bin/sudo /bin/chmod 0755 "$HELPER_EXECUTION_STAGE_ROOT"'
        staged_blob = 'HELPER_EXECUTION_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git hash-object --no-filters -- "$HELPER_EXECUTION_SUBJECT"'
        equality = '[[ "$HELPER_EXECUTION_BLOB" == "$HELPER_ACCEPTED_BLOB" ]]'
        fingerprint_exec = '/usr/bin/python3 -I -B "$HELPER_EXECUTION_SUBJECT" fingerprint --app "$APP"'
        verify_exec = '/usr/bin/python3 -I -B "$HELPER_EXECUTION_SUBJECT" verify-stage'

        markers = (
            accepted_blob,
            actual_blob,
            protected_root,
            materialize,
            protected_subject,
            root_owner,
            read_only,
            expose_parent,
            staged_blob,
            equality,
            fingerprint_exec,
            verify_exec,
        )
        indexes: dict[str, int] = {}
        for marker in markers:
            index = source.find(marker)
            self.assertGreaterEqual(index, 0, f"installer is missing helper execution-custody marker: {marker}")
            indexes[marker] = index

        self.assertLess(indexes[actual_blob], indexes[protected_root])
        self.assertLess(indexes[protected_root], indexes[materialize])
        self.assertLess(indexes[materialize], indexes[root_owner])
        self.assertLess(indexes[root_owner], indexes[read_only])
        self.assertLess(indexes[read_only], indexes[expose_parent])
        self.assertLess(indexes[expose_parent], indexes[staged_blob])
        self.assertLess(indexes[staged_blob], indexes[equality])
        self.assertLess(indexes[equality], indexes[fingerprint_exec])
        self.assertLess(indexes[fingerprint_exec], indexes[verify_exec])

        mutable_exec = '/usr/bin/python3 -I "$ROOT/scripts/ci/capture_signed_app_install_custody.py"'
        self.assertNotIn(
            mutable_exec,
            source,
            "accepted helper authority must never reopen the user-writable checkout pathname",
        )
        self.assertIn('cleanup_helper_execution_subject()', source)
        self.assertIn('/usr/bin/sudo /bin/rm -rf -- "$HELPER_EXECUTION_STAGE_ROOT"', source)
        self.assertGreaterEqual(source.count('"$HELPER_EXECUTION_SUBJECT"'), 10)

    def test_installer_moves_authority_to_protected_stage_before_codesign(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        app_marker = 'APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"'
        helper_stage_marker = 'HELPER_EXECUTION_STAGE_ROOT="$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-capture-install-helper.XXXXXX)"'
        fingerprint_marker = '"$HELPER_EXECUTION_SUBJECT" fingerprint --app "$APP"'
        stage_marker = '/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX'
        copy_marker = '/usr/bin/sudo /usr/bin/ditto "$APP" "$APP_INSTALL_STAGE"'
        owner_marker = '/usr/bin/sudo /usr/bin/find "$APP_INSTALL_STAGE_ROOT" -exec /usr/sbin/chown -h root:wheel {} +'
        verify_stage_marker = '"$HELPER_EXECUTION_SUBJECT" verify-stage'
        switch_marker = 'APP="$APP_INSTALL_STAGE"'
        codesign_marker = '/usr/bin/codesign --verify --deep --strict "$APP"'
        install_marker = 'xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"'

        indexes = {}
        for name, marker in (
            ("app", app_marker),
            ("helper_stage", helper_stage_marker),
            ("fingerprint", fingerprint_marker),
            ("stage", stage_marker),
            ("copy", copy_marker),
            ("owner", owner_marker),
            ("verify_stage", verify_stage_marker),
            ("switch", switch_marker),
            ("codesign", codesign_marker),
            ("install", install_marker),
        ):
            indexes[name] = source.find(marker)
            self.assertGreaterEqual(indexes[name], 0, f"installer is missing {name} custody marker")

        self.assertLess(indexes["app"], indexes["helper_stage"])
        self.assertLess(indexes["helper_stage"], indexes["fingerprint"])
        self.assertLess(indexes["fingerprint"], indexes["stage"])
        self.assertLess(indexes["stage"], indexes["copy"])
        self.assertLess(indexes["copy"], indexes["owner"])
        self.assertLess(indexes["owner"], indexes["verify_stage"])
        self.assertLess(indexes["verify_stage"], indexes["switch"])
        self.assertLess(indexes["switch"], indexes["codesign"])
        self.assertLess(indexes["codesign"], indexes["install"])
        self.assertIn('git ls-files -v -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)
        self.assertIn('git ls-files -t -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)
        self.assertIn('git rev-parse "HEAD:$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)
        self.assertIn('git hash-object --no-filters -- "$SIGNED_APP_CUSTODY_HELPER_RELATIVE"', source)
        self.assertLess(source.find('HELPER_ACTUAL_BLOB='), indexes["helper_stage"])
        self.assertIn('[[ "$STAGED_APP_TREE_SHA256" == "$SOURCE_APP_TREE_SHA256" ]]', source)
        self.assertIn('APP_INSTALL_STAGE_ROOT=""', source)
        self.assertIn('cleanup_install_subject()', source)
        self.assertIn('/usr/bin/sudo /bin/rm -rf -- "$APP_INSTALL_STAGE_ROOT"', source)
        self.assertIn('cleanup_helper_execution_subject', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
