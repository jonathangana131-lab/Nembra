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
            "group_attestation": "build_groups = _attest_build_identity_groups(\n            build_name,",
            "image": "_create_apfs_image(image)",
            "attach_rw": "writable_device = _attach_apfs(image, mountpoint, readonly=False)",
            "spawn": "build = _run_exec_bound_build(",
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

        self.assertLess(indexes["group_attestation"], indexes["image"])
        self.assertLess(indexes["attach_rw"], indexes["spawn"])
        self.assertLess(indexes["spawn"], indexes["lock_owner"])
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
        self.assertIn("if effective != expected:", source)
        self.assertIn("if effective.intersection(field_only):", source)
        self.assertIn("def _run_exec_bound_build(", source)
        self.assertIn('"NEMBRA_EXEC_ATTEST_EXPECTED_GROUPS_JSON"', source)
        self.assertIn("os.execve(command[0], command, os.environ)", source)
        self.assertIn("baseline_groups=build_groups", source)
        self.assertNotIn("build = subprocess.run(\n            guarded_command,", source)
        self.assertIn("def _process_state_for_uid(", source)
        self.assertIn("if not _numeric_principal_in_use(candidate):", source)
        self.assertIn("def _wait_for_no_live_uid(", source)
        self.assertIn("if not latest_live:", source)
        self.assertIn("_wait_for_no_live_uid(uid)", source)
        self.assertIn("if detach.returncode != 0:", source)
        self.assertIn("normal non-forced quiescence", source)
        self.assertIn('["/usr/bin/ditto", "--noacl"', source)
        self.assertIn("if staged_fingerprint != source_fingerprint:", source)
        self.assertIn("_remove_local_build_identity(build_name, build_uid, require_absent=True)", source)
        self.assertIn("if retirement_error is not None:", source)
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

    def test_ephemeral_identity_selector_skips_account_and_process_collisions(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_identity")
        with (
            mock.patch.object(helper.os, "getpid", return_value=123),
            mock.patch.object(
                helper,
                "_numeric_principal_in_use",
                side_effect=lambda value: value < 52125,
            ),
        ):
            self.assertEqual(helper._choose_ephemeral_id(), 52125)

        with (
            mock.patch.object(helper, "_id_in_use", return_value=False),
            mock.patch.object(helper, "_process_state_for_uid", return_value=((999,), ())),
        ):
            self.assertTrue(helper._numeric_principal_in_use(55001))
        with (
            mock.patch.object(helper, "_id_in_use", return_value=False),
            mock.patch.object(helper, "_process_state_for_uid", return_value=((), (999,))),
        ):
            self.assertTrue(helper._numeric_principal_in_use(55001))
        with (
            mock.patch.object(helper, "_id_in_use", return_value=False),
            mock.patch.object(helper, "_process_state_for_uid", return_value=((), ())),
        ):
            self.assertFalse(helper._numeric_principal_in_use(55001))

    def test_process_state_separates_live_and_zombie_numeric_uid_subjects(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_process_state")
        completed = mock.Mock(
            returncode=0,
            stdout="101 55001 S\n102 55001 Z\n103 501 R\n",
            stderr="",
        )
        with mock.patch.object(helper.subprocess, "run", return_value=completed):
            self.assertEqual(helper._process_state_for_uid(55001), ((101,), (102,)))

    def test_process_state_fails_closed_on_malformed_inventory(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_bad_process_state")
        malformed_outputs = (
            "101 55001\n",
            "not-a-pid 55001 S\n",
            "101 not-a-uid S\n",
            "0 55001 S\n",
        )
        for output in malformed_outputs:
            completed = mock.Mock(returncode=0, stdout=output, stderr="")
            with (
                self.subTest(output=output),
                mock.patch.object(helper.subprocess, "run", return_value=completed),
                self.assertRaises(helper.BuildOriginCustodyError),
            ):
                helper._process_state_for_uid(55001)

        failed = mock.Mock(returncode=1, stdout="", stderr="ps failed")
        with (
            mock.patch.object(helper.subprocess, "run", return_value=failed),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._process_state_for_uid(55001)

    def test_build_environment_rejects_ambient_xcode_selector_authority(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_environment")
        poison = {
            "DEVELOPER_DIR": "/tmp/poison-developer",
            "SDKROOT": "/tmp/poison-sdk",
            "TOOLCHAINS": "poison-toolchain",
            "__CF_USER_TEXT_ENCODING": "poison-encoding",
            "CC": "/tmp/poison-cc",
            "CXX": "/tmp/poison-cxx",
            "SWIFT_EXEC": "/tmp/poison-swift",
            "DYLD_INSERT_LIBRARIES": "/tmp/poison.dylib",
            "LANG": "poison_LANG",
            "LC_ALL": "poison_LC_ALL",
        }
        with tempfile.TemporaryDirectory(prefix="nembra-build-env-") as temporary:
            home = Path(temporary)
            with mock.patch.dict(helper.os.environ, poison, clear=True):
                environment = helper._build_environment("nembrabuildtest", home)
        self.assertEqual(
            environment,
            {
                "HOME": str(home),
                "USER": "nembrabuildtest",
                "LOGNAME": "nembrabuildtest",
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "TMPDIR": str(home / "tmp"),
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8",
            },
        )
        self.assertTrue(set(poison).isdisjoint(environment))

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

    def test_exec_bound_build_attests_then_execs_exact_absolute_command(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_exec_bound")
        completed = mock.Mock(returncode=0)
        command = ["/usr/bin/python3", "-B", "/private/tmp/guard.py", "arg"]
        environment = {"PATH": "/usr/bin:/bin", "HOME": "/private/tmp/home"}
        with mock.patch.object(helper.subprocess, "run", return_value=completed) as run:
            result = helper._run_exec_bound_build(
                command,
                name="nembrabuildtest",
                uid=55001,
                gid=55001,
                baseline_groups=(12, 61, 100, 701, 55001),
                environment=environment,
                cwd=Path("/private/tmp"),
            )
        self.assertIs(result, completed)
        argv = run.call_args.args[0]
        self.assertEqual(argv[:4], ["/usr/bin/python3", "-B", "-I", "-c"])
        self.assertIn("os.execve(command[0], command, os.environ)", argv[4])
        separator = argv.index("--")
        self.assertEqual(argv[separator + 1 :], command)
        self.assertEqual(run.call_args.kwargs["user"], 55001)
        self.assertEqual(run.call_args.kwargs["group"], 55001)
        self.assertEqual(run.call_args.kwargs["extra_groups"], [])
        exec_env = run.call_args.kwargs["env"]
        self.assertEqual(exec_env["NEMBRA_EXEC_ATTEST_EXPECTED_UID"], "55001")
        self.assertEqual(exec_env["NEMBRA_EXEC_ATTEST_EXPECTED_GID"], "55001")
        self.assertEqual(exec_env["NEMBRA_EXEC_ATTEST_EXPECTED_USER"], "nembrabuildtest")
        self.assertEqual(
            __import__("json").loads(exec_env["NEMBRA_EXEC_ATTEST_EXPECTED_GROUPS_JSON"]),
            [12, 61, 100, 701],
        )
        self.assertEqual(environment, {"PATH": "/usr/bin:/bin", "HOME": "/private/tmp/home"})

    def test_exec_bound_build_rejects_relative_or_invalid_group_authority(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_exec_rejection")
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._run_exec_bound_build(
                ["python3", "guard.py"],
                name="nembrabuildtest",
                uid=55001,
                gid=55001,
                baseline_groups=(55001,),
                environment={},
                cwd=Path("/private/tmp"),
            )
        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._run_exec_bound_build(
                ["/usr/bin/python3", "guard.py"],
                name="nembrabuildtest",
                uid=55001,
                gid=55001,
                baseline_groups=(0, 55001),
                environment={},
                cwd=Path("/private/tmp"),
            )

    def test_effective_build_groups_must_match_fresh_directory_service_baseline(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_groups")
        payload = {
            "uid": 55001,
            "euid": 55001,
            "gid": 55001,
            "egid": 55001,
            "groups": [12, 61, 100, 701, 55001],
            "user": "nembrabuildtest",
        }
        completed = mock.Mock(
            returncode=0,
            stdout=helper.GROUP_ATTESTOR_MARKER + __import__("json").dumps(payload) + "\n",
            stderr="",
        )
        with (
            mock.patch.object(helper.os, "getuid", return_value=0),
            mock.patch.object(helper.os, "getgrouplist", return_value=[55001, 12, 61, 100, 701]),
            mock.patch.object(helper.subprocess, "run", return_value=completed) as run,
        ):
            baseline = helper._attest_build_identity_groups(
                "nembrabuildtest",
                55001,
                55001,
                (20, 80, 12, 61, 100, 701),
                {"PATH": "/usr/bin:/bin"},
                Path("/private/tmp"),
            )
        self.assertEqual(baseline, (12, 61, 100, 701, 55001))
        self.assertEqual(run.call_args.kwargs["user"], 55001)
        self.assertEqual(run.call_args.kwargs["group"], 55001)
        self.assertEqual(run.call_args.kwargs["extra_groups"], [])

    def test_effective_build_groups_reject_field_only_leakage_or_baseline_drift(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_group_rejection")
        base_payload = {
            "uid": 55001,
            "euid": 55001,
            "gid": 55001,
            "egid": 55001,
            "groups": [12, 61, 100, 701, 55001],
            "user": "nembrabuildtest",
        }
        for bad_groups in ([12, 61, 80, 100, 701, 55001], [12, 61, 100, 55001]):
            payload = dict(base_payload)
            payload["groups"] = bad_groups
            completed = mock.Mock(
                returncode=0,
                stdout=helper.GROUP_ATTESTOR_MARKER + __import__("json").dumps(payload) + "\n",
                stderr="",
            )
            with (
                mock.patch.object(helper.os, "getuid", return_value=0),
                mock.patch.object(helper.os, "getgrouplist", return_value=[55001, 12, 61, 100, 701]),
                mock.patch.object(helper.subprocess, "run", return_value=completed),
                self.assertRaises(helper.BuildOriginCustodyError),
            ):
                helper._attest_build_identity_groups(
                    "nembrabuildtest",
                    55001,
                    55001,
                    (20, 80, 12, 61, 100, 701),
                    {"PATH": "/usr/bin:/bin"},
                    Path("/private/tmp"),
                )

    def test_verified_identity_retirement_requires_no_live_uid_or_identity_lookup(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_retirement")
        missing = mock.Mock(side_effect=KeyError)
        with (
            mock.patch.object(helper.pwd, "getpwnam", missing),
            mock.patch.object(helper.pwd, "getpwuid", missing),
            mock.patch.object(helper.grp, "getgrnam", missing),
            mock.patch.object(helper.grp, "getgrgid", missing),
            mock.patch.object(helper, "_process_state_for_uid", return_value=((), ())),
        ):
            helper._assert_local_build_identity_retired("nembrabuildtest", 55001)

        with (
            mock.patch.object(helper.pwd, "getpwnam", missing),
            mock.patch.object(helper.pwd, "getpwuid", missing),
            mock.patch.object(helper.grp, "getgrnam", missing),
            mock.patch.object(helper.grp, "getgrgid", missing),
            mock.patch.object(helper, "_process_state_for_uid", return_value=((1234,), ())),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._assert_local_build_identity_retired("nembrabuildtest", 55001, timeout=0)

        with (
            mock.patch.object(helper.pwd, "getpwnam", return_value=object()),
            mock.patch.object(helper.pwd, "getpwuid", missing),
            mock.patch.object(helper.grp, "getgrnam", missing),
            mock.patch.object(helper.grp, "getgrgid", missing),
            mock.patch.object(helper, "_process_state_for_uid", return_value=((), ())),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._assert_local_build_identity_retired("nembrabuildtest", 55001, timeout=0)

        with self.assertRaises(helper.BuildOriginCustodyError):
            helper._assert_local_build_identity_retired("nembrabuildtest", 0)

    def test_strict_identity_removal_proves_zero_live_uid_before_directory_service_deletion(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_strict_retirement")
        events: list[str] = []

        def run_side_effect(argv, **_kwargs):
            if argv[:3] == ["/usr/bin/pkill", "-9", "-u"]:
                events.append("pkill")
            elif argv[:3] == ["/usr/bin/dscl", ".", "-delete"]:
                if argv[3].startswith("/Users/"):
                    events.append("delete-user")
                elif argv[3].startswith("/Groups/"):
                    events.append("delete-group")
            return mock.Mock(returncode=0)

        def wait_side_effect(_uid, **_kwargs):
            events.append("zero-live")
            return ()

        def verify_side_effect(_name, _uid):
            events.append("verify-lookups")

        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.subprocess, "run", side_effect=run_side_effect),
            mock.patch.object(helper, "_wait_for_no_live_uid", side_effect=wait_side_effect),
            mock.patch.object(
                helper,
                "_assert_local_build_identity_retired",
                side_effect=verify_side_effect,
            ),
        ):
            helper._remove_local_build_identity("nembrabuildtest", 55001, require_absent=True)

        self.assertLess(events.index("pkill"), events.index("zero-live"))
        self.assertLess(events.index("zero-live"), events.index("delete-user"))
        self.assertLess(events.index("delete-user"), events.index("delete-group"))
        self.assertLess(events.index("delete-group"), events.index("verify-lookups"))

    def test_strict_identity_removal_rejects_unclassifiable_pkill_failure(self) -> None:
        helper = load(ORIGIN_HELPER, "capture_signed_app_build_origin_custody_pkill_failure")
        failed = mock.Mock(returncode=3)
        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.subprocess, "run", return_value=failed),
            self.assertRaises(helper.BuildOriginCustodyError),
        ):
            helper._remove_local_build_identity("nembrabuildtest", 55001, require_absent=True)

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
