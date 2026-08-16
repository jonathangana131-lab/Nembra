#!/usr/bin/env python3
"""Exploit-positive proof that strict accepted-root mode leaves an absolute workspace live."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_accepted_root_absolute_workspace_escape", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def canonical_guarded_command(helper, live_repo: Path, workspace: Path) -> list[str]:
    return [
        "/usr/bin/python3",
        "-I",
        str(live_repo / helper.ACCEPTED_GUARD_RELATIVE),
        "--lockfile",
        str(live_repo / "Podfile.lock"),
        "--security-podspec",
        str(live_repo / "LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),
        "--security-build",
        str(live_repo / "LocalSecrets/TuyaSDK/Build"),
        "--identity-podspec",
        str(live_repo / "LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"),
        "--identity-sources",
        str(live_repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"),
        "--",
        "/usr/bin/xcodebuild",
        "-workspace",
        str(workspace),
        "-scheme",
        "Nembra Capture",
    ]


class FakeLease:
    def __init__(self) -> None:
        self.events: list[str] = []

    def grant(self, principal: str) -> None:
        self.events.append("grant:" + principal)

    def revoke(self, *, suppress_errors: bool = False) -> None:
        self.events.append("revoke")


class AcceptedRootAbsoluteWorkspaceEscapeRedTeamTests(unittest.TestCase):
    def test_absolute_live_workspace_survives_rebase_and_forced_accepted_root_cwd(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-accepted-root-workspace-escape-") as raw:
            fixture = Path(raw)
            live_repo = fixture / "live"
            accepted_root = fixture / "accepted"
            live_repo.mkdir()
            accepted_root.mkdir()
            live_workspace = live_repo / "NembraCapture.xcworkspace"
            live_workspace.mkdir()

            command = canonical_guarded_command(helper, live_repo, live_workspace)
            rebased = helper._rebase_private_guard_paths(
                command,
                live_repo=live_repo,
                accepted_root=accepted_root,
            )
            frozen_developer = Path(
                "/Library/NembraSelectedXcodeFreeze.fixture/Xcode.app/Contents/Developer"
            )
            selected = helper._replace_selected_xcode(
                rebased,
                frozen_developer=frozen_developer,
                selected_xcodebuild=frozen_developer / "usr/bin/xcodebuild",
            )

            workspace_index = selected.index("-workspace")
            self.assertEqual(selected[workspace_index + 1], str(live_workspace))
            self.assertTrue(Path(selected[workspace_index + 1]).is_absolute())
            with self.assertRaises(ValueError):
                Path(selected[workspace_index + 1]).relative_to(accepted_root)

            observed: dict[str, object] = {}

            def original(
                observed_command,
                *,
                name,
                uid,
                gid,
                baseline_groups,
                environment,
                cwd,
            ):
                observed["command"] = list(observed_command)
                observed["cwd"] = cwd
                return 0

            build_origin = {"_run_exec_bound_build": original}
            lease = FakeLease()
            helper._bind_private_read_lease(
                build_origin,
                lease,
                build_cwd=accepted_root,
            )
            result = build_origin["_run_exec_bound_build"](
                selected,
                name="nembrabuildfixture",
                uid=52000,
                gid=52000,
                baseline_groups=(52000,),
                environment={},
                cwd=live_repo,
            )

            self.assertEqual(result, 0)
            self.assertEqual(observed["cwd"], accepted_root)
            observed_command = observed["command"]
            self.assertIsInstance(observed_command, list)
            observed_workspace_index = observed_command.index("-workspace")
            self.assertEqual(
                observed_command[observed_workspace_index + 1],
                str(live_workspace),
            )
            self.assertEqual(
                lease.events,
                ["grant:nembrabuildfixture", "revoke"],
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
