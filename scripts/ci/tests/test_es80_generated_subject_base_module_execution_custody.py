#!/usr/bin/env python3
"""Regression for R3 authenticated-stationary parent execution custody."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import subprocess, tempfile, unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"
SPEC = importlib.util.spec_from_file_location("generated_subject_final_go", MODULE_PATH)
if SPEC is None or SPEC.loader is None: raise RuntimeError("could not load generated-subject Final GO")
GO = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(GO)
BASE_RELATIVE = GO.BASE_MODULE_PATH

class BaseModuleExecutionCustodyTests(unittest.TestCase):
    def test_hidden_base_worktree_replacement_is_not_executed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-sealed-base-") as temporary:
            root=Path(temporary).resolve(strict=True); sentinel=root/"unexpected-worktree-parent-execution"; base=root/BASE_RELATIVE
            base.parent.mkdir(parents=True,exist_ok=True)
            base.write_text("#!/usr/bin/env python3\nBASE_MARKER = 'accepted'\n",encoding="utf-8")
            subprocess.run(["/usr/bin/git","-C",str(root),"init","-q"],check=True)
            subprocess.run(["/usr/bin/git","-C",str(root),"config","user.email","capture@nembra.invalid"],check=True)
            subprocess.run(["/usr/bin/git","-C",str(root),"config","user.name","Nembra Capture QA"],check=True)
            subprocess.run(["/usr/bin/git","-C",str(root),"add","."],check=True)
            subprocess.run(["/usr/bin/git","-C",str(root),"commit","-qm","accepted parent fixture"],check=True)
            source=subprocess.check_output(["/usr/bin/git","-C",str(root),"rev-parse","HEAD"],text=True).strip()
            accepted_blob=subprocess.check_output(["/usr/bin/git","-C",str(root),"rev-parse",f"{source}:{BASE_RELATIVE}"],text=True).strip()
            subprocess.run(["/usr/bin/git","-C",str(root),"update-index","--assume-unchanged",BASE_RELATIVE],check=True)
            base.write_text("#!/usr/bin/env python3\nfrom pathlib import Path\n"+f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\nBASE_MARKER = 'substituted'\n",encoding="utf-8")
            self.assertEqual(subprocess.check_output(["/usr/bin/git","-C",str(root),"status","--porcelain=v1","--untracked-files=all"],text=True),"")
            control={"parentSourceCommitSHA":source,"gitBlobs":{BASE_RELATIVE:accepted_blob}}
            loaded=GO._load_base_module(root,control,GO._ControlPrimitives)
            self.assertFalse(sentinel.exists(),"mutable parent worktree bytes executed instead of accepted Git bytes")
            self.assertEqual(getattr(loaded,"BASE_MARKER",None),"accepted")

    def test_control_record_blob_mismatch_fails_before_parent_execution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-base-mismatch-") as temporary:
            root=Path(temporary).resolve(strict=True); base=root/BASE_RELATIVE
            base.parent.mkdir(parents=True,exist_ok=True); base.write_text("BASE_MARKER='accepted'\n",encoding="utf-8")
            subprocess.run(["/usr/bin/git","-C",str(root),"init","-q"],check=True)
            subprocess.run(["/usr/bin/git","-C",str(root),"config","user.email","capture@nembra.invalid"],check=True)
            subprocess.run(["/usr/bin/git","-C",str(root),"config","user.name","Nembra Capture QA"],check=True)
            subprocess.run(["/usr/bin/git","-C",str(root),"add","."],check=True); subprocess.run(["/usr/bin/git","-C",str(root),"commit","-qm","fixture"],check=True)
            source=subprocess.check_output(["/usr/bin/git","-C",str(root),"rev-parse","HEAD"],text=True).strip()
            with self.assertRaises(GO.GeneratedSubjectGoError):
                GO._load_base_module(root,{"parentSourceCommitSHA":source,"gitBlobs":{BASE_RELATIVE:"0"*40}},GO._ControlPrimitives)

if __name__=="__main__":unittest.main(verbosity=2)
