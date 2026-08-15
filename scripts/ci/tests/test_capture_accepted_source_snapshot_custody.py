#!/usr/bin/env python3
"""Portable regressions for production accepted-source snapshot composition."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "scripts/ci/capture_accepted_source_snapshot_custody.py"


def load():
    spec = importlib.util.spec_from_file_location("nembra_accepted_source_snapshot_custody", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load accepted-source snapshot custody helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureAcceptedSourceSnapshotCustodyTests(unittest.TestCase):
    def test_command_maps_only_live_repo_descendants_and_rejects_embedded_reference(self) -> None:
        helper = load()
        live = Path("/Users/field/Nembra")
        snapshot = Path("/private/tmp/nembra-accepted-source.fixture/source")
        command = [
            "/usr/bin/python3",
            "-I",
            str(live / "Scripts/capture_tuya_private_input_build_guard.py"),
            "--lockfile",
            str(live / "Podfile.lock"),
            "--",
            "/usr/bin/env",
            "DEVELOPER_DIR=/Library/NembraFrozen/Xcode.app/Contents/Developer",
            "/Library/NembraFrozen/Xcode.app/Contents/Developer/usr/bin/xcodebuild",
            "-workspace",
            "NembraCapture.xcworkspace",
            "-derivedDataPath",
            "/Volumes/NembraCaptureBuild/DerivedData",
        ]
        mapped = helper.map_guarded_command(command, live, snapshot)
        self.assertEqual(mapped[2], str(snapshot / "Scripts/capture_tuya_private_input_build_guard.py"))
        self.assertEqual(mapped[4], str(snapshot / "Podfile.lock"))
        self.assertIn("NembraCapture.xcworkspace", mapped)
        self.assertIn("/Volumes/NembraCaptureBuild/DerivedData", mapped)
        self.assertNotIn(str(live), "\0".join(mapped))
        with self.assertRaises(helper.AcceptedSourceSnapshotCustodyError):
            helper.map_guarded_command(
                [
                    str(live / "Scripts/capture_tuya_private_input_build_guard.py"),
                    f"SOME_FLAG=prefix:{live}/Pods",
                ],
                live,
                snapshot,
            )

    def test_snapshot_helper_contract_is_exact(self) -> None:
        helper = load()
        stage = lambda *_args: "c" * 64
        digest = lambda *_args: "c" * 64
        namespace = {
            "SCHEMA_VERSION": 1,
            "GENERATED_SUBJECTS": tuple(Path(value) for value in helper.EXPECTED_GENERATED_SUBJECTS),
            "stage_accepted_build_inputs": stage,
            "generated_manifest_sha256": digest,
        }
        self.assertEqual(helper._require_snapshot_helper(namespace), (stage, digest))
        bad = dict(namespace)
        bad["SCHEMA_VERSION"] = 2
        with self.assertRaises(helper.AcceptedSourceSnapshotCustodyError):
            helper._require_snapshot_helper(bad)

    def test_build_origin_binding_seals_maps_cwd_and_allows_exactly_one_exec(self) -> None:
        helper = load()
        events: list[object] = []
        snapshot = object.__new__(helper.AcceptedSourceSnapshot)
        snapshot.live_repo = Path("/Users/field/Nembra")
        snapshot.snapshot = Path("/private/tmp/nembra-accepted-source.fixture/source")
        snapshot._bound = False
        snapshot._sealed_gid = None
        snapshot.seal = lambda gid: events.append(("seal", gid))

        def original(command, *, name, uid, gid, baseline_groups, environment, cwd):
            events.append(("exec", list(command), name, uid, gid, tuple(baseline_groups), cwd))
            return 17

        build_origin = {"_run_exec_bound_build": original}
        snapshot.bind_build_origin(build_origin)
        wrapped = build_origin["_run_exec_bound_build"]
        command = [
            "/usr/bin/python3",
            "-I",
            "/Users/field/Nembra/Scripts/capture_tuya_private_input_build_guard.py",
            "--",
            "/usr/bin/xcodebuild",
        ]
        result = wrapped(
            command,
            name="nembrabuildfixture",
            uid=52000,
            gid=52000,
            baseline_groups=(52000,),
            environment={},
            cwd=Path("/Users/field/Nembra"),
        )
        self.assertEqual(result, 17)
        self.assertEqual(events[0], ("seal", 52000))
        exec_event = events[1]
        self.assertEqual(exec_event[1][2], str(snapshot.snapshot / "Scripts/capture_tuya_private_input_build_guard.py"))
        self.assertEqual(exec_event[-1], snapshot.snapshot)
        with self.assertRaisesRegex(helper.AcceptedSourceSnapshotCustodyError, "more than one"):
            wrapped(
                command,
                name="nembrabuildfixture",
                uid=52000,
                gid=52000,
                baseline_groups=(52000,),
                environment={},
                cwd=Path("/Users/field/Nembra"),
            )

    def test_stage_scans_absolute_live_checkout_reference_before_exposure(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-source-snapshot-portable-") as temporary:
            root = Path(temporary)
            live = root / "live"
            live.mkdir()
            fake_private_tmp = root / "private-tmp"
            fake_private_tmp.mkdir()
            stage_calls: list[tuple[Path, Path]] = []

            def stage(repo, _source, destination, _expected):
                stage_calls.append((repo, destination))
                destination.mkdir(parents=True)
                (destination / "Scripts").mkdir()
                (destination / "Scripts/capture_tuya_private_input_build_guard.py").write_text("# guard\n")
                (destination / "Podfile.lock").write_text(f"ROOT={live}\n")
                for subject in (
                    "NembraCapture.xcworkspace",
                    "Pods",
                    "LocalSecrets/TuyaSDK",
                    "LocalSecrets/TuyaRuntime",
                ):
                    (destination / subject).mkdir(parents=True, exist_ok=True)
                return "c" * 64

            namespace = {
                "SCHEMA_VERSION": 1,
                "GENERATED_SUBJECTS": tuple(Path(value) for value in helper.EXPECTED_GENERATED_SUBJECTS),
                "stage_accepted_build_inputs": stage,
                "generated_manifest_sha256": lambda *_args: "c" * 64,
            }
            with (
                mock.patch.object(helper, "_require_private_tmp", return_value=fake_private_tmp),
                mock.patch.object(helper, "_require_no_acl", return_value=None),
                self.assertRaisesRegex(helper.AcceptedSourceSnapshotCustodyError, "absolute live-checkout"),
            ):
                helper.AcceptedSourceSnapshot(
                    live_repo=live,
                    source_sha="a" * 40,
                    expected_manifest_sha256="c" * 64,
                    snapshot_helper=namespace,
                )
            self.assertEqual(len(stage_calls), 1)
            self.assertFalse(any(fake_private_tmp.iterdir()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
