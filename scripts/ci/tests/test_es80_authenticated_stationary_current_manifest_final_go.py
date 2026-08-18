#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import hashlib
from pathlib import Path
import subprocess
import tempfile
import types
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/ci/es80_authenticated_stationary_current_manifest_final_go.py"

spec = importlib.util.spec_from_file_location("current_manifest_control", MODULE_PATH)
assert spec and spec.loader
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)

DIGEST = hashlib.sha256((("a" * 64) + "\n").encode()).hexdigest()
OTHER_DIGEST = hashlib.sha256((("b" * 64) + "\n").encode()).hexdigest()


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["/usr/bin/git", "-C", str(root), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout.strip()


def write_candidate(root: Path, *, helper_seed: str = "a" * 64, valid_consumer: bool = True) -> str:
    helper = root / control.SNAPSHOT_HELPER_PATH
    helper.parent.mkdir(parents=True, exist_ok=True)
    helper.write_text(
        "from pathlib import Path\n"
        "import hashlib\n"
        "SCHEMA_VERSION = 1\n"
        "GENERATED_SUBJECTS = (\n"
        "    Path('Podfile.lock'), Path('NembraCapture.xcworkspace'), Path('Pods'),\n"
        "    Path('LocalSecrets/TuyaSDK'), Path('LocalSecrets/TuyaRuntime'),\n"
        ")\n"
        f"def canonical_generated_manifest(root, source): return b'{helper_seed}\\n'\n"
        "def generated_manifest_sha256(root, source): "
        "return hashlib.sha256(canonical_generated_manifest(root, source)).hexdigest()\n",
        encoding="utf-8",
    )

    bootstrap = root / control.BOOTSTRAP_PATH
    bootstrap.parent.mkdir(parents=True, exist_ok=True)
    bootstrap.write_text(
        "#!/bin/bash\n"
        f': "${{{control.CURRENT_ENV_KEY}:?review required}}"\n'
        f'HELPER="scripts/ci/capture_accepted_build_input_snapshot.py"\n'
        'SOURCE_SHA="0123456789012345678901234567890123456789"\n'
        'GENERATED_MANIFEST_SHA256="$(/usr/bin/python3 -I "$HELPER" manifest --root "$PWD" '
        '--source-sha "$SOURCE_SHA" | /usr/bin/shasum -a 256)"\n'
        'ACCEPTED_GENERATED_MANIFEST_SHA256="$GENERATED_MANIFEST_SHA256"\n',
        encoding="utf-8",
    )

    installer = root / control.INSTALLER_PATH
    installer.parent.mkdir(parents=True, exist_ok=True)
    if valid_consumer:
        installer.write_text(
            "#!/bin/bash\n"
            f': "${{{control.CURRENT_ENV_KEY}:?review required}}"\n'
            "python3 scripts/ci/capture_selected_xcode_build_orchestrator.py "
            f'{control.INSTALLER_OPTION} "${{{control.CURRENT_ENV_KEY}}}"\n',
            encoding="utf-8",
        )
    else:
        installer.write_text("#!/bin/bash\ntrue\n", encoding="utf-8")

    if not (root / ".git").exists():
        git(root, "init")
        git(root, "config", "user.email", "nembra-test@example.invalid")
        git(root, "config", "user.name", "Nembra Test")
    git(root, "add", ".")
    git(root, "commit", "-m", "candidate")
    return git(root, "rev-parse", "HEAD")


class FakeParent(types.SimpleNamespace):
    def __init__(self, *, legacy_digest: str = DIGEST):
        super().__init__()
        self.ENV_KEY = control.LEGACY_ENV_KEY
        self.install_calls = 0
        self.legacy_digest = legacy_digest

        def derive(repo: Path, source: str) -> str:
            return self.legacy_digest

        self.derive_generated_manifest_sha256 = derive

        def build(*, candidate_repo: Path, source: str, **kwargs):
            digest = self.derive_generated_manifest_sha256(candidate_repo, source)
            self.install_calls += 1
            return {
                "physicalResultCollected": False,
                "acceptedGeneratedBuildInputManifestSHA256": digest,
                "generatedBuildInputManifestAuthority": {
                    "installerEnvironmentKey": self.ENV_KEY,
                    "installerConsumerIntegrated": False,
                    "physicalAuthorityCreated": False,
                },
            }

        self.build = build


class CurrentManifestConsumerControlTests(unittest.TestCase):
    def test_exact_blob_preserves_HEAD_revision_sentinel(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "subject.txt").write_text("accepted\n", encoding="utf-8")
            git(root, "init")
            git(root, "config", "user.email", "nembra-test@example.invalid")
            git(root, "config", "user.name", "Nembra Test")
            git(root, "add", "subject.txt")
            git(root, "commit", "-m", "subject")
            blob, payload = control._exact_blob(root, "HEAD", "subject.txt")
            self.assertRegex(blob, r"^[0-9a-f]{40,64}$")
            self.assertEqual(payload, b"accepted\n")

    def test_current_consumer_key_and_candidate_helper_are_bound_before_promotion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = write_candidate(root)
            parent = FakeParent()
            record = control.build(candidate_repo=root, source=source, parent_module=parent)

            authority = record["generatedBuildInputManifestAuthority"]
            self.assertEqual(authority["installerEnvironmentKey"], control.CURRENT_ENV_KEY)
            self.assertTrue(authority["installerConsumerIntegrated"])
            self.assertEqual(
                authority["consumerContract"],
                "nembra-capture-current-generated-manifest-consumer-v1",
            )
            self.assertRegex(authority["currentCandidateSnapshotHelperGitBlob"], r"^[0-9a-f]{40,64}$")
            self.assertFalse(authority["physicalAuthorityCreated"])
            self.assertEqual(parent.install_calls, 1)
            self.assertEqual(parent.ENV_KEY, control.LEGACY_ENV_KEY)

    def test_missing_current_installer_transport_fails_before_parent_side_effect(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = write_candidate(root, valid_consumer=False)
            parent = FakeParent()
            with self.assertRaises(control.CurrentManifestConsumerFinalGoError):
                control.build(candidate_repo=root, source=source, parent_module=parent)
            self.assertEqual(parent.install_calls, 0)
            self.assertEqual(parent.ENV_KEY, control.LEGACY_ENV_KEY)

    def test_candidate_helper_semantic_drift_fails_before_parent_side_effect(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = write_candidate(root, helper_seed="b" * 64)
            parent = FakeParent(legacy_digest=DIGEST)
            with self.assertRaises(control.CurrentManifestConsumerFinalGoError):
                control.build(candidate_repo=root, source=source, parent_module=parent)
            self.assertEqual(parent.install_calls, 0)
            self.assertEqual(parent.ENV_KEY, control.LEGACY_ENV_KEY)

    def test_legacy_environment_key_is_rejected_in_candidate_consumer(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = write_candidate(root)
            installer = root / control.INSTALLER_PATH
            installer.write_text(
                installer.read_text(encoding="utf-8")
                + f'echo "${{{control.LEGACY_ENV_KEY}:-}}"\n',
                encoding="utf-8",
            )
            git(root, "add", control.INSTALLER_PATH)
            git(root, "commit", "-m", "legacy key")
            source = git(root, "rev-parse", "HEAD")
            parent = FakeParent()
            with self.assertRaises(control.CurrentManifestConsumerFinalGoError):
                control.build(candidate_repo=root, source=source, parent_module=parent)
            self.assertEqual(parent.install_calls, 0)


if __name__ == "__main__":
    unittest.main()
