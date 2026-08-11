#!/usr/bin/env python3
"""Expected-red attack: clean child Git bytes must not outrun exact parent authority."""
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


class GeneratedSubjectParentLiveBaseBindingTests(unittest.TestCase):
    def test_clean_child_parent_override_never_executes_before_exact_parent_binding(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-parent-live-binding-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "unaccepted-parent-executed"
            r3 = root / R3_RELATIVE
            base = root / BASE_RELATIVE
            r3.parent.mkdir(parents=True, exist_ok=True)
            r3.write_bytes(R3_SOURCE.read_bytes())
            base.write_text("#!/usr/bin/env python3\nBASE_MARKER = 'accepted-parent'\n", encoding="utf-8")

            git = ["/usr/bin/git", "-C", str(root)]
            subprocess.run([*git, "init", "-q"], check=True)
            subprocess.run([*git, "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run([*git, "config", "user.name", "Nembra Capture QA"], check=True)
            subprocess.run([*git, "add", "."], check=True)
            subprocess.run([*git, "commit", "-qm", "accepted parent fixture"], check=True)
            accepted_parent = subprocess.check_output([*git, "rev-parse", "HEAD"], text=True).strip()
            accepted_blob = subprocess.check_output([*git, "rev-parse", f"{accepted_parent}:{BASE_RELATIVE}"], text=True).strip()

            base.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\n"
                "BASE_MARKER = 'unaccepted-child-override'\n",
                encoding="utf-8",
            )
            subprocess.run([*git, "add", BASE_RELATIVE], check=True)
            subprocess.run([*git, "commit", "-qm", "unaccepted child override"], check=True)
            child_head = subprocess.check_output([*git, "rev-parse", "HEAD"], text=True).strip()
            child_blob = subprocess.check_output([*git, "rev-parse", f"{child_head}:{BASE_RELATIVE}"], text=True).strip()
            self.assertNotEqual(child_blob, accepted_blob)
            self.assertEqual(
                subprocess.check_output([*git, "status", "--porcelain=v1", "--untracked-files=all"], text=True),
                "",
            )

            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("r3_parent_binding_fixture", r3)
                if spec is None or spec.loader is None:
                    self.fail("could not load R3 fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                try:
                    loaded = module._load_base_module(parent_source=accepted_parent)
                except TypeError:
                    loaded = module._load_base_module()
            finally:
                sys.dont_write_bytecode = previous

            self.assertFalse(
                sentinel.exists(),
                "R3 executed a clean child-committed parent override before binding execution to the exact accepted parent source/blob",
            )
            self.assertEqual(getattr(loaded, "BASE_MARKER", None), "accepted-parent")


if __name__ == "__main__":
    unittest.main(verbosity=2)
