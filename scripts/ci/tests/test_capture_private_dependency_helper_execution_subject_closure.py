#!/usr/bin/env python3
"""Accepted closure for private dependency-custody helper execution authority."""

from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[3]
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
ADAPTER = ROOT / "Scripts/capture_tuya_private_dependency_resolution_guard.py"
CANONICAL_GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
PROVENANCE = ROOT / "Scripts/capture_tuya_private_input_provenance.py"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


def load_adapter():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_dependency_helper_execution_closure",
        ADAPTER,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("dependency-resolution adapter import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateDependencyHelperExecutionClosureTests(unittest.TestCase):
    def test_bootstrap_executes_captured_adapter_and_snapshot_bytes(self) -> None:
        source = BOOTSTRAP.read_text(encoding="utf-8")
        adapter_oid = git_blob_oid(ADAPTER.read_bytes())
        provenance_oid = git_blob_oid(PROVENANCE.read_bytes())

        self.assertIn(
            f'PRIVATE_INPUT_RESOLUTION_GUARD_GIT_BLOB_OID="{adapter_oid}"',
            source,
        )
        self.assertIn(
            f'PROVENANCE_HELPER_GIT_BLOB_OID="{provenance_oid}"',
            source,
        )
        self.assertIn('RESOLUTION_GUARD_SOURCE="${RESOLUTION_GUARD_CAPTURE%$\'\\001\'}"', source)
        self.assertIn("printf '%s' \"$RESOLUTION_GUARD_SOURCE\" | /usr/bin/python3 -I -", source)
        self.assertNotIn('/usr/bin/python3 -I "$PRIVATE_INPUT_RESOLUTION_GUARD"', source)
        self.assertIn('/usr/bin/python3 -I -c "$PROVENANCE_SOURCE" snapshot', source)
        self.assertNotIn('/usr/bin/python3 -I "$PROVENANCE_HELPER" snapshot', source)
        self.assertIn('--canonical-guard-source "$PRIVATE_INPUT_BUILD_GUARD"', source)
        self.assertIn('--provenance-helper-source "$PROVENANCE_HELPER"', source)

    def test_transient_adapter_replacement_cannot_change_captured_execution_bytes(self) -> None:
        accepted = ADAPTER.read_bytes()
        accepted_oid = git_blob_oid(accepted)
        with tempfile.TemporaryDirectory(prefix="nembra-private-adapter-captured-") as temporary:
            sandbox = Path(temporary)
            subject = sandbox / ADAPTER.name
            marker = sandbox / "attacker-ran.txt"
            subject.write_bytes(accepted)

            captured = subject.read_bytes()
            self.assertEqual(git_blob_oid(captured), accepted_oid)

            subject.write_text(
                textwrap.dedent(
                    f"""
                    from pathlib import Path
                    Path({str(marker)!r}).write_text("executed\\n", encoding="utf-8")
                    raise SystemExit(0)
                    """
                ).lstrip(),
                encoding="utf-8",
            )

            completed = subprocess.run(
                [sys.executable, "-I", "-", "--help"],
                input=captured,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            self.assertFalse(marker.exists(), "mutable adapter pathname executed after accepted capture")

    def test_exact_adapter_loads_exact_canonical_guard_and_pinned_provenance(self) -> None:
        adapter = load_adapter()
        self.assertEqual(
            adapter._CANONICAL_GUARD_GIT_BLOB_OID,
            git_blob_oid(CANONICAL_GUARD.read_bytes()),
        )
        self.assertEqual(
            adapter._PROVENANCE_HELPER_GIT_BLOB_OID,
            git_blob_oid(PROVENANCE.read_bytes()),
        )
        guard = adapter._load_guard(CANONICAL_GUARD, PROVENANCE, ROOT)
        self.assertTrue(hasattr(guard, "PrivateInputs"))
        self.assertTrue(callable(guard.run_guarded_build))
        self.assertEqual(
            guard._PINNED_PROVENANCE_GIT_BLOB_OID,
            git_blob_oid(PROVENANCE.read_bytes()),
        )
        self.assertEqual(
            getattr(guard.provenance, "SCHEMA", None),
            "nembra-capture-tuya-dependencies-v2",
        )

    def test_substituted_canonical_guard_is_rejected_before_execution(self) -> None:
        adapter = load_adapter()
        with tempfile.TemporaryDirectory(prefix="nembra-private-canonical-substitution-") as temporary:
            sandbox = Path(temporary)
            checkout = sandbox / "repo"
            scripts = checkout / "Scripts"
            scripts.mkdir(parents=True)
            marker = sandbox / "malicious-guard-ran.txt"
            malicious = scripts / CANONICAL_GUARD.name
            malicious.write_text(
                textwrap.dedent(
                    f"""
                    from pathlib import Path
                    Path({str(marker)!r}).write_text("executed\\n", encoding="utf-8")
                    """
                ).lstrip(),
                encoding="utf-8",
            )
            provenance = scripts / PROVENANCE.name
            provenance.write_bytes(PROVENANCE.read_bytes())

            with self.assertRaises(adapter.ResolutionGuardError):
                adapter._load_guard(malicious, provenance, checkout)
            self.assertFalse(marker.exists(), "rejected canonical guard bytes were executed")

    def test_substituted_provenance_helper_is_rejected_before_canonical_execution(self) -> None:
        adapter = load_adapter()
        with tempfile.TemporaryDirectory(prefix="nembra-private-provenance-substitution-") as temporary:
            sandbox = Path(temporary)
            checkout = sandbox / "repo"
            scripts = checkout / "Scripts"
            scripts.mkdir(parents=True)
            canonical = scripts / CANONICAL_GUARD.name
            canonical.write_bytes(CANONICAL_GUARD.read_bytes())
            marker = sandbox / "malicious-provenance-ran.txt"
            provenance = scripts / PROVENANCE.name
            provenance.write_text(
                textwrap.dedent(
                    f"""
                    from pathlib import Path
                    Path({str(marker)!r}).write_text("executed\\n", encoding="utf-8")
                    """
                ).lstrip(),
                encoding="utf-8",
            )

            with self.assertRaises(adapter.ResolutionGuardError):
                adapter._load_guard(canonical, provenance, checkout)
            self.assertFalse(marker.exists(), "rejected provenance helper bytes were executed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
