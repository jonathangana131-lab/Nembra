#!/usr/bin/env python3
"""Regress the production selected-Xcode -> private-input -> signed-build composition boundary."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
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

    def test_live_guard_replacement_requires_exact_canonical_marker(self) -> None:
        helper = load()
        live = Path("/repo/Scripts/capture_tuya_private_input_build_guard.py")
        accepted = Path("/private/tmp/nembra-accepted/guard.py")
        command = ["/usr/bin/python3", "-I", str(live), "--", "/usr/bin/xcodebuild"]
        replaced = helper._replace_live_guard(command, live_guard=live, accepted_guard=accepted)
        self.assertEqual(replaced[2], str(accepted))
        self.assertNotIn(str(live), replaced)
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._replace_live_guard(
                ["/usr/bin/python3", "-I", "/other/guard.py", "--", "/usr/bin/xcodebuild"],
                live_guard=live,
                accepted_guard=accepted,
            )
        with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
            helper._replace_live_guard(
                [str(live), str(live), "/usr/bin/xcodebuild"],
                live_guard=live,
                accepted_guard=accepted,
            )

    def test_private_subjects_are_exact_canonical_field_inputs(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-private-subject-contract-") as temporary:
            repo = Path(temporary)
            live_guard = repo / helper.ACCEPTED_GUARD_RELATIVE
            command = [
                "/usr/bin/python3",
                "-I",
                str(live_guard),
                "--lockfile",
                str(repo / "Podfile.lock"),
                "--security-podspec",
                str(repo / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),
                "--security-build",
                str(repo / "LocalSecrets/TuyaSDK/Build"),
                "--identity-podspec",
                str(repo / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"),
                "--identity-sources",
                str(repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"),
                "--",
                "/usr/bin/xcodebuild",
            ]
            self.assertEqual(
                helper._private_read_subjects(command, repo),
                (repo / "LocalSecrets/TuyaSDK", repo / "LocalSecrets/TuyaRuntime"),
            )
            escaped = list(command)
            escaped[escaped.index("--identity-sources") + 1] = str(repo / "other")
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._private_read_subjects(escaped, repo)

    def test_build_origin_exec_is_wrapped_by_exact_reversible_lease(self) -> None:
        helper = load()
        events: list[tuple[str, str]] = []

        class Lease:
            def grant(self, principal: str) -> None:
                events.append(("grant", principal))

            def revoke(self, **_kwargs) -> None:
                events.append(("revoke", ""))

        def original(command, *, name, uid, gid, baseline_groups, environment, cwd):
            events.append(("exec", name))
            self.assertEqual(command, ["/usr/bin/true"])
            return 0

        namespace: dict[str, object] = {"_run_exec_bound_build": original}
        helper._bind_private_read_lease(namespace, Lease())
        wrapped = namespace["_run_exec_bound_build"]
        result = wrapped(
            ["/usr/bin/true"],
            name="nembrabuildfixture",
            uid=52000,
            gid=52000,
            baseline_groups=(52000,),
            environment={},
            cwd=Path("/"),
        )
        self.assertEqual(result, 0)
        self.assertEqual(
            events,
            [("grant", "nembrabuildfixture"), ("exec", "nembrabuildfixture"), ("revoke", "")],
        )

    def test_orchestration_requires_full_launcher_toolset_exact_guard_and_lease(self) -> None:
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

def _run_exec_bound_build(command, *, name, uid, gid, baseline_groups, environment, cwd):
    developer = "/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"
    selected = developer + "/usr/bin/xcodebuild"
    assert command[2] == EXPECTED_GUARD
    marker = command.index("/usr/bin/env")
    assert command[marker:marker + 3] == ["/usr/bin/env", "DEVELOPER_DIR=" + developer, selected]
    assert "/usr/bin/xcodebuild" not in command
    return 0

def run_custodied_build(command, *, app_relative, fingerprint_helper_base64):
    assert _run_exec_bound_build(
        command,
        name="nembrabuildfixture",
        uid=52000,
        gid=52000,
        baseline_groups=(52000,),
        environment={},
        cwd=Path("/"),
    ) == 0
    assert app_relative == Path("Build/Products/Debug-iphoneos/Nembra Capture.app")
    assert fingerprint_helper_base64 == INSTALL_BASE64
    return Path("/private/tmp/nembra-authenticated-capture-install.fixture"), "b" * 64
'''
        freeze_source = b"# accepted freeze helper fixture\n"
        install_source = b"# accepted install helper fixture\n"
        encode = lambda raw: __import__("base64").b64encode(raw).decode("ascii")
        install_encoded = encode(install_source)

        class FakeLease:
            instances: list["FakeLease"] = []

            def __init__(self, subjects, repo):
                self.subjects = tuple(subjects)
                self.repo = repo
                self._opened: list[object] = []
                self._principal = ""
                self.events: list[str] = []
                self.__class__.instances.append(self)

            def grant(self, principal: str) -> None:
                self._principal = principal
                self._opened = [object()]
                self.events.append("grant:" + principal)

            def revoke(self, *, suppress_errors: bool = False) -> None:
                self.events.append("revoke")
                self._opened = []
                self._principal = ""

        with tempfile.TemporaryDirectory(prefix="nembra-accepted-guard-fixture-") as temporary:
            bundle = Path(temporary) / "bundle"
            bundle.mkdir()
            accepted_guard = bundle / helper.ACCEPTED_GUARD_RELATIVE.name
            accepted_provenance = bundle / helper.ACCEPTED_PROVENANCE_RELATIVE.name
            accepted_guard.write_text("# fixture\n", encoding="utf-8")
            accepted_provenance.write_text("# fixture\n", encoding="utf-8")
            build_source = build_source.replace(b"EXPECTED_GUARD", repr(str(accepted_guard)).encode("ascii"))
            build_source = build_source.replace(b"INSTALL_BASE64", repr(install_encoded).encode("ascii"))
            canonical_command = [
                "/usr/bin/python3",
                "-I",
                str(REPOSITORY / helper.ACCEPTED_GUARD_RELATIVE),
                "--lockfile",
                str(REPOSITORY / "Podfile.lock"),
                "--security-podspec",
                str(REPOSITORY / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),
                "--security-build",
                str(REPOSITORY / "LocalSecrets/TuyaSDK/Build"),
                "--identity-podspec",
                str(REPOSITORY / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"),
                "--identity-sources",
                str(REPOSITORY / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"),
                "--",
                "/usr/bin/xcodebuild",
                "-version",
            ]
            with (
                mock.patch.object(helper.sys, "platform", "darwin"),
                mock.patch.object(helper.os, "geteuid", return_value=0),
                mock.patch.object(helper.os, "getcwd", return_value=str(REPOSITORY)),
                mock.patch.object(
                    helper,
                    "_private_read_subjects",
                    return_value=(Path("/private/fixture/sdk"), Path("/private/fixture/runtime")),
                ),
                mock.patch.object(
                    helper,
                    "_materialize_accepted_guard_bundle",
                    return_value=(bundle, accepted_guard, accepted_provenance),
                ),
                mock.patch.object(helper, "_PrivateReadLease", FakeLease),
            ):
                stage, fingerprint = helper.orchestrate(
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
                    command=canonical_command,
                )
            self.assertEqual(stage, Path("/private/tmp/nembra-authenticated-capture-install.fixture"))
            self.assertEqual(fingerprint, "b" * 64)
            self.assertEqual(len(FakeLease.instances), 1)
            self.assertEqual(
                FakeLease.instances[0].events,
                ["grant:nembrabuildfixture", "revoke"],
            )

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
