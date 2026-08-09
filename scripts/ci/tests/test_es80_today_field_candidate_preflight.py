#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import replace
import importlib.util
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_field_candidate_preflight.py"
spec = importlib.util.spec_from_file_location("field_candidate_preflight", MODULE_PATH)
preflight = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = preflight
spec.loader.exec_module(preflight)


class FakeRunner:
    def __init__(
        self,
        expected_sha: str,
        *,
        dirty: bool = False,
        xcode_version: str = "Xcode 27.0",
        raw_mismatch: str | None = None,
    ):
        self.expected_sha = expected_sha
        self.dirty = dirty
        self.xcode_version = xcode_version
        self.raw_mismatch = raw_mismatch
        self.calls: list[tuple[tuple[str, ...], Path | None, dict[str, str]]] = []

    def __call__(self, argv, cwd, env):
        args = tuple(argv)
        self.calls.append((args, cwd, dict(env)))
        if args == ("/usr/bin/git", "rev-parse", "--verify", "HEAD^{commit}"):
            return preflight.CommandResult(0, self.expected_sha + "\n", "")
        if (
            len(args) == 4
            and args[:3] == ("/usr/bin/git", "rev-parse", "--verify")
            and args[3].startswith(self.expected_sha + ":")
        ):
            return preflight.CommandResult(0, "d" * 40 + "\n", "")
        if args == ("/usr/bin/git", "status", "--porcelain=v1", "--untracked-files=all"):
            return preflight.CommandResult(0, "?? local-secret.txt\n" if self.dirty else "", "")
        if args[:2] == ("/usr/bin/git", "ls-tree"):
            relative_path = args[-1]
            return preflight.CommandResult(
                0,
                f"100755 blob {'d' * 40}\t{relative_path}\n",
                "",
            )
        if args[:4] == ("/usr/bin/git", "hash-object", "--no-filters", "--"):
            relative_path = args[-1]
            blob = "e" * 40 if relative_path == self.raw_mismatch else "d" * 40
            return preflight.CommandResult(0, blob + "\n", "")
        if args == ("/usr/bin/xcode-select", "-p"):
            return preflight.CommandResult(0, "/Applications/Xcode-beta.app/Contents/Developer\n", "")
        if args == ("/usr/bin/xcodebuild", "-version"):
            return preflight.CommandResult(0, self.xcode_version + "\nBuild version 27A000\n", "")
        raise AssertionError(args)


class FieldCandidatePreflightTests(unittest.TestCase):
    SOURCE = "a" * 40
    TEAM = "ABCDE12345"
    PRIVATE_UDID = "00008110-PRIVATE-DEVICE-SUBJECT"

    def make_inputs(
        self,
        root: Path,
        *,
        udid_mode: int = 0o600,
        udid_suffix: str = "",
    ):
        repo = root / "repo"
        (repo / "scripts" / "ci").mkdir(parents=True)
        for relative in (preflight.TODAY_WRAPPER, preflight.CANONICAL_PRODUCER):
            path = repo / relative
            path.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            path.chmod(0o755)

        export_options = root / "private-export-options.plist"
        with export_options.open("wb") as handle:
            plistlib.dump({"method": "development"}, handle)

        udid = root / "private-intended-device.txt"
        udid.write_text(self.PRIVATE_UDID + udid_suffix, encoding="utf-8")
        udid.chmod(udid_mode)

        return preflight.Inputs(
            source_repo=repo,
            expected_source_sha=self.SOURCE,
            development_team=self.TEAM,
            export_options_plist=export_options,
            intended_device_udid_file=udid,
            allow_provisioning_updates="0",
        )

    def test_ready_report_is_explicitly_non_authorizing_and_secret_minimizing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root)
            runner = FakeRunner(self.SOURCE)
            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=runner,
                system_name="Darwin",
            )

            encoded = json.dumps(report, sort_keys=True)
            self.assertEqual(exit_code, 0)
            self.assertEqual(report["status"], preflight.READY_STATUS)
            self.assertEqual(report["physicalExperimentAuthorization"], "not-granted")
            self.assertEqual(report["researchCompileMode"], "private-today-v1")
            self.assertEqual(report["researchCompileCondition"], "NEMBRA_ES80_TODAY_RESEARCH")
            self.assertNotIn(self.TEAM, encoded)
            self.assertNotIn(self.PRIVATE_UDID, encoded)
            self.assertNotIn(str(inputs.intended_device_udid_file), encoded)
            self.assertNotIn(str(inputs.export_options_plist), encoded)

            xcode_calls = [call for call in runner.calls if call[0][0] == "/usr/bin/xcodebuild"]
            self.assertEqual(len(xcode_calls), 1)
            self.assertEqual(
                xcode_calls[0][2].get("DEVELOPER_DIR"),
                "/Applications/Xcode-beta.app/Contents/Developer",
            )

    def test_dirty_invocation_checkout_fails_closed_without_echoing_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root)
            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=FakeRunner(self.SOURCE, dirty=True),
                system_name="Darwin",
            )

        self.assertEqual(exit_code, 2)
        self.assertEqual(report["status"], preflight.NOT_READY_STATUS)
        self.assertIn("invocation-checkout-not-clean", report["problems"])
        self.assertNotIn("local-secret.txt", json.dumps(report))
        self.assertEqual(report["physicalExperimentAuthorization"], "not-granted")

    def test_executable_handoff_bytes_must_match_frozen_git_blobs(self):
        cases = (
            (
                preflight.TODAY_WRAPPER,
                "todayWrapperMatchesFrozenGitBlob",
                "today-wrapper-checkout-bytes-do-not-match-frozen-git-blob",
            ),
            (
                preflight.CANONICAL_PRODUCER,
                "canonicalProducerMatchesFrozenGitBlob",
                "canonical-producer-checkout-bytes-do-not-match-frozen-git-blob",
            ),
        )
        for relative_path, check_name, problem in cases:
            with self.subTest(relative_path=relative_path):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    inputs = self.make_inputs(root)
                    report, exit_code = preflight.evaluate_preflight(
                        inputs,
                        runner=FakeRunner(self.SOURCE, raw_mismatch=relative_path),
                        system_name="Darwin",
                    )

                self.assertEqual(exit_code, 2)
                self.assertEqual(report["status"], preflight.NOT_READY_STATUS)
                self.assertFalse(report["checks"][check_name])
                self.assertIn(problem, report["problems"])
                self.assertEqual(report["physicalExperimentAuthorization"], "not-granted")

    def test_private_udid_file_must_be_mode_0600(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root, udid_mode=0o644)
            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=FakeRunner(self.SOURCE),
                system_name="Darwin",
            )

        self.assertEqual(exit_code, 2)
        self.assertFalse(report["checks"]["privateIntendedDeviceInput"])
        self.assertIn("private-intended-device-input-invalid", report["problems"])
        self.assertNotIn(self.PRIVATE_UDID, json.dumps(report))

    def test_trailing_newline_is_rejected_to_match_frozen_private_runner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root, udid_suffix="\n")
            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=FakeRunner(self.SOURCE),
                system_name="Darwin",
            )

        self.assertEqual(exit_code, 2)
        self.assertFalse(report["checks"]["privateIntendedDeviceInput"])
        self.assertIn("private-intended-device-input-invalid", report["problems"])
        self.assertNotIn(self.PRIVATE_UDID, json.dumps(report))

    def test_repository_contained_udid_file_is_rejected_to_match_frozen_private_runner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root)
            repository_private = inputs.source_repo / "private-intended-device.txt"
            repository_private.write_text(self.PRIVATE_UDID, encoding="utf-8")
            repository_private.chmod(0o600)
            inputs = replace(inputs, intended_device_udid_file=repository_private)

            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=FakeRunner(self.SOURCE),
                system_name="Darwin",
            )

        self.assertEqual(exit_code, 2)
        self.assertFalse(report["checks"]["privateIntendedDeviceInput"])
        self.assertIn("private-intended-device-input-invalid", report["problems"])
        self.assertNotIn(self.PRIVATE_UDID, json.dumps(report))
        self.assertNotIn(str(repository_private), json.dumps(report))

    def test_symlinked_udid_parent_is_rejected_to_match_frozen_private_runner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root)
            real_parent = root / "real-private-parent"
            real_parent.mkdir()
            private_file = real_parent / "private-intended-device.txt"
            private_file.write_text(self.PRIVATE_UDID, encoding="utf-8")
            private_file.chmod(0o600)
            symlink_parent = root / "symlink-private-parent"
            try:
                symlink_parent.symlink_to(real_parent, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")
            inputs = replace(
                inputs,
                intended_device_udid_file=symlink_parent / "private-intended-device.txt",
            )

            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=FakeRunner(self.SOURCE),
                system_name="Darwin",
            )

        self.assertEqual(exit_code, 2)
        self.assertFalse(report["checks"]["privateIntendedDeviceInput"])
        self.assertIn("private-intended-device-input-invalid", report["problems"])
        self.assertNotIn(self.PRIVATE_UDID, json.dumps(report))
        self.assertNotIn(str(symlink_parent), json.dumps(report))

    def test_non_xcode_27_selection_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root)
            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=FakeRunner(self.SOURCE, xcode_version="Xcode 26.4"),
                system_name="Darwin",
            )

        self.assertEqual(exit_code, 2)
        self.assertFalse(report["checks"]["selectedXcode27"])
        self.assertIn("selected-xcode-is-not-xcode-27", report["problems"])

    def test_non_macos_host_never_attempts_xcode_and_never_reports_ready(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = self.make_inputs(root)
            runner = FakeRunner(self.SOURCE)
            report, exit_code = preflight.evaluate_preflight(
                inputs,
                runner=runner,
                system_name="Linux",
            )

        self.assertEqual(exit_code, 2)
        self.assertFalse(report["checks"]["macOSSigningSurface"])
        self.assertFalse(report["checks"]["selectedXcode27"])
        self.assertFalse(any(call[0][0] == "/usr/bin/xcodebuild" for call in runner.calls))
        self.assertEqual(report["physicalExperimentAuthorization"], "not-granted")


if __name__ == "__main__":
    unittest.main()