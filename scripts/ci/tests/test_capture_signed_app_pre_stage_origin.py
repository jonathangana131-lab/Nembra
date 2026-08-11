#!/usr/bin/env python3
"""Regress the compiler-output -> protected-stage origin boundary for field Capture."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
ORIGIN_HELPER = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"
INSTALL_HELPER = REPOSITORY / "scripts/ci/capture_signed_app_install_custody.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureSignedAppPreStageOriginTests(unittest.TestCase):
    def test_installer_promotes_only_root_supervisor_stage(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        origin_helper = (
            'BUILD_ORIGIN_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 '
            'GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse'
        )
        install_helper = (
            'SIGNED_APP_CUSTODY_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 '
            'GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git rev-parse'
        )
        markers = {
            "origin_helper": origin_helper,
            "install_helper": install_helper,
            "supervisor": "/usr/bin/sudo /usr/bin/python3 -I -c",
            "derived": '-derivedDataPath "$DERIVED_PLACEHOLDER"',
            "stage_result": 'APP_INSTALL_STAGE_ROOT="${BUILD_ORIGIN_CUSTODY_RESULT%%$\'\\t\'*}"',
            "switch": 'APP="$APP_INSTALL_STAGE"',
            "verify": "/usr/bin/python3 -I - verify-stage",
            "codesign": '/usr/bin/codesign --verify --deep --strict "$APP"',
            "install": 'xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"',
        }
        indexes: dict[str, int] = {}
        for name, marker in markers.items():
            indexes[name] = source.find(marker)
            self.assertGreaterEqual(indexes[name], 0, f"missing {name} build-origin marker")

        self.assertLess(indexes["origin_helper"], indexes["supervisor"])
        self.assertLess(indexes["install_helper"], indexes["supervisor"])
        self.assertLess(indexes["supervisor"], indexes["stage_result"])
        self.assertLess(indexes["stage_result"], indexes["switch"])
        self.assertLess(indexes["switch"], indexes["verify"])
        self.assertLess(indexes["verify"], indexes["codesign"])
        self.assertLess(indexes["codesign"], indexes["install"])

        self.assertIn('DERIVED_PLACEHOLDER="__NEMBRA_PROTECTED_DERIVED__"', source)
        self.assertIn(
            '--install-custody-helper-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64"',
            source,
        )
        self.assertIn(
            'STAGED_APP_TREE_SHA256="${BUILD_ORIGIN_CUSTODY_RESULT#*$\'\\t\'}"',
            source,
        )
        self.assertIn(
            '[[ "$VERIFIED_STAGE_TREE_SHA256" == "$STAGED_APP_TREE_SHA256" ]]',
            source,
        )
        self.assertIn("Noninteractive sudo authority remained after build-origin custody", source)

        self.assertNotIn(
            'APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"',
            source,
        )
        self.assertNotIn("SOURCE_APP_TREE_SHA256=", source)
        self.assertNotIn(
            '/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"',
            source,
        )

    def test_supervisor_orders_revocation_build_lock_fingerprint_and_stage(self) -> None:
        source = ORIGIN_HELPER.read_text(encoding="utf-8")
        markers = {
            "sudo_revoke": "_invalidate_invoker_sudo(uid, gid, invoking_groups, child_env)",
            "prepare": "derived_root = _prepare_derived(private_tmp, capability_gid)",
            "spawn": "process = subprocess.Popen(",
            "retire": "_terminate_remaining_process_group(process.pid)",
            "lock_owner": "os.chown(derived_root, 0, 0)",
            "lock_mode": "os.chmod(derived_root, 0o700)",
            "source_hash": "source_fingerprint = str(fingerprint(source_app))",
            "stage": "stage_root, stage_app = _copy_to_stage(source_app, private_tmp)",
            "stage_hash": "staged_fingerprint = str(fingerprint(stage_app))",
        }
        indexes: dict[str, int] = {}
        search_from = 0
        for name in (
            "sudo_revoke",
            "prepare",
            "spawn",
            "lock_owner",
            "lock_mode",
            "retire",
            "source_hash",
            "stage",
            "stage_hash",
        ):
            index = source.find(markers[name], search_from)
            self.assertGreaterEqual(index, 0, f"missing {name} supervisor marker")
            indexes[name] = index
            search_from = index + 1

        self.assertIn("os.chown(derived, 0, capability_gid)", source)
        self.assertIn("os.chmod(derived, 0o770)", source)
        self.assertIn("if gid <= 0:", source)
        self.assertIn("if any(value <= 0 for value in groups):", source)
        self.assertIn("credentials = _structured_credentials(uid, gid, groups)", source)
        self.assertIn("child_groups = (capability_gid,)", source)
        self.assertIn("**_structured_credentials(uid, gid, child_groups)", source)
        self.assertNotIn("preexec_fn=", source)
        self.assertIn('["/usr/bin/sudo", "-K"]', source)
        self.assertIn('["/usr/bin/sudo", "-n", "/usr/bin/true"]', source)
        self.assertIn('["/usr/bin/ditto", "--noacl"', source)
        self.assertIn("if staged_fingerprint != source_fingerprint:", source)
        self.assertIn("shutil.rmtree(derived_root, ignore_errors=True)", source)

    def test_placeholder_is_exactly_single_use(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody")
        derived = Path("/private/tmp/example")
        self.assertEqual(
            helper._replace_derived_placeholder(
                ["tool", helper.DERIVED_PLACEHOLDER],
                derived,
            ),
            ["tool", str(derived)],
        )
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._replace_derived_placeholder(["tool"], derived)
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._replace_derived_placeholder(
                ["tool", helper.DERIVED_PLACEHOLDER, helper.DERIVED_PLACEHOLDER],
                derived,
            )

    def test_capability_gid_never_reuses_invoking_or_named_group(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody")
        occupied = {group.gr_gid for group in helper.grp.getgrall()}
        invoking = tuple(sorted(occupied))[:4] or (20,)
        low = 1 << 29
        candidate = low + 12345
        while candidate in occupied or candidate in invoking:
            candidate += 1
        selected = helper._choose_capability_gid(
            invoking,
            randbelow=lambda _: candidate - low,
        )
        self.assertEqual(selected, candidate)
        self.assertNotIn(selected, occupied)
        self.assertNotIn(selected, invoking)

    def test_structured_credentials_preserve_explicit_authority_without_primary_duplication(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_credentials")
        capability_gid = (1 << 29) + 12345
        self.assertEqual(
            helper._structured_credentials(501, 20, (20, capability_gid, capability_gid)),
            {
                "user": 501,
                "group": 20,
                "extra_groups": [capability_gid],
            },
        )
        self.assertEqual(
            helper._structured_credentials(501, 20, (20, 80, 701, 80)),
            {
                "user": 501,
                "group": 20,
                "extra_groups": [80, 701],
            },
        )
        self.assertEqual(
            helper._structured_credentials(501, 20, ()),
            {"user": 501, "group": 20, "extra_groups": []},
        )
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._structured_credentials(501, 20, (0,))
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._structured_credentials(501, 0, ())
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._structured_credentials(0, 20, ())

    def test_invoking_identity_rejects_root_primary_group(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_root_gid")
        environment = {
            "SUDO_UID": "501",
            "SUDO_GID": "0",
            "SUDO_USER": "field",
        }
        with (
            mock.patch.object(helper.os, "geteuid", return_value=0),
            mock.patch.dict(helper.os.environ, environment, clear=False),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._invoking_identity()

    def test_post_handoff_replacement_cannot_change_promoted_stage_model(self) -> None:
        install = load(INSTALL_HELPER, "capture_signed_app_install_custody_for_origin")
        with tempfile.TemporaryDirectory(prefix="nembra-origin-model-") as temporary:
            root = Path(temporary)
            isolated = root / "isolated/Nembra Capture.app"
            isolated.mkdir(parents=True)
            (isolated / "Info.plist").write_text(
                "accepted build provenance\n",
                encoding="utf-8",
            )
            (isolated / "Nembra Capture").write_bytes(b"ACCEPTED_XCODEBUILD_OUTPUT\n")
            build_fingerprint = install.fingerprint(isolated)

            protected = root / "protected/Nembra Capture.app"
            protected.parent.mkdir()
            shutil.copytree(isolated, protected, symlinks=True)
            self.assertEqual(install.fingerprint(protected), build_fingerprint)

            replacement = root / "replacement.app"
            replacement.mkdir()
            (replacement / "Info.plist").write_text(
                "accepted build provenance\n",
                encoding="utf-8",
            )
            (replacement / "Nembra Capture").write_bytes(b"SUBSTITUTED_AFTER_HANDOFF\n")
            shutil.rmtree(isolated)
            os.rename(replacement, isolated)

            self.assertNotEqual(install.fingerprint(isolated), build_fingerprint)
            self.assertEqual(install.fingerprint(protected), build_fingerprint)

    @unittest.skipUnless(
        sys.platform == "darwin" and os.geteuid() == 0,
        "requires root on macOS",
    )
    def test_real_macos_capability_blocks_same_uid_and_root_lock_revokes_it(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_macos")
        user, uid, gid, _home, groups = helper._invoking_identity()
        capability_gid = helper._choose_capability_gid(groups)
        derived = helper._prepare_derived(helper._require_real_private_tmp(), capability_gid)
        target = derived / "proof.txt"
        try:
            normal_credentials = helper._structured_credentials(uid, gid, groups)
            capability_credentials = helper._structured_credentials(uid, gid, (capability_gid,))

            denied = subprocess.run(
                ["/usr/bin/touch", str(target)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                **normal_credentials,
            )
            self.assertNotEqual(
                denied.returncode,
                0,
                f"{user} unexpectedly reached root-owned capability DerivedData",
            )

            allowed = subprocess.run(
                ["/usr/bin/touch", str(target)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                **capability_credentials,
            )
            self.assertEqual(allowed.returncode, 0)

            os.chown(derived, 0, 0)
            os.chmod(derived, 0o700)
            revoked = subprocess.run(
                ["/bin/sh", "-c", f"printf changed > {target!s}"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                **capability_credentials,
            )
            self.assertNotEqual(
                revoked.returncode,
                0,
                "root lock failed to revoke the one-run build capability",
            )
        finally:
            shutil.rmtree(derived, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
