import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"
SPEC = importlib.util.spec_from_file_location("signed_artifact_evidence", SCRIPT)
assert SPEC and SPEC.loader
evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evidence)


class SignedFieldArtifactPathCustodyTests(unittest.TestCase):
    def test_canonical_direct_subject_remains_readable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-evidence-custody-") as raw:
            root = Path(raw).resolve(strict=True)
            subject = root / "signed-evidence.json"
            expected = b"canonical evidence fixture\n"
            subject.write_bytes(expected)

            self.assertEqual(
                evidence.read_exact_file(subject, "signed artifact evidence", 4096),
                expected,
            )

    def test_final_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-evidence-custody-") as raw:
            root = Path(raw).resolve(strict=True)
            subject = root / "signed-evidence.json"
            subject.write_bytes(b"canonical evidence fixture\n")
            alias = root / "alias.json"
            alias.symlink_to(subject)

            with self.assertRaises(evidence.EvidenceError):
                evidence.read_exact_file(alias, "signed artifact evidence", 4096)

    def test_symlink_ancestor_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-evidence-custody-") as raw:
            root = Path(raw).resolve(strict=True)
            real = root / "real"
            real.mkdir()
            subject = real / "signed-evidence.json"
            subject.write_bytes(b"canonical evidence fixture\n")
            linked = root / "linked"
            linked.symlink_to(real, target_is_directory=True)

            with self.assertRaises(evidence.EvidenceError):
                evidence.read_exact_file(
                    linked / subject.name,
                    "signed artifact evidence",
                    4096,
                )

    def test_dotdot_path_is_rejected_instead_of_reinterpreted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-evidence-custody-") as raw:
            root = Path(raw).resolve(strict=True)
            subject = root / "signed-evidence.json"
            subject.write_bytes(b"canonical evidence fixture\n")
            noncanonical = root / "unused" / ".." / subject.name

            with self.assertRaises(evidence.EvidenceError):
                evidence.read_exact_file(noncanonical, "signed artifact evidence", 4096)

    def test_source_traverses_each_ancestor_descriptor_relative(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("def _open_no_follow_file", source)
        self.assertIn("dir_fd=directory_fd", source)
        self.assertIn('os.O_RDONLY | directory_only | no_follow | close_on_exec', source)
        self.assertIn('os.O_RDONLY | no_follow | close_on_exec', source)
        self.assertIn("os.open not in os.supports_dir_fd", source)
        self.assertNotIn("candidate.is_symlink()", source)


if __name__ == "__main__":
    unittest.main()
