#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_private_runner.py"


def load_runner():
    spec = importlib.util.spec_from_file_location("nembra_private_runner_test", RUNNER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load private signed-field runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SignedFieldArtifactPrivateRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = load_runner()

    def test_adversarial_private_input_self_test(self) -> None:
        self.runner.self_test()

    def test_validate_only_reads_private_file_without_inspector_inputs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-runner-test-") as temporary:
            path = Path(temporary) / "device-id"
            path.write_text("00008101-001234567890001E", encoding="utf-8")
            path.chmod(0o600)

            result = self.runner.main(
                [
                    "--validate-only",
                    "--intended-device-udid-file",
                    str(path),
                ]
            )
            self.assertEqual(result, 0)

    def test_source_keeps_raw_identifier_out_of_environment_and_process_argv(self) -> None:
        source = RUNNER.read_text(encoding="utf-8")
        self.assertNotIn('os.environ', source)
        self.assertNotIn('os.getenv', source)
        self.assertNotIn('subprocess', source)
        self.assertIn('inspector.main(inspector_arguments)', source)
        self.assertIn('O_NOFOLLOW', source)
        self.assertIn('metadata.st_mode & 0o077', source)
        self.assertIn('MAX_IDENTIFIER_BYTES = 128', source)


if __name__ == "__main__":
    unittest.main()
