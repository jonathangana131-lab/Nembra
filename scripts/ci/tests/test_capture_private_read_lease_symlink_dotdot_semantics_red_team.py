#!/usr/bin/env python3
"""Exploit-positive oracle for descriptor-bound symlink/.. POSIX resolution semantics."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
HELPER = REPO / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_symlink_dotdot_red_team", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseSymlinkDotDotRedTeamTests(unittest.TestCase):
    def test_pathname_race_plus_symlink_dotdot_can_escape_descriptor_policy(self) -> None:
        helper = load()
        # Anchor beneath the checkout so Darwin does not trip on /var -> /private/var
        # before the intended policy seam is exercised.
        with tempfile.TemporaryDirectory(
            prefix="nembra-held-symlink-dotdot-",
            dir=REPO,
        ) as raw:
            outer = Path(raw).resolve(strict=True)
            repo = outer / "repo"
            subject = repo / "LocalSecrets/TuyaSDK/Build"
            subject.mkdir(parents=True)

            # One inode has an admitted in-subject hard link and an out-of-subject
            # hard link. If the symlink is classified as internal, the later ACL plan
            # can authorize the inode even though POSIX traversal reaches it outside
            # the admitted subject namespace.
            shared = outer / "shared.fixture"
            shared.write_bytes(b"accepted\n")
            internal_payload = subject / "outside.fixture"
            external_payload = subject.parent / "outside.fixture"
            os.link(shared, internal_payload)
            os.link(shared, external_payload)

            # POSIX resolves the intermediate symlink before applying '..':
            #   anchor -> .
            #   escape -> anchor/../outside.fixture
            # therefore escape reaches Build/../outside.fixture, outside subject.
            (subject / "anchor").symlink_to(".", target_is_directory=True)
            escape = subject / "escape"
            escape.symlink_to("anchor/../outside.fixture")
            self.assertEqual(
                escape.resolve(strict=True),
                external_payload.resolve(strict=True),
            )
            self.assertNotEqual(
                escape.resolve(strict=True).parent,
                subject.resolve(strict=True),
            )
            self.assertEqual(
                helper._path_signature(internal_payload),
                helper._path_signature(external_payload),
            )

            # Preserve the #3411 chronology seam: generation B is pathname-visible
            # only while legacy classification runs. The held descriptor remains on A.
            accepted_hold = repo / "LocalSecrets/TuyaSDK/Build.accepted-hold"
            replacement = outer / "replacement-build"
            replacement.mkdir()
            os.link(shared, replacement / "outside.fixture")
            (replacement / "anchor").symlink_to(".", target_is_directory=True)
            (replacement / "escape").symlink_to("outside.fixture")

            original_subject_entries = helper._subject_entries
            raced = False

            def classify_replacement_then_restore(
                path: Path,
                *,
                include_signatures: bool = False,
            ):
                nonlocal raced
                candidate = Path(path)
                if candidate != subject or raced:
                    return original_subject_entries(
                        candidate,
                        include_signatures=include_signatures,
                    )
                subject.rename(accepted_hold)
                replacement.rename(subject)
                try:
                    entries = original_subject_entries(
                        subject,
                        include_signatures=include_signatures,
                    )
                finally:
                    subject.rename(replacement)
                    accepted_hold.rename(subject)
                raced = True
                return entries

            with mock.patch.object(
                helper,
                "_subject_entries",
                side_effect=classify_replacement_then_restore,
            ):
                # EXPLOIT-POSITIVE: the vulnerable product returns a complete plan.
                # A repair should make this call fail closed, turning this oracle red
                # until the validation is rewritten as a permanent negative regression.
                plan = helper._lease_paths(
                    (subject,),
                    repo,
                    include_descriptors=True,
                )

            try:
                self.assertTrue(raced)
                admitted = {entry[0] for entry in plan}
                self.assertIn(subject, admitted)
                self.assertIn(internal_payload, admitted)
                self.assertEqual(
                    escape.resolve(strict=True),
                    external_payload.resolve(strict=True),
                )
            finally:
                for _path, _host_only, _signature, descriptor in reversed(plan):
                    os.close(int(descriptor))


if __name__ == "__main__":
    unittest.main(verbosity=2)
