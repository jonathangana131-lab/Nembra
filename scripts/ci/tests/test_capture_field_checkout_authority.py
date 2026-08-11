#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "Scripts/capture_field_checkout_authority.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("nembra_capture_field_checkout_authority_test", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("field checkout authority helper import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout.strip()


class FieldCheckoutAuthorityTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix="nembra-field-checkout-authority-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name) / "repo"
        root.mkdir()
        git(root, "init", "-q")
        git(root, "config", "user.name", "Nembra Tests")
        git(root, "config", "user.email", "tests@example.invalid")
        source_dir = root / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture"
        source_dir.mkdir(parents=True)
        accepted = source_dir / "Accepted.swift"
        accepted.write_text("public let accepted = true\n", encoding="utf-8")
        git(root, "add", ".")
        git(root, "commit", "-qm", "accepted")
        return load_helper(), root, git(root, "rev-parse", "HEAD")

    def test_clean_tracked_checkout_is_accepted(self) -> None:
        helper, root, sha = self.fixture()
        helper.verify(root, root / ".git", sha)

    def test_info_exclude_cannot_hide_untracked_swift_source(self) -> None:
        helper, root, sha = self.fixture()
        injected = root / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/Injected.swift"
        injected.write_text("public let attackerCompiled = true\n", encoding="utf-8")
        (root / ".git/info/exclude").write_text(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/Injected.swift\n",
            encoding="utf-8",
        )
        with self.assertRaises(helper.CheckoutAuthorityError):
            helper.verify(root, root / ".git", sha)

    def test_raw_blob_audit_rejects_tracked_byte_rewrite(self) -> None:
        helper, root, sha = self.fixture()
        accepted = root / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/Accepted.swift"
        accepted.write_text("public let accepted = false\n", encoding="utf-8")
        with self.assertRaises(helper.CheckoutAuthorityError):
            helper.verify(root, root / ".git", sha)

    def test_delegated_private_and_generated_roots_are_not_false_dirty(self) -> None:
        helper, root, sha = self.fixture()
        (root / "LocalSecrets").mkdir()
        (root / "LocalSecrets/private.txt").write_text("private", encoding="utf-8")
        (root / "Pods").mkdir()
        (root / "Pods/Generated.swift").write_text("generated", encoding="utf-8")
        (root / "NembraCapture.xcworkspace").mkdir()
        (root / "NembraCapture.xcworkspace/contents.xcworkspacedata").write_text("generated", encoding="utf-8")
        (root / "Podfile.lock").write_text("generated", encoding="utf-8")
        helper.verify(root, root / ".git", sha)


if __name__ == "__main__":
    unittest.main(verbosity=2)
