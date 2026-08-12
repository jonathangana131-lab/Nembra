#!/usr/bin/env python3
"""Regress the compiler-output -> protected-stage origin boundary for field Capture."""

from __future__ import annotations

import errno
import importlib.util
import os
from pathlib import Path
import shutil
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

    def test_supervisor_requires_dedicated_identity_apfs_quiescence_before_fingerprint(self) -> None:
        source = ORIGIN_HELPER.read_text(encoding="utf-8")
        markers = {
            "sudo_revoke": "_invalidate_invoker_sudo(field_user, field_uid, field_gid, field_groups, field_env)",
            "identity_id": "build_uid = _choose_ephemeral_id()",
            "identity_create": "_create_local_build_identity(build_name, build_uid, build_gid, home)",
            "image": "_create_apfs_image(image)",
            "attach_rw": "writable_device = _attach_apfs(image, mountpoint, readonly=False)",
            "spawn": "build = subprocess.run(",
            "lock_owner": "os.chown(mountpoint, 0, 0)",
            "lock_mode": "os.chmod(mountpoint, 0o700)",
            "detach_rw": "detach = _detach_apfs(writable_device)",
            "status": "if build.returncode != 0:",
            "attach_ro": "readonly_device = _attach_apfs(image, mountpoint, readonly=True)",
            "readonly_probe": "_require_readonly_mount(mountpoint)",
            "source_hash": "source_fingerprint = str(fingerprint(source_app))",
            "stage": "stage_root, stage_app = _copy_to_stage(source_app, private_tmp)",
            "stage_hash": "staged_fingerprint = str(fingerprint(stage_app))",
            "detach_ro": "frozen_detach = _detach_apfs(readonly_device)",
        }
        indexes: dict[str, int] = {}
        search_from = 0
        for name in markers:
            index = source.find(markers[name], search_from)
            self.assertGreaterEqual(index, 0, f"missing {name} dedicated-UID/APFS marker")
            indexes[name] = index
            search_from = index + 1

        self.assertLess(indexes["detach_rw"], indexes["status"])
        self.assertLess(indexes["status"], indexes["attach_ro"])
        self.assertLess(indexes["readonly_probe"], indexes["source_hash"])
        self.assertLess(indexes["source_hash"], indexes["stage"])
        self.assertLess(indexes["stage_hash"], indexes["detach_ro"])

        self.assertIn("build_gid = build_uid", source)
        self.assertIn("if build_uid == field_uid or build_gid in field_groups:", source)
        self.assertIn("**_structured_credentials(build_uid, build_gid, ())", source)
        self.assertIn('"-owners",\n        "on",', source)
        self.assertEqual(source.count('"-owners"'), 1)
        self.assertIn("if detach.returncode != 0:", source)
        self.assertIn("normal non-forced quiescence", source)
        self.assertIn('["/usr/bin/ditto", "--noacl"', source)
        self.assertIn("if staged_fingerprint != source_fingerprint:", source)
        self.assertIn("_remove_local_build_identity(build_name, build_uid)", source)
        self.assertIn("_detach_apfs(readonly_device, force=True)", source)
        self.assertIn("_detach_apfs(writable_device, force=True)", source)

        self.assertNotIn("_choose_capability_gid", source)
        self.assertNotIn("_prepare_derived", source)
        self.assertNotIn("_terminate_remaining_process_group", source)
        self.assertNotIn("preexec_fn=", source)

    def test_placeholder_is_exactly_single_use(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody")
        derived = Path("/private/tmp/example")
        self.assertEqual(
            helper._replace_derived_placeholder(["tool", helper.DERIVED_PLACEHOLDER], derived),
            ["tool", str(derived)],
        )
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._replace_derived_placeholder(["tool"], derived)
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._replace_derived_placeholder(
                ["tool", helper.DERIVED_PLACEHOLDER, helper.DERIVED_PLACEHOLDER], derived
            )

    def test_ephemeral_identity_selector_skips_existing_ids(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_identity")
        with (
            mock.patch.object(helper.os, "getpid", return_value=123),
            mock.patch.object(helper, "_id_in_use", side_effect=lambda value: value < 52125),
        ):
            self.assertEqual(helper._choose_ephemeral_id(), 52125)

    def test_structured_credentials_preserve_explicit_authority_without_primary_duplication(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_credentials")
        self.assertEqual(
            helper._structured_credentials(501, 20, (20, 80, 701, 80)),
            {"user": 501, "group": 20, "extra_groups": [80, 701]},
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

    def test_sudo_policy_classifier_rejects_passwordless_authority(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_sudo_policy")
        self.assertTrue(
            helper._sudo_policy_exposes_passwordless_authority(
                "User field may run the following commands:\n    (ALL) NOPASSWD: /bin/kill\n",
                ("staff", "admin"),
            )
        )
        self.assertTrue(
            helper._sudo_policy_exposes_passwordless_authority(
                "Matching Defaults entries:\n    !authenticate\n",
                ("staff",),
            )
        )
        self.assertTrue(
            helper._sudo_policy_exposes_passwordless_authority(
                "Matching Defaults entries:\n    exempt_group=admin, env_reset\n",
                ("staff", "admin"),
            )
        )
        self.assertFalse(
            helper._sudo_policy_exposes_passwordless_authority(
                "Matching Defaults entries:\n    env_reset, secure_path=/usr/bin:/bin\n"
                "User field may run the following commands:\n    (ALL) /usr/bin/xcodebuild\n",
                ("staff", "admin"),
            )
        )

    def test_invoking_identity_rejects_root_primary_group(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_root_gid")
        environment = {"SUDO_UID": "501", "SUDO_GID": "0", "SUDO_USER": "field"}
        with (
            mock.patch.object(helper.os, "geteuid", return_value=0),
            mock.patch.dict(helper.os.environ, environment, clear=False),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._invoking_identity()

    def test_readonly_probe_accepts_only_explicit_erofs(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_readonly")
        mountpoint = Path("/private/tmp/nembra-readonly-test")
        with mock.patch.object(helper.os, "open", side_effect=OSError(errno.EROFS, "Read-only file system")):
            helper._require_readonly_mount(mountpoint)
        with (
            mock.patch.object(helper.os, "open", side_effect=OSError(errno.EACCES, "Permission denied")),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._require_readonly_mount(mountpoint)

    def test_post_handoff_replacement_cannot_change_promoted_stage_model(self) -> None:
        install = load(INSTALL_HELPER, "capture_signed_app_install_custody_for_origin")
        with tempfile.TemporaryDirectory(prefix="nembra-origin-model-") as temporary:
            root = Path(temporary)
            isolated = root / "isolated/Nembra Capture.app"
            isolated.mkdir(parents=True)
            (isolated / "Info.plist").write_text("accepted build provenance\n", encoding="utf-8")
            (isolated / "Nembra Capture").write_bytes(b"ACCEPTED_XCODEBUILD_OUTPUT\n")
            build_fingerprint = install.fingerprint(isolated)

            protected = root / "protected/Nembra Capture.app"
            protected.parent.mkdir()
            shutil.copytree(isolated, protected, symlinks=True)
            self.assertEqual(install.fingerprint(protected), build_fingerprint)

            replacement = root / "replacement.app"
            replacement.mkdir()
            (replacement / "Info.plist").write_text("accepted build provenance\n", encoding="utf-8")
            (replacement / "Nembra Capture").write_bytes(b"SUBSTITUTED_AFTER_HANDOFF\n")
            shutil.rmtree(isolated)
            os.rename(replacement, isolated)

            self.assertNotEqual(install.fingerprint(isolated), build_fingerprint)
            self.assertEqual(install.fingerprint(protected), build_fingerprint)

    @unittest.skipUnless(
        sys.platform == "darwin" and os.geteuid() == 0,
        "requires root on macOS",
    )
    def test_real_macos_ephemeral_identity_is_distinct_from_field_authority(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_macos_identity")
        _user, field_uid, _field_gid, _home, field_groups = helper._invoking_identity()
        build_uid = helper._choose_ephemeral_id()
        build_gid = build_uid
        self.assertNotEqual(build_uid, field_uid)
        self.assertNotIn(build_gid, field_groups)
        private_tmp = helper._require_real_private_tmp()
        workspace = Path(tempfile.mkdtemp(prefix="nembra-build-identity-test.", dir=private_tmp))
        home = workspace / "home"
        name = f"nembratest{os.getpid()}"
        created = False
        try:
            home.mkdir()
            helper._create_local_build_identity(name, build_uid, build_gid, home)
            created = True
            account = helper.pwd.getpwnam(name)
            group = helper.grp.getgrnam(name)
            self.assertEqual((account.pw_uid, account.pw_gid, group.gr_gid), (build_uid, build_gid, build_gid))
        finally:
            if created:
                helper._remove_local_build_identity(name, build_uid)
            shutil.rmtree(workspace, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
