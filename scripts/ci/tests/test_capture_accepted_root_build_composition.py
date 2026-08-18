#!/usr/bin/env python3
"""Prove selected-Xcode strict mode consumes the sealed accepted build root."""

from __future__ import annotations

import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_accepted_root_build_composition", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def encode(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def canonical_command(helper, repo: Path) -> list[str]:
    return [
        "/usr/bin/python3",
        "-I",
        str(repo / helper.ACCEPTED_GUARD_RELATIVE),
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
        "-workspace",
        str(repo / "NembraCapture.xcworkspace"),
        "-scheme",
        "Nembra Capture",
    ]


class CaptureAcceptedRootBuildCompositionTests(unittest.TestCase):
    def test_private_guard_paths_rebase_only_from_canonical_live_subjects(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-accepted-root-rebase-") as temporary:
            accepted_root = Path(temporary) / "accepted"
            accepted_root.mkdir()
            command = canonical_command(helper, REPOSITORY)
            rebased = helper._rebase_private_guard_paths(
                command,
                live_repo=REPOSITORY,
                accepted_root=accepted_root,
            )
            expected = {
                "--lockfile": Path("Podfile.lock"),
                "--security-podspec": Path("LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),
                "--security-build": Path("LocalSecrets/TuyaSDK/Build"),
                "--identity-podspec": Path(
                    "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
                ),
                "--identity-sources": Path(
                    "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
                ),
            }
            for flag, relative in expected.items():
                self.assertEqual(
                    rebased[rebased.index(flag) + 1],
                    str(accepted_root / relative),
                )
            self.assertEqual(command, canonical_command(helper, REPOSITORY))

            compiler_rebased = helper._rebase_accepted_root_compiler_paths(
                rebased, live_repo=REPOSITORY, accepted_root=accepted_root
            )
            workspace_index = compiler_rebased.index("-workspace")
            self.assertEqual(
                compiler_rebased[workspace_index + 1],
                str(accepted_root / "NembraCapture.xcworkspace"),
            )

            relative_workspace = list(rebased)
            relative_workspace[relative_workspace.index("-workspace") + 1] = "NembraCapture.xcworkspace"
            relative_rebased = helper._rebase_accepted_root_compiler_paths(
                relative_workspace, live_repo=REPOSITORY, accepted_root=accepted_root
            )
            self.assertEqual(
                relative_rebased[relative_rebased.index("-workspace") + 1],
                str(accepted_root / "NembraCapture.xcworkspace"),
            )

            escaped_workspace = list(rebased)
            escaped_workspace[escaped_workspace.index("-workspace") + 1] = str(REPOSITORY.parent / "attacker.xcworkspace")
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._rebase_accepted_root_compiler_paths(
                    escaped_workspace, live_repo=REPOSITORY, accepted_root=accepted_root
                )

            project_command = list(rebased)
            project_command[project_command.index("-workspace")] = "-project"
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._rebase_accepted_root_compiler_paths(
                    project_command, live_repo=REPOSITORY, accepted_root=accepted_root
                )

            escaped = list(command)
            escaped[escaped.index("--security-build") + 1] = str(REPOSITORY / "other")
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._rebase_private_guard_paths(
                    escaped,
                    live_repo=REPOSITORY,
                    accepted_root=accepted_root,
                )

    def test_strict_mode_forces_compiler_into_sealed_root_and_rechecks_identity(self) -> None:
        helper = load()
        source_sha = "a" * 40
        manifest = "c" * 64
        fingerprint = "d" * 64
        freeze_source = b"# accepted freeze helper fixture\n"
        install_source = b"# accepted install helper fixture\n"
        install_encoded = encode(install_source)
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

        class FakeLease:
            instances: list["FakeLease"] = []

            def __init__(self, subjects, repo, *, use_native_darwin_acl=False):
                self.subjects = tuple(subjects)
                self.repo = repo
                self.use_native_darwin_acl = bool(use_native_darwin_acl)
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

        with tempfile.TemporaryDirectory(prefix="nembra-strict-root-composition-") as temporary:
            fixture = Path(temporary)
            accepted_root = fixture / "accepted-root"
            accepted_root.mkdir()
            root_bundle = fixture / "root-helper-bundle"
            root_bundle.mkdir()
            root_helper = root_bundle / "capture_accepted_build_root_custody.py"
            root_helper.write_text("# mocked exact helper bytes\n", encoding="utf-8")
            guard_bundle = fixture / "guard-bundle"
            guard_bundle.mkdir()
            accepted_guard = guard_bundle / helper.ACCEPTED_GUARD_RELATIVE.name
            accepted_provenance = guard_bundle / helper.ACCEPTED_PROVENANCE_RELATIVE.name
            accepted_guard.write_text("# fixture guard\n", encoding="utf-8")
            accepted_provenance.write_text("# fixture provenance\n", encoding="utf-8")

            root_events: list[object] = []

            class RootAuthority:
                @staticmethod
                def create_accepted_build_root(repo, observed_sha, observed_manifest):
                    root_events.append(("create", repo, observed_sha, observed_manifest))
                    return accepted_root, fingerprint, manifest

                @staticmethod
                def accepted_build_root_fingerprint(root):
                    root_events.append(("fingerprint", root))
                    return fingerprint

                @staticmethod
                def destroy_accepted_build_root(root):
                    root_events.append(("destroy", root))

            build_source = b'''\
from pathlib import Path

def _value(command, flag):
    index = command.index(flag)
    return command[index + 1]

def _run_exec_bound_build(command, *, name, uid, gid, baseline_groups, environment, cwd):
    assert name == "nembrabuildfixture"
    assert cwd == Path(EXPECTED_ROOT)
    assert command[2] == EXPECTED_GUARD
    assert _value(command, "--lockfile") == EXPECTED_ROOT + "/Podfile.lock"
    assert _value(command, "--security-podspec") == EXPECTED_ROOT + "/LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"
    assert _value(command, "--security-build") == EXPECTED_ROOT + "/LocalSecrets/TuyaSDK/Build"
    assert _value(command, "--identity-podspec") == EXPECTED_ROOT + "/LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"
    assert _value(command, "--identity-sources") == EXPECTED_ROOT + "/LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
    assert _value(command, "-workspace") == EXPECTED_ROOT + "/NembraCapture.xcworkspace"
    developer = "/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"
    selected = developer + "/usr/bin/xcodebuild"
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
        cwd=Path("/caller-controlled-live-cwd"),
    ) == 0
    assert app_relative == Path("Build/Products/Debug-iphoneos/Nembra Capture.app")
    assert fingerprint_helper_base64 == INSTALL_BASE64
    return Path("/private/tmp/nembra-authenticated-capture-install.fixture"), "e" * 64
'''
            build_source = build_source.replace(
                b"EXPECTED_ROOT", repr(str(accepted_root)).encode("ascii")
            )
            build_source = build_source.replace(
                b"EXPECTED_GUARD", repr(str(accepted_guard)).encode("ascii")
            )
            build_source = build_source.replace(
                b"INSTALL_BASE64", repr(install_encoded).encode("ascii")
            )

            FakeLease.instances.clear()
            command = canonical_command(helper, REPOSITORY)
            with (
                mock.patch.object(helper.sys, "platform", "darwin"),
                mock.patch.object(helper.os, "geteuid", return_value=0),
                mock.patch.object(helper.os, "getcwd", return_value=str(REPOSITORY)),
                mock.patch.object(
                    helper,
                    "_materialize_accepted_build_root_bundle",
                    return_value=(root_bundle, root_helper),
                ),
                mock.patch.object(
                    helper,
                    "_load_python_module",
                    return_value=RootAuthority,
                ),
                mock.patch.object(
                    helper,
                    "_materialize_accepted_guard_bundle",
                    return_value=(guard_bundle, accepted_guard, accepted_provenance),
                ),
                mock.patch.object(helper, "_PrivateReadLease", FakeLease),
            ):
                stage, observed_fingerprint = helper.orchestrate(
                    field_pid=4242,
                    source_sha=source_sha,
                    freeze_launcher_base64=encode(launcher_source),
                    freeze_launcher_blob=helper._git_blob_oid(launcher_source),
                    freeze_helper_base64=encode(freeze_source),
                    freeze_helper_blob=helper._git_blob_oid(freeze_source),
                    build_origin_base64=encode(build_source),
                    build_origin_blob=helper._git_blob_oid(build_source),
                    install_custody_base64=install_encoded,
                    install_custody_blob=helper._git_blob_oid(install_source),
                    accepted_generated_manifest_sha256=manifest,
                    command=command,
                )

            self.assertEqual(
                stage, Path("/private/tmp/nembra-authenticated-capture-install.fixture")
            )
            self.assertEqual(observed_fingerprint, "e" * 64)
            self.assertEqual(len(FakeLease.instances), 1)
            lease = FakeLease.instances[0]
            self.assertEqual(
                lease.subjects,
                (accepted_root,),
            )
            self.assertEqual(lease.repo, accepted_root)
            self.assertTrue(lease.use_native_darwin_acl)
            self.assertEqual(
                lease.events,
                ["grant:nembrabuildfixture", "revoke"],
            )
            self.assertEqual(
                root_events,
                [
                    ("create", REPOSITORY, source_sha, manifest),
                    ("fingerprint", accepted_root),
                    ("destroy", accepted_root),
                ],
            )

    def test_strict_manifest_digest_is_required_to_be_exact_sha256_hex(self) -> None:
        helper = load()
        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.os, "geteuid", return_value=0),
        ):
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper.orchestrate(
                    field_pid=4242,
                    source_sha="a" * 40,
                    freeze_launcher_base64="unused",
                    freeze_launcher_blob="unused",
                    freeze_helper_base64="unused",
                    freeze_helper_blob="unused",
                    build_origin_base64="unused",
                    build_origin_blob="unused",
                    install_custody_base64="unused",
                    install_custody_blob="unused",
                    accepted_generated_manifest_sha256="not-a-sha256",
                    command=[],
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
