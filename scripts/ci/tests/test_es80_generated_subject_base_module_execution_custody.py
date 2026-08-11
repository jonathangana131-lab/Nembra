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


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["/usr/bin/git", "-C", str(root), *arguments], text=True
    ).strip()


def initialize_fixture(root: Path) -> tuple[Path, Path]:
    r3 = root / R3_RELATIVE
    base = root / BASE_RELATIVE
    r3.parent.mkdir(parents=True, exist_ok=True)
    r3.write_bytes(R3_SOURCE.read_bytes())
    base.write_text("#!/usr/bin/env python3\nBASE_MARKER = 'accepted'\n", encoding="utf-8")
    subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
    subprocess.run(
        ["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"],
        check=True,
    )
    subprocess.run(
        ["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"],
        check=True,
    )
    subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
    subprocess.run(
        ["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted R3/base fixture"],
        check=True,
    )
    return r3, base


def load_pinned_base(r3: Path, accepted_source: str, accepted_blob: str):
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("r3_loader_fixture", r3)
        if spec is None or spec.loader is None:
            raise AssertionError("could not load R3 fixture")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.PARENT_SOURCE_SHA = accepted_source
        module.PARENT_BASE_BLOB_OID = accepted_blob
        return module._load_base_module()
    finally:
        sys.dont_write_bytecode = previous


class GeneratedSubjectBaseModuleExecutionCustodyTests(unittest.TestCase):
    def test_hidden_base_worktree_replacement_never_executes_from_r3_loader(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-base-module-exec-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "attacker-base-executed"
            r3, base = initialize_fixture(root)
            accepted_source = git(root, "rev-parse", "HEAD")
            accepted_blob = git(root, "rev-parse", f"{accepted_source}:{BASE_RELATIVE}")

            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "update-index", "--assume-unchanged", BASE_RELATIVE],
                check=True,
            )
            base.write_text(
                "#!/usr/bin/env python3\nfrom pathlib import Path\n"
                + f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                + "BASE_MARKER = 'substituted'\n",
                encoding="utf-8",
            )
            current_blob = git(root, "hash-object", "--no-filters", "--", BASE_RELATIVE)
            self.assertNotEqual(current_blob, accepted_blob)
            self.assertEqual(git(root, "status", "--porcelain=v1", "--untracked-files=all"), "")

            loaded = load_pinned_base(r3, accepted_source, accepted_blob)
            self.assertFalse(
                sentinel.exists(),
                "R3 executed mutable authenticated-stationary base worktree bytes before exact parent authority was established",
            )
            self.assertEqual(getattr(loaded, "BASE_MARKER", None), "accepted")

    def test_clean_local_head_retarget_cannot_choose_parent_execution_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-base-head-retarget-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "attacker-head-executed"
            r3, base = initialize_fixture(root)
            accepted_source = git(root, "rev-parse", "HEAD")
            accepted_blob = git(root, "rev-parse", f"{accepted_source}:{BASE_RELATIVE}")

            base.write_text(
                "#!/usr/bin/env python3\nfrom pathlib import Path\n"
                + f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                + "BASE_MARKER = 'retargeted-head'\n",
                encoding="utf-8",
            )
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", BASE_RELATIVE], check=True)
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "commit", "-qm", "attacker retarget commit"],
                check=True,
            )
            self.assertNotEqual(git(root, "rev-parse", "HEAD"), accepted_source)
            self.assertEqual(git(root, "status", "--porcelain=v1", "--untracked-files=all"), "")

            loaded = load_pinned_base(r3, accepted_source, accepted_blob)
            self.assertFalse(
                sentinel.exists(),
                "R3 allowed a clean local HEAD retarget to choose authenticated-stationary parent execution bytes",
            )
            self.assertEqual(getattr(loaded, "BASE_MARKER", None), "accepted")


if __name__ == "__main__":
    unittest.main(verbosity=2)
