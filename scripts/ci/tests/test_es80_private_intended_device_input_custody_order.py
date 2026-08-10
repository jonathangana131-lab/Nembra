#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock

MODULE_PATH = pathlib.Path(__file__).parents[1] / "es80_private_intended_device_input.py"
spec = importlib.util.spec_from_file_location("private_input", MODULE_PATH)
private_input = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(private_input)


class PrivateInputCustodyOrderTests(unittest.TestCase):
    def private_dir(self, root: pathlib.Path) -> pathlib.Path:
        path = root / "private"
        path.mkdir(mode=0o700)
        path.chmod(0o700)
        return path

    def test_cli_prompts_only_after_fresh_output_inode_exists(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            output = self.private_dir(root) / "device.udid"
            prompt_observed = False

            def prompt(_: str) -> str:
                nonlocal prompt_observed
                prompt_observed = True
                self.assertTrue(
                    output.exists(),
                    "identifier prompt ran before the descriptor-bound output inode existed",
                )
                return "00008101ABCDEF0123456789"

            with mock.patch.object(private_input.getpass, "getpass", side_effect=prompt):
                self.assertEqual(private_input.main(["--output-path", str(output)]), 0)

            self.assertTrue(prompt_observed)
            self.assertEqual(output.read_bytes(), b"00008101ABCDEF0123456789")

    def test_helper_byte_ceiling_matches_accepted_preflight_contract(self):
        self.assertEqual(
            private_input._MAX_IDENTIFIER_BYTES,
            128,
            "helper can admit a value the accepted preflight deterministically rejects",
        )
        self.assertEqual(len(private_input._validate_identifier("A" * 128)), 128)
        with self.assertRaises(private_input.PrivateInputError):
            private_input._validate_identifier("A" * 129)


if __name__ == "__main__":
    unittest.main()
