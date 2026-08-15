#!/usr/bin/env python3
"""Regress selected-Xcode -> accepted-source snapshot -> signed-build composition."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"


def load():
    spec = importlib.util.spec_from_file_location("nembra_selected_xcode_build_orchestrator", ORCHESTRATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureSelectedXcodeBuildOrchestratorTests(unittest.TestCase):
    def test_selected_xcode_replacement_is_exact_and_rejects_ambient_selector(self) -> None:
        helper = load()
        developer = Path("/Library/NembraSelectedXcodeFreeze.test/Xcode.app/Contents/Developer")
        xcodebuild = developer / "usr/bin/xcodebuild"
        command = ["/usr/bin/python3", "-I", "/accepted/guard.py", "--", "/usr/bin/xcodebuild", "-version"]
        replaced = helper._replace_selected_xcode(command, frozen_developer=developer, selected_xcodebuild=xcodebuild)
        marker = replaced.index("/usr/bin/env")
        self.assertEqual(replaced[marker:marker + 3], ["/usr/bin/env", f"DEVELOPER_DIR={developer}", str(xcodebuild)])
        self.assertNotIn("/usr/bin/xcodebuild", replaced)
        for bad in (
            ["/usr/bin/python3", "guard.py"],
            ["/usr/bin/xcodebuild", "/usr/bin/xcodebuild"],
            ["DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer", "/usr/bin/xcodebuild"],
        ):
            with self.subTest(command=bad), self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._replace_selected_xcode(bad, frozen_developer=developer, selected_xcodebuild=xcodebuild)

    def test_frozen_tools_remain_inside_one_frozen_developer_tree(self) -> None:
        helper = load()
        developer = Path("/Library/NembraSelectedXcodeFreeze.test/Xcode.app/Contents/Developer")
        for name in ("xcodebuild", "xctrace", "devicectl"):
            expected = developer / "usr/bin" / name
            self.assertEqual(helper._require_frozen_tool({name: expected}, name, developer), expected)
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._require_frozen_tool({name: Path("/usr/bin") / name}, name, developer)

    def test_git_blob_transport_rejects_substitution(self) -> None:
        helper = load()
        raw = b"accepted helper bytes\n"
        blob = helper._git_blob_oid(raw)
        encoded = __import__("base64").b64encode(raw).decode("ascii")
        self.assertEqual(helper._decode_verified_git_blob(encoded, blob, "fixture"), raw)
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._decode_verified_git_blob(__import__("base64").b64encode(b"substituted\n").decode("ascii"), blob, "fixture")

    def test_orchestration_binds_snapshot_instead_of_live_tree_lease(self) -> None:
        helper = load()
        launcher_source = b'''\
from pathlib import Path

def run(field_pid, source_sha, freeze_helper_base64, freeze_helper_blob):
    developer = Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer")
    return (Path("/Library/NembraSelectedXcodeFreeze.fixture"), developer,
            {"xcodebuild": developer / "usr/bin/xcodebuild",
             "xctrace": developer / "usr/bin/xctrace",
             "devicectl": developer / "usr/bin/devicectl"}, 777)
'''
        build_source = b'''\
from pathlib import Path

def _run_exec_bound_build(command, *, name, uid, gid, baseline_groups, environment, cwd):
    return 0

def run_custodied_build(command, *, app_relative, fingerprint_helper_base64):
    assert _run_exec_bound_build(command, name="nembrabuildfixture", uid=52000, gid=52000,
                                 baseline_groups=(52000,), environment={}, cwd=Path("/live")) == 0
    return Path("/private/tmp/nembra-authenticated-capture-install.fixture"), "b" * 64
'''
        snapshot_source = b'''\
SCHEMA_VERSION = 1
GENERATED_SUBJECTS = ()
def stage_accepted_build_inputs(*args): return "c" * 64
def generated_manifest_sha256(*args): return "c" * 64
'''
        custody_source = b'''\
class FakeSnapshot:
    def __init__(self): self.bound = False; self.destroyed = False; self.sealed = True
    def bind_build_origin(self, build_origin):
        self.bound = True
        original = build_origin["_run_exec_bound_build"]
        def wrapped(command, **kwargs): return original(command, **{**kwargs, "cwd": __import__("pathlib").Path("/snapshot")})
        build_origin["_run_exec_bound_build"] = wrapped
    def destroy(self): self.destroyed = True
LAST = None
def create(**kwargs):
    global LAST
    LAST = FakeSnapshot()
    return LAST
'''
        freeze_source = b"# freeze\n"
        install_source = b"# install\n"
        encode = lambda raw: __import__("base64").b64encode(raw).decode("ascii")
        reads = {
            helper.SNAPSHOT_HELPER_RELATIVE: snapshot_source,
            helper.SNAPSHOT_CUSTODY_RELATIVE: custody_source,
        }
        command = [
            "/usr/bin/python3", "-I", str(REPOSITORY / helper.ACCEPTED_GUARD_RELATIVE),
            "--lockfile", str(REPOSITORY / "Podfile.lock"),
            "--security-podspec", str(REPOSITORY / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),
            "--security-build", str(REPOSITORY / "LocalSecrets/TuyaSDK/Build"),
            "--identity-podspec", str(REPOSITORY / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"),
            "--identity-sources", str(REPOSITORY / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"),
            "--", "/usr/bin/xcodebuild", "-version",
        ]
        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.os, "geteuid", return_value=0),
            mock.patch.object(helper.os, "getcwd", return_value=str(REPOSITORY)),
            mock.patch.object(helper, "_private_read_subjects", return_value=()),
            mock.patch.object(helper, "_read_accepted_git_blob", side_effect=lambda _repo, _sha, rel: reads[rel]),
        ):
            result = helper.orchestrate(
                field_pid=4242, source_sha="a" * 40,
                accepted_generated_manifest_sha256="c" * 64,
                freeze_launcher_base64=encode(launcher_source), freeze_launcher_blob=helper._git_blob_oid(launcher_source),
                freeze_helper_base64=encode(freeze_source), freeze_helper_blob=helper._git_blob_oid(freeze_source),
                build_origin_base64=encode(build_source), build_origin_blob=helper._git_blob_oid(build_source),
                install_custody_base64=encode(install_source), install_custody_blob=helper._git_blob_oid(install_source),
                command=command,
            )
        self.assertEqual(result[0], Path("/private/tmp/nembra-authenticated-capture-install.fixture"))
        self.assertEqual(result[1], "b" * 64)
        self.assertEqual(result[2], Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"))

    def test_main_serializes_exact_five_field_handoff_and_manifest_arg(self) -> None:
        helper = load()
        expected = (
            Path("/private/tmp/nembra-authenticated-capture-install.fixture"), "b" * 64,
            Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"),
            Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer/usr/bin/xctrace"),
            Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer/usr/bin/devicectl"),
        )
        args = mock.Mock(
            field_pid=4242, source_sha="a" * 40, accepted_generated_manifest_sha256="c" * 64,
            freeze_launcher_base64="launcher", freeze_launcher_blob="a" * 40,
            freeze_helper_base64="freeze", freeze_helper_blob="b" * 40,
            build_origin_base64="origin", build_origin_blob="c" * 40,
            install_custody_base64="install", install_custody_blob="d" * 40,
            command=["/usr/bin/xcodebuild"],
        )
        with mock.patch.object(helper, "_parse", return_value=args), mock.patch.object(helper, "orchestrate", return_value=expected), mock.patch.object(helper.sys, "stdout") as stdout:
            self.assertEqual(helper.main([]), 0)
        stdout.write.assert_called_once_with("\t".join(str(value) for value in expected) + "\n")

    def test_installer_carries_reviewed_manifest_and_frozen_device_tools(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        syntax = subprocess.run(["/bin/bash", "-n", str(INSTALLER)], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        for fragment in (
            'NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256',
            '--accepted-generated-manifest-sha256 "$ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256"',
            'IFS=$\'\\t\' read -r APP_INSTALL_STAGE_ROOT STAGED_APP_TREE_SHA256 SELECTED_XCODE_DEVELOPER_DIR SELECTED_XCTRACE SELECTED_DEVICECTL RESULT_EXTRA',
            'run_frozen_xcode_tool()',
            '"$SELECTED_DEVICECTL" device install app --device "$DEVICE_UDID" "$APP"',
        ):
            self.assertIn(fragment, source)
        self.assertNotIn('/usr/bin/xcrun xctrace', source)
        self.assertNotIn('/usr/bin/xcrun devicectl', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
