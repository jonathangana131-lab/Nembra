#!/usr/bin/env python3
"""Portable descriptor-transport and symlink policy regressions for private read lease."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_read_lease_descriptor_transport", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseDescriptorTransportTests(unittest.TestCase):
    def test_acl_tools_explicitly_inherit_only_the_pinned_descriptor(self) -> None:
        helper = load()
        completed = type("Completed", (), {"returncode": 0, "stdout": "", "stderr": ""})()
        with mock.patch.object(helper.subprocess, "run", return_value=completed) as run:
            helper._acl_listing(41)
            self.assertEqual(run.call_args.kwargs["pass_fds"], (41,))
            self.assertEqual(run.call_args.args[0][-1], "/dev/fd/41")
        with mock.patch.object(helper.subprocess, "run", return_value=completed) as run:
            helper._chmod_acl(43, "+a", "nembrabuildfixture allow read")
            self.assertEqual(run.call_args.kwargs["pass_fds"], (43,))
            self.assertEqual(run.call_args.args[0][-1], "/dev/fd/43")

    def test_preexisting_build_principal_acl_is_rejected_by_classifier(self) -> None:
        helper = load()
        self.assertTrue(
            helper._principal_already_present(
                " 0: nembrabuildfixture allow read\n", "nembrabuildfixture"
            )
        )
        self.assertFalse(
            helper._principal_already_present(
                " 0: otheruser allow read\n", "nembrabuildfixture"
            )
        )

    def test_internal_symlink_is_admitted_but_escaping_symlink_fails_closed(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-private-read-symlink-") as temporary:
            outer = Path(temporary)
            outer.chmod(0o711)
            repo = outer / "repo"
            repo.mkdir(mode=0o755)
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)
            payload = subject / "payload.bin"
            payload.write_bytes(b"fixture\n")
            (subject / "internal.bin").symlink_to("payload.bin")
            helper._lease_paths((subject,), repo)

            outside = repo / "outside.bin"
            outside.write_bytes(b"outside\n")
            (subject / "escape.bin").symlink_to(outside)
            with self.assertRaises(helper.SelectedXcodeBuildOrchestratorError):
                helper._lease_paths((subject,), repo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
