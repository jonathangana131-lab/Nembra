#!/usr/bin/env python3
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

CI_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CI_ROOT))

RUNTIME_MATERIALIZER_PATH = CI_ROOT / "es80_materialize_field_authorization_signer_runtime.py"
RUNNER_PATH = CI_ROOT / "es80_run_materialized_field_authorization_signer.py"
SIGNER_PATH = CI_ROOT / "es80_field_authorization_envelope.py"
RENDEZVOUS_PATH = CI_ROOT / "es80_field_authorization_rendezvous.py"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runtime_materializer = load(RUNTIME_MATERIALIZER_PATH, "runtime_materializer")
runner = load(RUNNER_PATH, "materialized_runner")
signer = load(SIGNER_PATH, "fixture_signer")
rendezvous_helper = load(RENDEZVOUS_PATH, "fixture_rendezvous")


class MaterializedFieldAuthorizationSignerRuntimeTests(unittest.TestCase):
    def _head(self) -> str:
        return runtime_materializer.base._git_text("rev-parse", "--verify", "HEAD^{commit}")

    def _temporary_directory(self, prefix: str):
        return tempfile.TemporaryDirectory(prefix=prefix, dir=Path.home())

    def _materialize(self, parent: Path) -> dict[str, object]:
        return runtime_materializer.materialize(self._head(), parent / "bundle")

    def _write_signing_fixture(self, root: Path) -> dict[str, object]:
        openssl = Path("/usr/bin/openssl")
        key = root / "ephemeral-private-key.pem"
        public = root / "ephemeral-public-key.pem"
        subprocess.run(
            [str(openssl), "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)],
            check=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        os.chmod(key, 0o600)
        subprocess.run(
            [str(openssl), "pkey", "-in", str(key), "-pubout", "-out", str(public)],
            check=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        digest = lambda character: character * 64
        evidence = signer.artifact_evidence.canonical_json_bytes({
            "schemaVersion": signer.artifact_evidence.SCHEMA_VERSION,
            "evidenceKind": "signed-field-artifact-digests-not-authorization",
            "procedureID": signer.PROCEDURE_ID,
            "bundleIdentifier": signer.BUNDLE_ID,
            "sourceCommitSHA": "1" * 40,
            "buildIdentifier": "materialized-runner-test",
            "buildInstanceID": "12345678-1234-abcd-8def-123456789abc",
            "signedInstallableKind": "ipa",
            "signedInstallableSHA256": digest("2"),
            "executableSHA256": digest("3"),
            "infoPlistSHA256": digest("4"),
            "tuyaDependencyLockSHA256": digest("5"),
            "externalBuildRecordSHA256": digest("6"),
            "finalGORecordSHA256": digest("7"),
            "intendedDevicePseudonymSHA256": digest("8"),
        })
        evidence_path = root / "signed-evidence.json"
        evidence_path.write_bytes(evidence)

        issued = "2026-08-20T12:00:00Z"
        expires = "2026-08-20T12:05:00Z"
        started_ms = int(
            datetime(2026, 8, 20, 12, 0, tzinfo=timezone.utc).timestamp() * 1000
        )
        challenge = digest("9")
        rendezvous = rendezvous_helper.canonical_json_bytes({
            "schema": rendezvous_helper.SCHEMA,
            "version": rendezvous_helper.SCHEMA_VERSION,
            "procedureID": rendezvous_helper.PROCEDURE_ID,
            "attemptChallengeSHA256": challenge,
            "attemptStartedAtUnixMilliseconds": started_ms,
            "authorizationMustExpireByUnixMilliseconds": (
                started_ms + rendezvous_helper.MAX_AUTHORIZATION_LIFETIME_MILLISECONDS
            ),
        })
        rendezvous_path = root / "rendezvous.json"
        rendezvous_path.write_bytes(rendezvous)
        return {
            "openssl": openssl,
            "key": key,
            "public": public,
            "evidence": evidence_path,
            "rendezvous": rendezvous_path,
            "issued": issued,
            "expires": expires,
            "challenge": challenge,
            "authorization_id": "87654321-4321-4321-8321-cba987654321",
        }

    def _runner_arguments(
        self,
        result: dict[str, object],
        fixture: dict[str, object],
        output: Path,
    ) -> list[str]:
        return [
            "--bundle-directory", str(result["outputDirectory"]),
            "--expected-source-commit", str(result["sourceCommitSHA"]),
            "--expected-manifest-sha256", str(result["manifestSHA256"]),
            "--rendezvous", str(fixture["rendezvous"]),
            "--signed-evidence", str(fixture["evidence"]),
            "--private-key", str(fixture["key"]),
            "--openssl", str(fixture["openssl"]),
            "--authorization-id", str(fixture["authorization_id"]),
            "--issued-at", str(fixture["issued"]),
            "--not-before", str(fixture["issued"]),
            "--expires-at", str(fixture["expires"]),
            "--output", str(output),
        ]

    def test_runtime_bundle_materializes_runner_as_first_exact_git_object(self) -> None:
        with self._temporary_directory("nembra-materialized-runtime-") as raw:
            parent = Path(raw)
            result = self._materialize(parent)
            bundle = Path(str(result["outputDirectory"]))
            manifest_path = bundle / runtime_materializer.base.MANIFEST_NAME
            manifest = json.loads(manifest_path.read_bytes())
            paths = tuple(entry["path"] for entry in manifest["executionSources"])

            self.assertEqual(paths, runtime_materializer.EXECUTION_SOURCES)
            self.assertEqual(paths, runner.REQUIRED_EXECUTION_SOURCES)
            self.assertEqual(Path(str(result["runnerPath"])), bundle / runner.RUNNER_RELATIVE_PATH)
            self.assertEqual(stat.S_IMODE((bundle / runner.RUNNER_RELATIVE_PATH).stat().st_mode), 0o400)
            self.assertEqual(stat.S_IMODE((bundle / "scripts/ci").stat().st_mode), 0o700)

    def test_runtime_materializer_has_no_private_key_surface(self) -> None:
        source = RUNTIME_MATERIALIZER_PATH.read_text(encoding="utf-8")
        self.assertNotIn('add_argument("--private-key"', source)
        self.assertNotIn("--private-key", source)
        self.assertNotIn("private_key", source)
        self.assertEqual(
            runtime_materializer.EXECUTION_SOURCES[0],
            "scripts/ci/es80_run_materialized_field_authorization_signer.py",
        )

    def test_checkout_runner_cannot_masquerade_as_materialized_bundle(self) -> None:
        source = RUNNER_PATH.read_text(encoding="utf-8")
        fake_manifest = "a" * 64
        with self.assertRaises(runner.MaterializedSignerRunnerError):
            runner.verify_materialized_bundle(
                runner.RUNNER_RELATIVE_PATH.parents[2] if len(runner.RUNNER_RELATIVE_PATH.parents) > 2 else CI_ROOT,
                self._head(),
                fake_manifest,
            )
        main = source[source.index("def main("):]
        self.assertLess(
            main.index("verify_materialized_bundle("),
            main.index("_load_verified_module("),
        )
        self.assertNotIn("_load_module(", main)

    def test_wrong_manifest_hash_fails_before_signer_launch(self) -> None:
        with self._temporary_directory("nembra-materialized-hash-") as raw:
            parent = Path(raw)
            result = self._materialize(parent)
            fixture = self._write_signing_fixture(parent)
            output = parent / "must-not-exist.json"
            command = [
                "/usr/bin/python3", str(result["runnerPath"]),
                "--bundle-directory", str(result["outputDirectory"]),
                "--expected-source-commit", str(result["sourceCommitSHA"]),
                "--expected-manifest-sha256", "0" * 64,
                "--rendezvous", str(fixture["rendezvous"]),
                "--signed-evidence", str(fixture["evidence"]),
                "--private-key", str(parent / "nonexistent-private-key.pem"),
                "--openssl", str(fixture["openssl"]),
                "--authorization-id", str(fixture["authorization_id"]),
                "--issued-at", str(fixture["issued"]),
                "--not-before", str(fixture["issued"]),
                "--expires-at", str(fixture["expires"]),
                "--output", str(output),
            ]
            completed = subprocess.run(
                command,
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(completed.returncode, 2)
            self.assertIn("manifest SHA-256 mismatch", completed.stderr)
            self.assertNotIn("private key", completed.stderr.lower())
            self.assertFalse(output.exists())

    def test_post_verification_source_swaps_cannot_change_executed_bytes(self) -> None:
        with self._temporary_directory("nembra-materialized-postverify-swap-") as raw:
            parent = Path(raw)
            result = self._materialize(parent)
            fixture = self._write_signing_fixture(parent)
            output = parent / "authorization-envelope.json"
            marker = parent / "MUTATED_SOURCE_EXECUTED"
            bundle = Path(str(result["outputDirectory"]))
            materialized_runner = load(
                Path(str(result["runnerPath"])),
                "materialized_runner_postverify_swap",
            )
            original_verify = materialized_runner.verify_materialized_bundle

            def verify_then_swap(*args):
                verified = original_verify(*args)
                malicious = (
                    "from pathlib import Path\n"
                    f"Path({str(marker)!r}).write_text('executed', encoding='utf-8')\n"
                    "raise RuntimeError('mutated materialized source executed')\n"
                ).encode("utf-8")
                for relative in (
                    materialized_runner.WRAPPER_RELATIVE_PATH,
                    materialized_runner.RENDEZVOUS_RELATIVE_PATH,
                    materialized_runner.SIGNER_RELATIVE_PATH,
                    materialized_runner.EVIDENCE_RELATIVE_PATH,
                ):
                    path = bundle / relative
                    os.chmod(path, 0o600)
                    path.write_bytes(malicious)
                    os.chmod(path, 0o400)
                return verified

            materialized_runner.verify_materialized_bundle = verify_then_swap
            stdout = io.StringIO()
            stderr = io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                returncode = materialized_runner.main(
                    self._runner_arguments(result, fixture, output)
                )

            self.assertEqual(returncode, 0, stderr.getvalue())
            self.assertIn(
                "SIGNED_BY_VERIFIED_MATERIALIZED_BUNDLE_NOT_PHYSICAL_GO",
                stdout.getvalue(),
            )
            self.assertTrue(output.is_file())
            self.assertFalse(marker.exists())

    def test_ephemeral_key_end_to_end_uses_only_materialized_signing_stack(self) -> None:
        with self._temporary_directory("nembra-materialized-e2e-") as raw:
            parent = Path(raw)
            result = self._materialize(parent)
            fixture = self._write_signing_fixture(parent)
            output = parent / "authorization-envelope.json"
            command = [
                "/usr/bin/python3", str(result["runnerPath"]),
                *self._runner_arguments(result, fixture, output),
            ]
            completed = subprocess.run(
                command,
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("SIGNED_BY_VERIFIED_MATERIALIZED_BUNDLE_NOT_PHYSICAL_GO", completed.stdout)
            self.assertTrue(output.is_file())

            bundle = Path(str(result["outputDirectory"]))
            verified_signer = bundle / runner.SIGNER_RELATIVE_PATH
            verify = subprocess.run(
                [
                    "/usr/bin/python3", str(verified_signer),
                    "--verify", str(output),
                    "--signed-evidence", str(fixture["evidence"]),
                    "--public-key", str(fixture["public"]),
                    "--openssl", str(fixture["openssl"]),
                    "--authorization-id", str(fixture["authorization_id"]),
                    "--attempt-challenge-sha256", str(fixture["challenge"]),
                    "--now", "2026-08-20T12:01:00Z",
                ],
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd=bundle,
                env={
                    "PATH": "/usr/bin:/bin",
                    "HOME": "/tmp",
                    "LC_ALL": "C",
                    "PYTHONNOUSERSITE": "1",
                    "PYTHONPATH": "",
                },
            )
            self.assertEqual(verify.returncode, 0, verify.stderr)
            self.assertIn("VERIFIED_SINGLE_ATTEMPT", verify.stdout)


if __name__ == "__main__":
    unittest.main()
