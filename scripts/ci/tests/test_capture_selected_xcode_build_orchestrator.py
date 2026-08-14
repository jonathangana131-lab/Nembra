#!/usr/bin/env python3
"""Regress the production selected-Xcode -> signed-build composition boundary."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
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
        command = [
            "/usr/bin/python3",
            "-I",
            "/accepted/guard.py",
            "--",
            "/usr/bin/xcodebuild",
            "-version",
        ]
        replaced = helper._replace_selected_xcode(
            command,
            frozen_developer=developer,
            selected_xcodebuild=xcodebuild,
        )
        marker = replaced.index("/usr/bin/env")
        self.assertEqual(
            replaced[marker : marker + 3],
            ["/usr/bin/env", f"DEVELOPER_DIR={developer}", str(xcodebuild)],
        )
        self.assertNotIn("/usr/bin/xcodebuild", replaced)
        self.assertEqual(command[-2:], ["/usr/bin/xcodebuild", "-version"])

        bad_commands = (
            ["/usr/bin/python3", "guard.py"],
            ["/usr/bin/xcodebuild", "/usr/bin/xcodebuild"],
            ["DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer", "/usr/bin/xcodebuild"],
        )
        for bad in bad_commands:
            with self.subTest(command=bad), self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._replace_selected_xcode(
                    bad,
                    frozen_developer=developer,
                    selected_xcodebuild=xcodebuild,
                )

        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._replace_selected_xcode(
                ["/usr/bin/xcodebuild"],
                frozen_developer=developer,
                selected_xcodebuild=Path("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"),
            )

    def test_frozen_tool_must_remain_inside_frozen_developer_tree(self) -> None:
        helper = load()
        developer = Path("/Library/NembraSelectedXcodeFreeze.test/Xcode.app/Contents/Developer")
        expected = developer / "usr/bin/devicectl"
        self.assertEqual(helper._require_frozen_tool({"devicectl": expected}, "devicectl", developer), expected)
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._require_frozen_tool(
                {"devicectl": Path("/usr/bin/devicectl")},
                "devicectl",
                developer,
            )
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._require_frozen_tool({}, "devicectl", developer)

    def test_git_blob_transport_rejects_substitution(self) -> None:
        helper = load()
        raw = b"accepted selected-Xcode helper bytes\n"
        blob = helper._git_blob_oid(raw)
        encoded = __import__("base64").b64encode(raw).decode("ascii")
        self.assertEqual(helper._decode_verified_git_blob(encoded, blob, "fixture"), raw)
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._decode_verified_git_blob(
                __import__("base64").b64encode(b"substituted\n").decode("ascii"),
                blob,
                "fixture",
            )
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._decode_verified_git_blob(encoded, "not-a-git-blob", "fixture")

    def test_orchestration_uses_launcher_returned_xcode_in_same_root_process(self) -> None:
        helper = load()
        launcher_source = b'''\
from pathlib import Path

def run(field_pid, source_sha, freeze_helper_base64, freeze_helper_blob):
    assert field_pid == 4242
    assert source_sha == "a" * 40
    developer = Path("/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer")
    return (
        Path("/Library/NembraSelectedXcodeFreeze.fixture"),
        developer,
        {
            "xcodebuild": developer / "usr/bin/xcodebuild",
            "xctrace": developer / "usr/bin/xctrace",
            "devicectl": developer / "usr/bin/devicectl",
        },
        777,
    )
'''
        build_source = b'''\
from pathlib import Path

def run_custodied_build(command, *, app_relative, fingerprint_helper_base64):
    developer = "/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"
    selected = developer + "/usr/bin/xcodebuild"
    marker = command.index("/usr/bin/env")
    assert command[marker:marker + 3] == ["/usr/bin/env", "DEVELOPER_DIR=" + developer, selected]
    assert "/usr/bin/xcodebuild" not in command
    assert app_relative == Path("Build/Products/Debug-iphoneos/Nembra Capture.app")
    assert fingerprint_helper_base64 == INSTALL_BASE64
    return Path("/private/tmp/nembra-authenticated-capture-install.fixture"), "b" * 64
'''
        freeze_source = b"# accepted freeze helper fixture\n"
        install_source = b"# accepted install helper fixture\n"
        encode = lambda raw: __import__("base64").b64encode(raw).decode("ascii")
        install_encoded = encode(install_source)
        build_source = build_source.replace(b"INSTALL_BASE64", repr(install_encoded).encode("ascii"))

        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.os, "geteuid", return_value=0),
        ):
            stage, fingerprint, developer, xctrace, devicectl = helper.orchestrate(
                field_pid=4242,
                source_sha="a" * 40,
                freeze_launcher_base64=encode(launcher_source),
                freeze_launcher_blob=helper._git_blob_oid(launcher_source),
                freeze_helper_base64=encode(freeze_source),
                freeze_helper_blob=helper._git_blob_oid(freeze_source),
                build_origin_base64=encode(build_source),
                build_origin_blob=helper._git_blob_oid(build_source),
                install_custody_base64=install_encoded,
                install_custody_blob=helper._git_blob_oid(install_source),
                command=[
                    "/usr/bin/python3",
                    "-I",
                    "/accepted/guard.py",
                    "--",
                    "/usr/bin/xcodebuild",
                    "-version",
                ],
            )
        expected_developer = Path(
            "/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"
        )
        self.assertEqual(stage, Path("/private/tmp/nembra-authenticated-capture-install.fixture"))
        self.assertEqual(fingerprint, "b" * 64)
        self.assertEqual(developer, expected_developer)
        self.assertEqual(xctrace, expected_developer / "usr/bin/xctrace")
        self.assertEqual(devicectl, expected_developer / "usr/bin/devicectl")

    def test_installer_transports_and_invokes_exact_composition(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        syntax = subprocess.run(
            ["/bin/bash", "-n", str(INSTALLER)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        required = (
            'SELECTED_XCODE_FREEZE_HELPER_PATH="scripts/ci/capture_selected_xcode_freeze.py"',
            'SELECTED_XCODE_FREEZE_LAUNCHER_PATH="scripts/ci/capture_selected_xcode_freeze_launcher.py"',
            'SELECTED_XCODE_BUILD_ORCHESTRATOR_PATH="scripts/ci/capture_selected_xcode_build_orchestrator.py"',
            '"$SOURCE_SHA:$SELECTED_XCODE_FREEZE_HELPER_PATH"',
            '"$SOURCE_SHA:$SELECTED_XCODE_FREEZE_LAUNCHER_PATH"',
            '"$SOURCE_SHA:$SELECTED_XCODE_BUILD_ORCHESTRATOR_PATH"',
            '"$SELECTED_XCODE_BUILD_ORCHESTRATOR_BASE64"',
            '"$SELECTED_XCODE_BUILD_ORCHESTRATOR_BLOB"',
            '--field-pid "$$"',
            '--source-sha "$SOURCE_SHA"',
            '--freeze-launcher-base64 "$SELECTED_XCODE_FREEZE_LAUNCHER_BASE64"',
            '--freeze-helper-base64 "$SELECTED_XCODE_FREEZE_HELPER_BASE64"',
            '--build-origin-base64 "$BUILD_ORIGIN_CUSTODY_HELPER_BASE64"',
            '--install-custody-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64"',
            '-- /usr/bin/xcodebuild',
            '/usr/bin/sudo -n -l',
        )
        for fragment in required:
            self.assertIn(fragment, source)
        self.assertNotIn('sys.argv = ["<accepted-build-origin-custody>"]', source)
        self.assertNotIn(
            "otherwise-unused supplementary gid given to this guarded build process group",
            source,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
