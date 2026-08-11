#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
TESTS = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


source = SOURCE.read_text(encoding="utf-8")
source = replace_once(
    source,
    '''    if not ((state=="open" and draft is False) or (state=="closed" and merged)):
        raise GoError("canonical PR is draft or closed without merge; software acceptance is not promotable")
    subjects=[]
''',
    '''    if not ((state=="open" and draft is False) or (state=="closed" and merged)):
        raise GoError("canonical PR is draft or closed without merge; software acceptance is not promotable")
    _,main=get("/branches/main"); main_sha=canon(main.get("commit",{}).get("sha"),"current main")
    _,comparison=get(f"/compare/{main_sha}...{source}"); merge_base=comparison.get("merge_base_commit",{})
    if comparison.get("status") not in {"ahead","identical"} or canon(merge_base.get("sha"),"main/candidate merge base")!=main_sha:
        raise GoError("candidate does not contain the exact current main authority")
    subjects=[]
''',
    "current-main admission",
)
source = replace_once(
    source,
    '''    return {"number":pr,"headSHA":source,"headBranch":head_ref,"base":"main","state":state,"merged":merged,"draft":draft},subjects
''',
    '''    return {"number":pr,"headSHA":source,"headBranch":head_ref,"base":"main","mainSHA":main_sha,"state":state,"merged":merged,"draft":draft},subjects
''',
    "accepted PR main binding",
)
source = replace_once(
    source,
    '''def candidate(repo:Path,source:str):
    root=repo.expanduser().resolve(strict=True)
    if canon(git(root,"rev-parse","HEAD"),"candidate HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("candidate checkout is not exact clean accepted source")
    blobs={k:git(root,"rev-parse",f"HEAD:{p}").lower() for k,p in (("installer",INSTALLER),("runbook",RUNBOOK),("buildIdentity",IDENTITY))}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",x) for x in blobs.values()): raise GoError("candidate Git blob invalid")
    paths=[root/INSTALLER,root/RUNBOOK,root/IDENTITY]
    if any(not p.is_file() or p.is_symlink() for p in paths): raise GoError("candidate authority path is not a regular non-symlink file")
    ins=paths[0].read_text(); rb=paths[1].read_text(); ident=paths[2].read_text()
    if f'PROCEDURE_ID="{PROC}"' not in ins or f'BUNDLE_ID="{BUNDLE}"' not in ins or f"PROCEDURE_ID: `{PROC}`" not in rb or f'static let requiredFieldProcedureIdentifier = "{PROC}"' not in ident or "ES80-FINGERPRINT-v1" in ins or "NEMBRA_ES80_TODAY_RESEARCH" in ins: raise GoError("candidate carries wrong/retired field authority")
    return {"sourceCommitSHA":source,"installerGitBlob":blobs["installer"],"runbookGitBlob":blobs["runbook"],"buildIdentityGitBlob":blobs["buildIdentity"]}
''',
    '''def _tracked_worktree_bytes(root:Path,relative:str,expected_blob:str)->bytes:
    tag=git(root,"ls-files","-v","--",relative)
    if tag!=f"H {relative}": raise GoError(f"candidate authority path has non-default Git index flags: {relative}")
    raw=regular(root/relative,f"candidate authority path {relative}")
    actual=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\\0"+raw).hexdigest()
    if actual!=expected_blob: raise GoError(f"candidate worktree bytes differ from accepted Git blob: {relative}")
    return raw

def candidate(repo:Path,source:str):
    root=repo.expanduser().resolve(strict=True)
    if canon(git(root,"rev-parse","HEAD"),"candidate HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("candidate checkout is not exact clean accepted source")
    entries=(("installer",INSTALLER),("runbook",RUNBOOK),("buildIdentity",IDENTITY))
    blobs={k:git(root,"rev-parse",f"HEAD:{p}").lower() for k,p in entries}
    if any(not re.fullmatch(r"[0-9a-f]{40}",x) for x in blobs.values()): raise GoError("candidate Git blob invalid")
    raws={k:_tracked_worktree_bytes(root,p,blobs[k]) for k,p in entries}
    try: ins=raws["installer"].decode(); rb=raws["runbook"].decode(); ident=raws["buildIdentity"].decode()
    except UnicodeDecodeError as e: raise GoError("candidate authority source is not UTF-8") from e
    if f'PROCEDURE_ID="{PROC}"' not in ins or f'BUNDLE_ID="{BUNDLE}"' not in ins or f"PROCEDURE_ID: `{PROC}`" not in rb or f'static let requiredFieldProcedureIdentifier = "{PROC}"' not in ident or "ES80-FINGERPRINT-v1" in ins or "NEMBRA_ES80_TODAY_RESEARCH" in ins: raise GoError("candidate carries wrong/retired field authority")
    return {"sourceCommitSHA":source,"installerGitBlob":blobs["installer"],"runbookGitBlob":blobs["runbook"],"buildIdentityGitBlob":blobs["buildIdentity"]}
''',
    "worktree byte custody",
)
source = replace_once(
    source,
    '''    stable_pr=("number","headSHA","headBranch","base","state","merged","draft")
''',
    '''    stable_pr=("number","headSHA","headBranch","base","mainSHA","state","merged","draft")
''',
    "post-install main drift binding",
)
SOURCE.write_text(source, encoding="utf-8")

tests = TESTS.read_text(encoding="utf-8")
tests = replace_once(
    tests,
    ''' def get(self,p):v=self.map[p];return json.dumps(v).encode(),v
''',
    ''' def get(self,p):
  if p=='/branches/main':v={'commit':{'sha':getattr(self,'main','0'*40)}}
  elif p.startswith('/compare/'):
   base=p.split('/compare/',1)[1].split('...',1)[0];v={'status':getattr(self,'compare_status','ahead'),'merge_base_commit':{'sha':base}}
  else:v=self.map[p]
  return json.dumps(v).encode(),v
''',
    "test API main/compare fixture",
)
insert = ''' def test_current_main_is_bound_and_must_be_candidate_ancestor(self):
  r=self.f.build();self.assertEqual(r['acceptedPR']['mainSHA'],'0'*40)
  self.f.compare_status='diverged';self.no(self.f.build)
 def test_post_install_current_main_drift_is_rejected(self):
  def move_main(r,s,d):x=self.f.inst(r,s,d);self.f.main='1'*40;return x
  self.no(lambda:self.f.build(run_installer=move_main))
 def test_candidate_rejects_hidden_index_flags_and_worktree_byte_drift(self):
  path=self.f.repo/go.INSTALLER;original=path.read_text()
  for flag,clear in [('--assume-unchanged','--no-assume-unchanged'),('--skip-worktree','--no-skip-worktree')]:
   subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index',flag,go.INSTALLER],check=True)
   path.write_text(original+'# hidden byte drift\\n')
   self.no(lambda:go.candidate(self.f.repo,self.f.s))
   path.write_text(original);subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index',clear,go.INSTALLER],check=True)
'''
tests = replace_once(
    tests,
    "if __name__=='__main__':unittest.main(verbosity=2)",
    insert + "if __name__=='__main__':unittest.main(verbosity=2)",
    "focused regression insertion",
)
TESTS.write_text(tests, encoding="utf-8")
