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
    def current_commit(self) -> str:
        return wrapper._git_text("rev-parse", "--verify", "HEAD^{commit}")

    def test_execution_bundle_is_selected_from_explicit_exact_commit(self) -> None:
        source_commit = self.current_commit()
        with wrapper.accepted_execution_bundle(source_commit) as bundle:
            self.assertNotEqual(bundle, wrapper.HERE)
            self.assertTrue(bundle.is_dir())
            for relative in wrapper.EXECUTION_SOURCES:
                snapshot = bundle / Path(relative).name
                self.assertTrue(snapshot.is_file())
                blob_id = wrapper._git_text(
                    "rev-parse", "--verify", f"{source_commit}:{relative}"
                )
                expected = wrapper._git_bytes("cat-file", "blob", blob_id)
                self.assertEqual(snapshot.read_bytes(), expected)

    def test_zero_or_noncanonical_source_commit_is_rejected(self) -> None:
        for value in ("0" * 40, "A" * 40, "main", "HEAD", "a" * 39):
            with self.subTest(value=value):
                with self.assertRaises(wrapper.SignerExecutionCustodyError):
                    wrapper._canonical_source_commit(value)

    def test_source_resolution_must_equal_requested_commit(self) -> None:
        requested = "1" * 40
        with mock.patch.object(wrapper, "_git_text", return_value="2" * 40):
            with self.assertRaises(wrapper.SignerExecutionCustodyError):
                wrapper._canonical_source_commit(requested)

    def test_accepted_blob_never_uses_checkout_head_to_select_code(self) -> None:
        source_commit = "1" * 40
        blob_id = wrapper._git_blob_sha(b"accepted helper bytes")
        with mock.patch.object(wrapper, "_canonical_source_commit", return_value=source_commit), \
             mock.patch.object(wrapper, "_git_text", return_value=blob_id) as git_text, \
             mock.patch.object(wrapper, "_git_bytes", return_value=b"accepted helper bytes"):
            self.assertEqual(
                wrapper._accepted_blob(source_commit, wrapper.EXECUTION_SOURCES[1]),
                b"accepted helper bytes",
            )
        requested = git_text.call_args.args[-1]
        self.assertTrue(requested.startswith(f"{source_commit}:"))
        self.assertNotIn("HEAD", requested)

    def test_git_object_hash_mismatch_is_rejected(self) -> None:
        source_commit = "1" * 40
        relative = wrapper.EXECUTION_SOURCES[1]
        with mock.patch.object(wrapper, "_canonical_source_commit", return_value=source_commit), \
             mock.patch.object(wrapper, "_git_text", return_value="a" * 40), \
             mock.patch.object(wrapper, "_git_bytes", return_value=b"not that blob"):
            with self.assertRaises(wrapper.SignerExecutionCustodyError):
                wrapper._accepted_blob(source_commit, relative)

    def test_signed_evidence_must_bind_same_accepted_source_before_signer_launch(self) -> None:
        helper = SimpleNamespace(
            MAX_JSON_BYTES=1024,
            read_exact_file=lambda *_args: b"evidence",
            verify_evidence_bytes=lambda _data: {"sourceCommitSHA": "2" * 40},
        )
        with self.assertRaises(wrapper.SignerExecutionCustodyError):
            wrapper.verify_accepted_evidence_source(
                evidence_helper=helper,
                signed_evidence=Path("/private/evidence.json"),
                accepted_source_commit="1" * 40,
            )

    def test_signed_evidence_matching_accepted_source_is_admitted(self) -> None:
        source = "1" * 40
        helper = SimpleNamespace(
            MAX_JSON_BYTES=1024,
            read_exact_file=lambda *_args: b"evidence",
            verify_evidence_bytes=lambda _data: {"sourceCommitSHA": source},
        )
        wrapper.verify_accepted_evidence_source(
            evidence_helper=helper,
            signed_evidence=Path("/private/evidence.json"),
            accepted_source_commit=source,
        )

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
        signer = Path("/private/snapshot/es80_field_authorization_envelope.py")
        command = wrapper.build_signer_command(
            args,
            {"attemptChallengeSHA256": "b" * 64},
            signer,
        )

        self.assertEqual(command[0], "/usr/bin/python3")
        self.assertEqual(command[1], str(signer))
        self.assertIn("--private-key", command)
        self.assertIn(str(args.private_key), command)
        self.assertNotIn(str(wrapper.HERE / wrapper.SIGNER_BASENAME), command)

    def test_source_has_no_self_selected_head_signer_authority(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('GIT = Path("/usr/bin/git")', source)
        self.assertIn('PYTHON = Path("/usr/bin/python3")', source)
        self.assertIn('"GIT_NO_REPLACE_OBJECTS": "1"', source)
        self.assertIn('"GIT_CONFIG_GLOBAL": "/dev/null"', source)
        self.assertIn('value.add_argument("--accepted-source-commit", required=True)', source)
        self.assertIn('f"{source_commit}:{relative_path}"', source)
        self.assertIn("verify_accepted_evidence_source(", source)
        self.assertIn("with accepted_execution_bundle(accepted_source_commit) as bundle:", source)
        self.assertIn('"PYTHONNOUSERSITE": "1"', source)
        self.assertIn('"PYTHONPATH": ""', source)
        self.assertNotIn('"HEAD:{relative_path}"', source)
        self.assertNotIn('"HEAD^{commit}"', source)
        self.assertNotIn("sys.executable,", source)
        self.assertNotIn("str(SIGNER)", source)
        self.assertNotIn("env=os.environ", source)


if __name__ == "__main__":
    unittest.main()
