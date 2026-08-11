#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, json, subprocess, tempfile, unittest
from pathlib import Path
MODULE=Path(__file__).resolve().parents[1]/"es80_authenticated_stationary_final_go.py"
SPEC=importlib.util.spec_from_file_location("nembra_final_go",MODULE)
if SPEC is None or SPEC.loader is None: raise RuntimeError("could not load Final-GO issuer")
go=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(go)
class ControlPlaneWorktreeCustodyTests(unittest.TestCase):
 def git(self,repo:Path,*args:str)->str:
  return subprocess.run(["/usr/bin/git","-C",str(repo),*args],check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout.strip()
 def fixture(self,root:Path):
  repo=root/"authority"; repo.mkdir(); self.git(repo,"init","-q"); self.git(repo,"config","user.email","capture@nembra.invalid"); self.git(repo,"config","user.name","Nembra Capture QA")
  paths=("scripts/ci/es80_authenticated_stationary_final_go.py","scripts/ci/es80_authenticated_stationary_signed_artifact.py","scripts/ci/es80_today_final_go_publication.py",go.AUTH_WORKFLOW_PATH,"scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
  for rel in paths:
   p=repo/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(f"accepted bytes for {rel}\n")
  self.git(repo,"add","."); self.git(repo,"commit","-qm","accepted fixture"); source=self.git(repo,"rev-parse","HEAD"); main="0"*40; run=9001; pr=2638; branch="control/v14-auth-stationary-final-go-sol"
  responses={f"/pulls/{pr}":{"state":"open","draft":False,"merged_at":None,"head":{"sha":source,"ref":branch,"repo":{"full_name":go.REPO}},"base":{"ref":"main"}},"/branches/main":{"commit":{"sha":main}},f"/compare/{main}...{source}":{"status":"ahead","merge_base_commit":{"sha":main}},f"/actions/runs/{run}":{"name":go.AUTH_WORKFLOW_NAME,"path":go.AUTH_WORKFLOW_PATH,"head_sha":source,"status":"completed","conclusion":"success","event":"push","head_branch":branch,"pull_requests":[]}}
  def get(path):
   value=responses[path]; return json.dumps(value).encode(),value
  return repo,source,run,get
 def test_hidden_authority_worktree_replacement_is_rejected(self):
  with tempfile.TemporaryDirectory(prefix="nembra-control-worktree-") as tmp:
   repo,source,run,get=self.fixture(Path(tmp)); self.assertEqual(go.control_plane(repo,2638,run,get)["sourceCommitSHA"],source)
   target="scripts/ci/es80_authenticated_stationary_signed_artifact.py"; self.git(repo,"update-index","--assume-unchanged","--",target); (repo/target).write_text("forged worktree bytes\n")
   self.assertEqual(self.git(repo,"status","--porcelain=v1","--untracked-files=all"),""); self.assertNotEqual(self.git(repo,"hash-object","--no-filters","--",target),self.git(repo,"rev-parse",f"HEAD:{target}"))
   with self.assertRaises(go.GoError): go.control_plane(repo,2638,run,get)
 def test_skip_worktree_authority_path_is_rejected_even_without_byte_change(self):
  with tempfile.TemporaryDirectory(prefix="nembra-control-index-") as tmp:
   repo,source,run,get=self.fixture(Path(tmp)); target="scripts/ci/es80_today_final_go_publication.py"; self.git(repo,"update-index","--skip-worktree","--",target)
   with self.assertRaises(go.GoError): go.control_plane(repo,2638,run,get)
if __name__=="__main__": unittest.main(verbosity=2)
