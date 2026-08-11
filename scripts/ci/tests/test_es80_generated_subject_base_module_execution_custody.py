#!/usr/bin/env python3
"""Regression for R3 loading its authenticated-stationary base from accepted Git bytes."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
R3_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
R3_RELATIVE = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
BASE_RELATIVE = "scripts/ci/es80_authenticated_stationary_final_go.py"


class GeneratedSubjectBaseModuleExecutionCustodyTests(unittest.TestCase):
    def test_hidden_base_worktree_replacement_never_executes_from_r3_loader(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-base-module-exec-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "attacker-base-executed"
            r3 = root / R3_RELATIVE
            base = root / BASE_RELATIVE
            r3.parent.mkdir(parents=True, exist_ok=True)
            r3.write_bytes(R3_SOURCE.read_bytes())
            base.write_text("#!/usr/bin/env python3\nBASE_MARKER = 'accepted'\n", encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted R3/base fixture"], check=True)
            accepted_source = subprocess.check_output(["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
            accepted_blob = subprocess.check_output(["/usr/bin/git", "-C", str(root), "rev-parse", f"{accepted_source}:{BASE_RELATIVE}"], text=True).strip()
            subprocess.run(["/usr/bin/git", "-C", str(root), "update-index", "--assume-unchanged", BASE_RELATIVE], check=True)
            base.write_text(
                "#!/usr/bin/env python3\nfrom pathlib import Path\n"
                + f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                + "BASE_MARKER = 'substituted'\n",
                encoding="utf-8",
            )
            current_blob = subprocess.check_output(["/usr/bin/git", "-C", str(root), "hash-object", "--no-filters", "--", BASE_RELATIVE], text=True).strip()
            self.assertNotEqual(current_blob, accepted_blob)
            self.assertEqual(subprocess.check_output(["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"], text=True), "")
            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("r3_loader_fixture", r3)
                if spec is None or spec.loader is None:
                    self.fail("could not load R3 fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                module.PARENT_MODULE_BLOB_OID = accepted_blob
                loaded = module._load_base_module()
            finally:
                sys.dont_write_bytecode = previous
            self.assertFalse(sentinel.exists(), "R3 executed mutable authenticated-stationary base worktree bytes before exact parent authority was established")
            self.assertEqual(getattr(loaded, "BASE_MARKER", None), "accepted")


if __name__ == "__main__":
    unittest.main(verbosity=2)
