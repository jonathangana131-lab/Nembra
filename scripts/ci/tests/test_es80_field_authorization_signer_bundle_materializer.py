#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "es80_materialize_field_authorization_signer_bundle.py"
SPEC = importlib.util.spec_from_file_location("prekey_signer_bundle_materializer", SCRIPT)
assert SPEC and SPEC.loader
materializer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(materializer)


class FieldAuthorizationSignerBundleMaterializerTests(unittest.TestCase):
    def _head(self) -> str:
        return materializer._git_text("rev-parse", "--verify", "HEAD^{commit}")

    def _parent(self, prefix: str):
        return tempfile.TemporaryDirectory(prefix=prefix, dir=Path.home())

    def test_materializes_exact_git_blobs_without_private_key_input(self) -> None:
        head = self._head()
        with self._parent("nembra-prekey-bundle-") as raw:
            output = Path(raw) / "bundle"
            result = materializer.materialize(head, output)

            self.assertEqual(result["status"], "MATERIALIZED_PREKEY_BUNDLE_NOT_AUTHORITY")
            self.assertEqual(result["sourceCommitSHA"], head)
            self.assertEqual(Path(result["outputDirectory"]), output)

            manifest_path = output / materializer.MANIFEST_NAME
            manifest_raw = manifest_path.read_bytes()
            manifest = json.loads(manifest_raw)
            self.assertEqual(manifest_raw, materializer.canonical_json_bytes(manifest))
            self.assertEqual(manifest["sourceCommitSHA"], head)
            self.assertEqual(manifest["authority"], materializer.AUTHORITY)
            self.assertIs(manifest["privateKeyMaterialized"], False)
            self.assertIs(manifest["physicalExperimentAuthority"], False)
            self.assertEqual(
                result["manifestSHA256"],
                materializer.hashlib.sha256(manifest_raw).hexdigest(),
            )

            entries = {item["path"]: item for item in manifest["executionSources"]}
            self.assertEqual(tuple(entries), materializer.EXECUTION_SOURCES)
            for relative in materializer.EXECUTION_SOURCES:
                with self.subTest(relative=relative):
                    path = output / relative
                    self.assertTrue(path.is_file())
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o400)
                    self.assertEqual(path.stat().st_uid, os.geteuid())
                    self.assertEqual(path.stat().st_nlink, 1)
                    blob_id = materializer._git_text(
                        "rev-parse", "--verify", f"{head}:{relative}"
                    )
                    accepted = materializer._git_bytes("cat-file", "blob", blob_id)
                    self.assertEqual(path.read_bytes(), accepted)
                    self.assertEqual(entries[relative]["gitBlobSHA1"], blob_id)
                    self.assertEqual(
                        entries[relative]["sha256"],
                        materializer.hashlib.sha256(accepted).hexdigest(),
                    )
                    self.assertEqual(entries[relative]["byteCount"], len(accepted))

            self.assertEqual(stat.S_IMODE(manifest_path.stat().st_mode), 0o400)
            self.assertEqual(stat.S_IMODE((output / "scripts").stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((output / "scripts/ci").stat().st_mode), 0o700)

    def test_materializer_surface_has_no_private_key_argument(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn('add_argument("--private-key"', source)
        self.assertNotIn("--private-key", source)
        self.assertNotIn("private_key", source)
        self.assertIn('value.add_argument("--source-commit", required=True)', source)
        self.assertIn('value.add_argument("--output-directory", type=Path, required=True)', source)

    def test_source_commit_must_be_explicit_full_lowercase_sha(self) -> None:
        head = self._head()
        with self.assertRaises(materializer.PreKeyBundleError):
            materializer._require_exact_source_commit("HEAD")
        with self.assertRaises(materializer.PreKeyBundleError):
            materializer._require_exact_source_commit(head.upper())
        self.assertEqual(materializer._require_exact_source_commit(head), head)

    def test_existing_output_is_never_replaced(self) -> None:
        head = self._head()
        with self._parent("nembra-prekey-existing-") as raw:
            output = Path(raw) / "bundle"
            output.mkdir(mode=0o700)
            sentinel = output / "sentinel"
            sentinel.write_text("keep", encoding="utf-8")
            with self.assertRaises(materializer.PreKeyBundleError):
                materializer.materialize(head, output)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_output_inside_repository_is_rejected_before_creation(self) -> None:
        head = self._head()
        output = materializer.REPOSITORY_ROOT / "scripts" / "nembra-prekey-must-not-exist"
        self.assertFalse(output.exists())
        with self.assertRaises(materializer.PreKeyBundleError):
            materializer.materialize(head, output)
        self.assertFalse(output.exists())

    def test_symlinked_output_ancestor_is_rejected(self) -> None:
        head = self._head()
        with self._parent("nembra-prekey-link-") as raw:
            root = Path(raw)
            real_parent = root / "real"
            real_parent.mkdir(mode=0o700)
            linked_parent = root / "linked"
            linked_parent.symlink_to(real_parent, target_is_directory=True)
            with self.assertRaises(materializer.PreKeyBundleError):
                materializer.materialize(head, linked_parent / "bundle")
            self.assertFalse((real_parent / "bundle").exists())

    def test_git_blob_identity_mismatch_fails_closed(self) -> None:
        with mock.patch.object(materializer, "_git_text", return_value="a" * 40), \
             mock.patch.object(materializer, "_git_bytes", return_value=b"wrong accepted bytes"):
            with self.assertRaises(materializer.PreKeyBundleError):
                materializer._accepted_blob("b" * 40, materializer.EXECUTION_SOURCES[0])

    def test_git_lookup_is_absolute_and_config_isolated(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('GIT = Path("/usr/bin/git")', source)
        self.assertIn('"GIT_NO_REPLACE_OBJECTS": "1"', source)
        self.assertIn('"GIT_CONFIG_NOSYSTEM": "1"', source)
        self.assertIn('"GIT_CONFIG_GLOBAL": "/dev/null"', source)
        self.assertIn('"cat-file", "blob"', source)
        self.assertNotIn("os.environ.copy", source)
        self.assertNotIn("env=os.environ", source)


if __name__ == "__main__":
    unittest.main()
