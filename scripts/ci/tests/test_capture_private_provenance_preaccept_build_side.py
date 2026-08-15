#!/usr/bin/env python3
"""Portable production regression for preaccepted private Tuya provenance.

Synthetic private bytes only. The field bootstrap must require externally reviewed
lock + private-provenance digests before dependency resolution, and a changed private
input must not be able to re-mint field-build authority under the old reviewed digest.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[3]
BOOTSTRAP = REPO / "Scripts/bootstrap_capture_tuya_sdk.sh"
PROVENANCE = REPO / "Scripts/capture_tuya_private_input_provenance.py"
LOCK_LABEL = "Podfile.lock SHA-256:"
PROVENANCE_LABEL = "Private-input provenance-record SHA-256:"


def _annotation_text(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _emit_stage_failure(stage: str, result: subprocess.CompletedProcess[str]) -> None:
    detail = f"rc={result.returncode}; stdout={result.stdout!r}; stderr={result.stderr!r}"
    print(f"::error title={stage}::{_annotation_text(detail)}", flush=True)


class PrivateProvenancePreacceptBuildSideTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nembra-private-preaccept-")
        self.root = Path(self.temp.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        shutil.copy2(BOOTSTRAP, scripts / BOOTSTRAP.name)
        shutil.copy2(PROVENANCE, scripts / PROVENANCE.name)

        (self.root / "Podfile").write_text("platform :ios, '17.0'\n", encoding="utf-8")
        (self.root / "NembraCapture.xcodeproj").mkdir()

        sdk = self.root / "LocalSecrets/TuyaSDK"
        build = sdk / "Build"
        runtime = self.root / "LocalSecrets/TuyaRuntime"
        identity = runtime / "Sources/NembraTuyaPrivateConfig"
        build.mkdir(parents=True)
        identity.mkdir(parents=True)
        (sdk / "ThingSmartCryption.podspec").write_text(
            "security-podspec-v1\n", encoding="utf-8"
        )
        (build / "libThingSmartCryption.a").write_bytes(b"synthetic-security-A")
        (runtime / "NembraTuyaPrivateConfig.podspec").write_text(
            "identity-podspec-v1\n", encoding="utf-8"
        )
        self.identity = identity / "NembraTuyaPrivateIdentity.swift"
        self.identity.write_text('let appKey = "SYNTHETIC-A"\n', encoding="utf-8")

        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.pod_marker = self.root / ".pod-invoked"
        pod = self.fake_bin / "pod"
        pod.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            f"printf invoked > {self.pod_marker!s}\n"
            "/bin/mkdir -p NembraCapture.xcworkspace\n"
            "/bin/cat > Podfile.lock <<'EOF'\n"
            "PODS:\n"
            "  - ThingSmartHomeKit (7.8.0)\n"
            "  - ThingSmartBusinessExtensionKit (7.8.0)\n"
            "EOF\n",
            encoding="utf-8",
        )
        pod.chmod(0o755)

        # The production script uses Darwin `stat -f %Lp` only to re-check the
        # provenance record mode. The helper itself establishes 0600; this shim
        # lets the rest of the exact bootstrap contract execute on Ubuntu.
        fake_stat = self.fake_bin / "stat"
        fake_stat.write_text("#!/bin/bash\nprintf '600\\n'\n", encoding="utf-8")
        fake_stat.chmod(0o755)

        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.fake_bin}:/usr/bin:/bin"
        self.env.pop("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256", None)
        self.env.pop("NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_PROVENANCE_SHA256", None)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_bootstrap(
        self,
        *arguments: str,
        lock_digest: str | None = None,
        provenance_digest: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = self.env.copy()
        if lock_digest is not None:
            env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = lock_digest
        if provenance_digest is not None:
            env["NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_PROVENANCE_SHA256"] = provenance_digest
        return subprocess.run(
            ["/bin/bash", str(self.root / "Scripts/bootstrap_capture_tuya_sdk.sh"), *arguments],
            cwd=self.root,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

    @staticmethod
    def digest_from(output: str, label: str) -> str:
        match = re.search(rf"^\s*{re.escape(label)}\s*([0-9a-f]{{64}})\s*$", output, re.MULTILINE)
        if match is None:
            raise AssertionError(f"candidate output missing {label!r}: {output!r}")
        return match.group(1)

    def require_success(self, stage: str, result: subprocess.CompletedProcess[str]) -> None:
        if result.returncode != 0:
            _emit_stage_failure(stage, result)
        self.assertEqual(result.returncode, 0, f"{stage}: {result.stderr}")

    def test_missing_private_digest_fails_before_pod_resolution(self) -> None:
        result = self.run_bootstrap(lock_digest="1" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_PROVENANCE_SHA256", result.stderr)
        self.assertFalse(self.pod_marker.exists(), "dependency resolver ran before private acceptance")

    def test_reviewed_private_digest_rejects_resnapshot_of_mutated_input(self) -> None:
        review_a = self.run_bootstrap("--resolve-lock-for-review")
        self.require_success("review-A", review_a)
        self.assertIn("NOT FIELD BUILD AUTHORITY", review_a.stdout)
        lock_a = self.digest_from(review_a.stdout, LOCK_LABEL)
        provenance_a = self.digest_from(review_a.stdout, PROVENANCE_LABEL)
        self.assertTrue(self.pod_marker.exists())

        accepted_a = self.run_bootstrap(lock_digest=lock_a, provenance_digest=provenance_a)
        self.require_success("accepted-A", accepted_a)
        self.assertIn("Preaccepted private Tuya input provenance matched", accepted_a.stdout)

        # Keep the dependency lock byte-identical and change only one ignored
        # private build input. Bootstrap may recompute a candidate record, but it
        # must not promote that new record under the old externally reviewed digest.
        self.identity.write_text('let appKey = "SYNTHETIC-B"\n', encoding="utf-8")
        rejected_b = self.run_bootstrap(lock_digest=lock_a, provenance_digest=provenance_a)
        if rejected_b.returncode == 0 or "does not match the preaccepted provenance-record SHA-256" not in rejected_b.stderr:
            _emit_stage_failure("rejected-B", rejected_b)
        self.assertNotEqual(rejected_b.returncode, 0)
        self.assertIn(
            "does not match the preaccepted provenance-record SHA-256",
            rejected_b.stderr,
        )
        self.assertNotIn("NEXT BUILD RULE:", rejected_b.stdout)

        review_b = self.run_bootstrap("--resolve-lock-for-review")
        self.require_success("review-B", review_b)
        lock_b = self.digest_from(review_b.stdout, LOCK_LABEL)
        provenance_b = self.digest_from(review_b.stdout, PROVENANCE_LABEL)
        if lock_b != lock_a or provenance_b == provenance_a:
            detail = (
                f"lockA={lock_a} lockB={lock_b} "
                f"provenanceA={provenance_a} provenanceB={provenance_b}"
            )
            print(f"::error title=review-B-digests::{_annotation_text(detail)}", flush=True)
        self.assertEqual(lock_b, lock_a)
        self.assertNotEqual(provenance_b, provenance_a)

    def test_source_contract_requires_both_reviewed_digests_before_resolution(self) -> None:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        lock_requirement = ': "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?'
        provenance_requirement = ': "${NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_PROVENANCE_SHA256:?'
        resolver = "pod install --repo-update"
        provenance_compare = '[[ "$PRIVATE_PROVENANCE_SHA256" == "$ACCEPTED_PRIVATE_PROVENANCE_SHA256" ]]'
        for marker in (
            lock_requirement,
            provenance_requirement,
            "DEPENDENCY + PRIVATE-INPUT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY",
            provenance_compare,
        ):
            self.assertIn(marker, source)
        self.assertLess(source.index(lock_requirement), source.index(resolver))
        self.assertLess(source.index(provenance_requirement), source.index(resolver))
        self.assertLess(source.index(provenance_compare), source.index("NEXT BUILD RULE:"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
