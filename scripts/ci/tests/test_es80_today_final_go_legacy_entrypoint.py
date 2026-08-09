#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_record.py"
spec = importlib.util.spec_from_file_location("legacy_final_go_entrypoint", MODULE_PATH)
legacy = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(legacy)


class LegacyFinalGoEntrypointTests(unittest.TestCase):
    def test_legacy_filename_routes_exact_arguments_to_hardened_entrypoint(self):
        completed = mock.Mock(returncode=17)
        with mock.patch.object(legacy.subprocess, "run", return_value=completed) as run:
            result = legacy.main(["--expected-pr-number", "833", "--help"])

        self.assertEqual(result, 17)
        run.assert_called_once()
        command = run.call_args.args[0]
        self.assertEqual(command[0], sys.executable)
        self.assertEqual(
            Path(command[1]),
            MODULE_PATH.with_name("es80_today_final_go_hardened.py"),
        )
        self.assertEqual(command[2:], ["--expected-pr-number", "833", "--help"])
        self.assertIs(run.call_args.kwargs["check"], False)

    def test_legacy_filename_cannot_call_legacy_builder_or_publication_path(self):
        completed = mock.Mock(returncode=2)
        with mock.patch.object(
            legacy,
            "build_final_go_record",
            side_effect=AssertionError("legacy builder must be unreachable from legacy CLI"),
        ) as build, mock.patch.object(
            legacy,
            "publish_record_no_replace",
            side_effect=AssertionError("legacy publisher must be unreachable from legacy CLI"),
        ) as publish, mock.patch.object(
            legacy.subprocess,
            "run",
            return_value=completed,
        ):
            self.assertEqual(legacy.main(["--help"]), 2)

        build.assert_not_called()
        publish.assert_not_called()

    def test_legacy_filename_fails_closed_if_hardened_process_cannot_start(self):
        with mock.patch.object(
            legacy.subprocess,
            "run",
            side_effect=OSError("simulated exec failure"),
        ):
            self.assertEqual(legacy.main(["--help"]), 2)


if __name__ == "__main__":
    unittest.main()
