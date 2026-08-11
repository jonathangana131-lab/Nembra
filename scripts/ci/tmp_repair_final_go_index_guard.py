#!/usr/bin/env python3
from pathlib import Path

source = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
text = source.read_text()
old = '''def _tracked_worktree_bytes(root:Path,relative:str,expected_blob:str)->bytes:
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
'''
new = '''def _require_default_index_entry(root:Path,relative:str):
    tag=git(root,"ls-files","-v","--",relative)
    if tag!=f"H {relative}": raise GoError(f"candidate authority path has non-default Git index flags: {relative}")

def _tracked_worktree_bytes(root:Path,relative:str,expected_blob:str)->bytes:
    raw=regular(root/relative,f"candidate authority path {relative}")
    actual=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\\0"+raw).hexdigest()
    if actual!=expected_blob: raise GoError(f"candidate worktree bytes differ from accepted Git blob: {relative}")
    return raw

def candidate(repo:Path,source:str):
    root=repo.expanduser().resolve(strict=True)
    if canon(git(root,"rev-parse","HEAD"),"candidate HEAD")!=source: raise GoError("candidate checkout HEAD is not exact accepted source")
    entries=(("installer",INSTALLER),("runbook",RUNBOOK),("buildIdentity",IDENTITY))
    for _,p in entries: _require_default_index_entry(root,p)
    if git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("candidate checkout is not exact clean accepted source")
    blobs={k:git(root,"rev-parse",f"HEAD:{p}").lower() for k,p in entries}
'''
if text.count(old) != 1:
    raise SystemExit("source index-guard repair expected exactly one transformed block")
source.write_text(text.replace(old, new, 1))

tests = Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
text = tests.read_text()
old = ''' def test_candidate_rejects_hidden_index_flags_and_worktree_byte_drift(self):
  path=self.f.repo/go.INSTALLER;original=path.read_text()
  for flag,clear in [('--assume-unchanged','--no-assume-unchanged'),('--skip-worktree','--no-skip-worktree')]:
   subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index',flag,go.INSTALLER],check=True)
   path.write_text(original+'# hidden byte drift\\n')
   self.no(lambda:go.candidate(self.f.repo,self.f.s))
   path.write_text(original);subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index',clear,go.INSTALLER],check=True)
'''
new = ''' def test_candidate_rejects_hidden_index_flags_and_worktree_byte_drift(self):
  path=self.f.repo/go.INSTALLER;original=path.read_text()
  for flag,clear in [('--assume-unchanged','--no-assume-unchanged'),('--skip-worktree','--no-skip-worktree')]:
   with self.subTest(flag=flag):
    subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index',flag,go.INSTALLER],check=True)
    try:self.no(lambda:go.candidate(self.f.repo,self.f.s))
    finally:subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index',clear,go.INSTALLER],check=True)
  path.write_text(original+'# visible byte drift\\n')
  self.no(lambda:go.candidate(self.f.repo,self.f.s))
  path.write_text(original)
'''
if text.count(old) != 1:
    raise SystemExit("test index-guard repair expected exactly one transformed block")
tests.write_text(text.replace(old, new, 1))
