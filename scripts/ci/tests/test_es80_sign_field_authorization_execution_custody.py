import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "es80_sign_field_authorization_from_rendezvous.py"
SPEC = importlib.util.spec_from_file_location("signer_wrapper", SCRIPT)
assert SPEC and SPEC.loader
wrapper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wrapper)


class SignerExecutionCustodyTests(unittest.TestCase):
    def test_live_checkout_matches_every_git_object_before_snapshot(self) -> None:
        with wrapper.accepted_execution_bundle() as bundle:
            self.assertNotEqual(bundle, wrapper.HERE)
            self.assertTrue(bundle.is_dir())
            for relative in wrapper.EXECUTION_SOURCES:
                snapshot = bundle / relative
                self.assertTrue(snapshot.is_file())
                blob_id = wrapper._git_text("rev-parse", "--verify", f"HEAD:{relative}")
                expected = wrapper._git_bytes("cat-file", "blob", blob_id)
                self.assertEqual(snapshot.read_bytes(), expected)
                self.assertFalse(
                    (bundle / Path(relative).name).exists(),
                    "accepted execution sources must retain repository-relative layout",
                )

    def test_mutated_checkout_is_rejected_before_execution_bundle(self) -> None:
        relative = wrapper.EXECUTION_SOURCES[1]
        blob_id = "a" * 40
        accepted = b"accepted helper bytes"
        with mock.patch.object(wrapper, "_git_text", return_value=blob_id), \
             mock.patch.object(wrapper, "_git_bytes", return_value=accepted), \
             mock.patch.object(wrapper, "_read_exact_worktree", return_value=b"mutated"):
            with self.assertRaises(wrapper.SignerExecutionCustodyError):
                wrapper._accepted_blob(relative)

    def test_git_object_hash_mismatch_is_rejected(self) -> None:
        relative = wrapper.EXECUTION_SOURCES[1]
        with mock.patch.object(wrapper, "_git_text", return_value="a" * 40), \
             mock.patch.object(wrapper, "_git_bytes", return_value=b"not that blob"):
            with self.assertRaises(wrapper.SignerExecutionCustodyError):
                wrapper._accepted_blob(relative)

    def test_signer_command_uses_frozen_signer_and_system_python(self) -> None:
        args = SimpleNamespace(
            signed_evidence=Path("/private/evidence.json"),
            private_key=Path("/private/key.pem"),
            openssl=Path("/usr/bin/openssl"),
            output=Path("/private/envelope.json"),
            authorization_id="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            issued_at="2026-08-20T01:00:00Z",
            not_before="2026-08-20T01:00:00Z",
            expires_at="2026-08-20T01:05:00Z",
        )
        signer = Path("/private/snapshot/scripts/ci/es80_field_authorization_envelope.py")
        command = wrapper.build_signer_command(
            args,
            {"attemptChallengeSHA256": "b" * 64},
            signer,
        )

        self.assertEqual(command[0], "/usr/bin/python3")
        self.assertEqual(command[1], str(signer))
        self.assertIn("--private-key", command)
        self.assertIn(str(args.private_key), command)
        self.assertNotIn(str(wrapper.HERE / wrapper.SIGNER_RELATIVE_PATH.name), command)

    def test_source_has_no_mutable_signer_launch_or_environment_inheritance(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('GIT = Path("/usr/bin/git")', source)
        self.assertIn('PYTHON = Path("/usr/bin/python3")', source)
        self.assertIn('"GIT_NO_REPLACE_OBJECTS": "1"', source)
        self.assertIn('"GIT_CONFIG_GLOBAL": "/dev/null"', source)
        self.assertIn('"cat-file", "blob"', source)
        self.assertIn("_git_blob_sha(blob) != blob_id", source)
        self.assertIn("worktree != blob", source)
        self.assertIn("with accepted_execution_bundle() as bundle:", source)
        self.assertIn("bundle / SIGNER_RELATIVE_PATH", source)
        self.assertIn("bundle / RENDEZVOUS_RELATIVE_PATH", source)
        self.assertIn('"PYTHONNOUSERSITE": "1"', source)
        self.assertIn('"PYTHONPATH": ""', source)
        self.assertNotIn("sys.executable,", source)
        self.assertNotIn("str(SIGNER)", source)
        self.assertNotIn("env=os.environ", source)


if __name__ == "__main__":
    unittest.main()
