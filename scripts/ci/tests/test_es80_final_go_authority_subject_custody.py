#!/usr/bin/env python3
"""Current-lineage regressions for Final-GO executable/Git authority custody."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from typing import Callable

MODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_final_go.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_subject_custody", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final-GO issuer")
go = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = go
SPEC.loader.exec_module(go)

FIXTURE_MODULE = Path(__file__).with_name("test_es80_authenticated_stationary_final_go.py")
FIXTURE_SPEC = importlib.util.spec_from_file_location("nembra_final_go_fixture", FIXTURE_MODULE)
if FIXTURE_SPEC is None or FIXTURE_SPEC.loader is None:
    raise RuntimeError("could not load Final-GO canonical fixture")
fixture_module = importlib.util.module_from_spec(FIXTURE_SPEC)
FIXTURE_SPEC.loader.exec_module(fixture_module)
F = fixture_module.F


def raw_git(repo: Path, *args: str, no_replace: bool = False) -> str:
    environment = os.environ.copy()
    if no_replace:
        environment["GIT_NO_REPLACE_OBJECTS"] = "1"
    return subprocess.check_output(
        ["/usr/bin/git", "-C", str(repo), *args],
        text=True,
        env=environment,
    ).strip()


def run_git(repo: Path, *args: str, no_replace: bool = False) -> None:
    environment = os.environ.copy()
    if no_replace:
        environment["GIT_NO_REPLACE_OBJECTS"] = "1"
    subprocess.run(
        ["/usr/bin/git", "-C", str(repo), *args],
        check=True,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class InstallerExecutionSubjectTests(unittest.TestCase):
    def test_verified_installer_cannot_be_replaced_only_for_execution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-installer-subject-") as temporary:
            root = Path(temporary)
            repo = root / "candidate"
            installer = repo / go.INSTALLER
            runbook = repo / go.RUNBOOK
            identity = repo / go.IDENTITY
            installer.parent.mkdir(parents=True)
            runbook.parent.mkdir(parents=True)
            identity.parent.mkdir(parents=True)

            accepted_installer = f'''#!/bin/bash
set -euo pipefail
PROCEDURE_ID="{go.PROC}"
BUNDLE_ID="{go.BUNDLE}"
# NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256
# hmac.compare_digest(actual_digest, expected_digest)
echo "accepted installer must be the executed subject"
exit 97
'''
            installer.write_text(accepted_installer, encoding="utf-8")
            installer.chmod(0o755)
            runbook.write_text(f"PROCEDURE_ID: `{go.PROC}`\n", encoding="utf-8")
            identity.write_text(
                f'static let requiredFieldProcedureIdentifier = "{go.PROC}"\n',
                encoding="utf-8",
            )
            run_git(repo, "init", "-q")
            run_git(repo, "config", "user.name", "nembra-adversarial")
            run_git(repo, "config", "user.email", "nembra-adversarial@invalid.example")
            run_git(repo, "add", ".")
            run_git(repo, "commit", "-q", "-m", "accepted candidate")
            source = raw_git(repo, "rev-parse", "HEAD")
            accepted = go.candidate(repo, source)
            self.assertEqual(accepted["sourceCommitSHA"], source)

            backup = root / "accepted-installer.command"
            backup.write_text(accepted_installer, encoding="utf-8")
            backup.chmod(0o755)
            backup_q = shlex.quote(str(backup))
            malicious = f'''#!/bin/bash
set -euo pipefail
trap '/bin/cp {backup_q} "$0"; /bin/chmod 755 "$0"' EXIT
printf '%s\\n' 'SDK-INTEGRATED CAPTURE LAUNCHED'
'''
            installer.write_text(malicious, encoding="utf-8")
            installer.chmod(0o755)

            device = root / "intended-device.txt"
            token = b"test-device"
            device.write_bytes(token)
            device.chmod(0o600)
            digest = hashlib.sha256(token).hexdigest()

            with self.assertRaises(
                go.GoError,
                msg="Final-GO must execute the already-reviewed installer bytes, not reopen a mutable pathname",
            ):
                go.installer(repo, source, device, digest, "a" * 64)

            self.assertEqual(installer.read_text(encoding="utf-8"), accepted_installer)
            self.assertEqual(raw_git(repo, "status", "--porcelain=v1", "--untracked-files=all"), "")


class ControlPlaneWorktreeCustodyTests(unittest.TestCase):
    def fixture(
        self, root: Path
    ) -> tuple[Path, str, int, Callable[[str], tuple[bytes, dict]]]:
        repo = root / "authority"
        repo.mkdir()
        run_git(repo, "init", "-q")
        run_git(repo, "config", "user.email", "capture-redteam@nembra.invalid")
        run_git(repo, "config", "user.name", "Nembra Capture Red Team")
        required_paths = (
            "scripts/ci/es80_authenticated_stationary_final_go.py",
            "scripts/ci/es80_authenticated_stationary_signed_artifact.py",
            "scripts/ci/es80_today_final_go_publication.py",
            go.AUTH_WORKFLOW_PATH,
            "scripts/ci/tests/test_es80_authenticated_stationary_final_go.py",
        )
        for relative in required_paths:
            destination = repo / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(f"accepted bytes for {relative}\n", encoding="utf-8")
        run_git(repo, "add", ".")
        run_git(repo, "commit", "-qm", "accepted Final-GO fixture")
        source = raw_git(repo, "rev-parse", "HEAD")
        main_sha = "0" * 40
        run_id = 9001
        pr_number = 2638
        branch = "control/v14-auth-stationary-final-go-sol"
        responses = {
            f"/pulls/{pr_number}": {
                "state": "open",
                "draft": False,
                "merged_at": None,
                "head": {"sha": source, "ref": branch, "repo": {"full_name": go.REPO}},
                "base": {"ref": "main"},
            },
            "/branches/main": {"commit": {"sha": main_sha}},
            f"/compare/{main_sha}...{source}": {
                "status": "ahead",
                "merge_base_commit": {"sha": main_sha},
            },
            f"/actions/runs/{run_id}": {
                "name": go.AUTH_WORKFLOW_NAME,
                "path": go.AUTH_WORKFLOW_PATH,
                "head_sha": source,
                "status": "completed",
                "conclusion": "success",
                "event": "push",
                "head_branch": branch,
                "pull_requests": [],
            },
        }

        def fake_get(path: str) -> tuple[bytes, dict]:
            value = responses[path]
            return json.dumps(value).encode("utf-8"), value

        return repo, source, run_id, fake_get

    def test_hidden_control_module_replacement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-control-worktree-") as temporary:
            repo, source, run_id, fake_get = self.fixture(Path(temporary))
            self.assertEqual(go.control_plane(repo, 2638, run_id, fake_get)["sourceCommitSHA"], source)
            target = "scripts/ci/es80_authenticated_stationary_signed_artifact.py"
            run_git(repo, "update-index", "--assume-unchanged", "--", target)
            (repo / target).write_text(
                "def retain_and_reinspect(*args, **kwargs):\n"
                "    return {'authority': 'forged-worktree-module'}\n",
                encoding="utf-8",
            )
            self.assertEqual(raw_git(repo, "status", "--porcelain=v1", "--untracked-files=all"), "")
            self.assertNotEqual(
                raw_git(repo, "hash-object", "--no-filters", "--", target),
                raw_git(repo, "rev-parse", f"HEAD:{target}"),
            )
            with self.assertRaises(go.GoError):
                go.control_plane(repo, 2638, run_id, fake_get)


class GitReplaceCustodyTests(unittest.TestCase):
    def test_candidate_rejects_replace_ref_that_redefines_accepted_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-replace-") as temporary:
            fixture = F(Path(temporary))
            accepted_source = fixture.s
            installer = fixture.repo / go.INSTALLER
            accepted_bytes = installer.read_bytes()
            installer.write_text(
                installer.read_text()
                + "# attacker replacement that still preserves required source markers\n"
            )
            run_git(fixture.repo, "add", go.INSTALLER)
            run_git(fixture.repo, "commit", "-qm", "attacker replacement")
            attacker_source = raw_git(fixture.repo, "rev-parse", "HEAD")
            attacker_blob = raw_git(
                fixture.repo, "rev-parse", f"{attacker_source}:{go.INSTALLER}", no_replace=True
            )
            run_git(fixture.repo, "reset", "--hard", "-q", accepted_source, no_replace=True)
            run_git(fixture.repo, "replace", accepted_source, attacker_source, no_replace=True)
            run_git(fixture.repo, "read-tree", attacker_source, no_replace=True)
            run_git(fixture.repo, "checkout-index", "-a", "-f", no_replace=True)

            self.assertEqual(raw_git(fixture.repo, "rev-parse", "HEAD"), accepted_source)
            self.assertEqual(raw_git(fixture.repo, "status", "--porcelain=v1", "--untracked-files=all"), "")
            self.assertNotEqual(
                raw_git(fixture.repo, "status", "--porcelain=v1", "--untracked-files=all", no_replace=True),
                "",
            )
            self.assertNotEqual(installer.read_bytes(), accepted_bytes)
            self.assertEqual(
                raw_git(fixture.repo, "rev-parse", f"{accepted_source}:{go.INSTALLER}"),
                attacker_blob,
            )
            self.assertNotEqual(
                raw_git(fixture.repo, "rev-parse", f"{accepted_source}:{go.INSTALLER}", no_replace=True),
                attacker_blob,
            )
            with self.assertRaises(go.GoError):
                go.candidate(fixture.repo, accepted_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
