from pathlib import Path


def rep(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, found {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


src = "scripts/ci/es80_authenticated_stationary_final_go.py"
tests = "scripts/ci/tests/test_es80_authenticated_stationary_final_go.py"

rep(
    src,
    '    return raw,obj(raw,path)\n\ndef public(source:str,pr:int,runs:dict[str,int],get=api):',
    '''    return raw,obj(raw,path)

def current_main(get=api):
    _,ref=get("/git/ref/heads/main"); subject=ref.get("object",{})
    if ref.get("ref")!="refs/heads/main" or subject.get("type")!="commit": raise GoError("current main ref is not canonical commit authority")
    return canon(subject.get("sha"),"current main")

def require_current_main_ancestor(main_sha:str,subject_sha:str,label:str,get=api):
    main_sha=canon(main_sha,"accepted main"); subject_sha=canon(subject_sha,label)
    _,comparison=get(f"/compare/{main_sha}...{subject_sha}")
    merge_base=comparison.get("merge_base_commit",{})
    if canon(merge_base.get("sha"),f"{label} merge base")!=main_sha or comparison.get("behind_by")!=0 or comparison.get("status") not in {"ahead","identical"}:
        raise GoError(f"{label} does not contain exact current main")

def public(source:str,pr:int,runs:dict[str,int],get=api):''',
)

rep(
    src,
    '    _,p=get(f"/pulls/{pr}"); head=p.get("head",{}); base=p.get("base",{}); head_ref=head.get("ref"); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft")',
    '    _,p=get(f"/pulls/{pr}"); head=p.get("head",{}); base=p.get("base",{}); head_ref=head.get("ref"); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft"); base_sha=canon(base.get("sha"),"PR base")',
)
rep(
    src,
    '    return {"number":pr,"headSHA":source,"headBranch":head_ref,"base":"main","state":state,"merged":merged,"draft":draft},subjects',
    '    return {"number":pr,"headSHA":source,"headBranch":head_ref,"base":"main","baseSHA":base_sha,"state":state,"merged":merged,"draft":draft},subjects',
)

rep(
    src,
    '    _,p=get(f"/pulls/{pos(pr,\'GO control-plane PR\')}"); head=p.get("head",{}); base=p.get("base",{}); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft")',
    '    _,p=get(f"/pulls/{pos(pr,\'GO control-plane PR\')}"); head=p.get("head",{}); base=p.get("base",{}); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft"); base_sha=canon(base.get("sha"),"GO control-plane PR base")',
)
rep(
    src,
    '    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}',
    '    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"baseSHA":base_sha,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}',
)

rep(
    src,
    '    control=control_authority(authority_repo,authority_pr,authority_run,get)\n    source=canon(source,"source"); pr=pos(pr,"PR")\n    ps,ws=public(source,pr,runs,get); vs=visual(source,runs[VISUAL],pos(artifact_id,"artifact"),archive,get); rv=review(pr,review_id,source,vs,get); lr=dependency_lock_review(pr,lock_review_id,source,get); cs=candidate(candidate_repo,source); dh=device_hash(device_file)\n    accepted_lock=lr["podfileLockSHA256"]',
    '''    main_sha=current_main(get); control=control_authority(authority_repo,authority_pr,authority_run,get)
    source=canon(source,"source"); pr=pos(pr,"PR")
    ps,ws=public(source,pr,runs,get); vs=visual(source,runs[VISUAL],pos(artifact_id,"artifact"),archive,get); rv=review(pr,review_id,source,vs,get); lr=dependency_lock_review(pr,lock_review_id,source,get); cs=candidate(candidate_repo,source); dh=device_hash(device_file)
    if ps.get("baseSHA")!=main_sha or control.get("baseSHA")!=main_sha: raise GoError("software/control PR base does not equal exact current main")
    require_current_main_ancestor(main_sha,source,"software candidate",get)
    require_current_main_ancestor(main_sha,control.get("sourceCommitSHA"),"GO control-plane candidate",get)
    accepted_lock=lr["podfileLockSHA256"]''',
)

rep(
    src,
    '    post_control=control_authority(authority_repo,authority_pr,authority_run,get); post_ps,post_ws=public(source,pr,runs,get); post_vs=visual(source,runs[VISUAL],artifact_id,archive,get); post_rv=review(pr,review_id,source,post_vs,get); post_lr=dependency_lock_review(pr,lock_review_id,source,get); post_cs=candidate(candidate_repo,source); post_dh=device_hash(device_file); post_signed=reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)',
    '    post_main_sha=current_main(get); post_control=control_authority(authority_repo,authority_pr,authority_run,get); post_ps,post_ws=public(source,pr,runs,get); post_vs=visual(source,runs[VISUAL],artifact_id,archive,get); post_rv=review(pr,review_id,source,post_vs,get); post_lr=dependency_lock_review(pr,lock_review_id,source,get); post_cs=candidate(candidate_repo,source); post_dh=device_hash(device_file); post_signed=reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)',
)
rep(
    src,
    '    stable_pr=("number","headSHA","headBranch","base","state","merged","draft")\n    if post_control!=control or any(post_ps[k]!=ps[k] for k in stable_pr) or post_ws!=ws or post_vs!=vs or post_rv!=rv or post_lr!=lr or post_cs!=cs or post_dh!=dh or post_signed!=signed:',
    '    stable_pr=("number","headSHA","headBranch","base","baseSHA","state","merged","draft")\n    if post_main_sha!=main_sha or post_control!=control or any(post_ps[k]!=ps[k] for k in stable_pr) or post_ws!=ws or post_vs!=vs or post_rv!=rv or post_lr!=lr or post_cs!=cs or post_dh!=dh or post_signed!=signed:',
)
rep(
    src,
    '    return {"schemaVersion":1,"authority":"nembra-authenticated-stationary-final-go-v1","status":"GO","createdAtUTC":stamp,"finalGOControlPlane":control,"acceptedSourceCommitSHA":source,',
    '    return {"schemaVersion":1,"authority":"nembra-authenticated-stationary-final-go-v1","status":"GO","createdAtUTC":stamp,"finalGOControlPlane":control,"acceptedMainCommitSHA":main_sha,"acceptedSourceCommitSHA":source,',
)

rep(
    tests,
    "self.s=subprocess.check_output(['/usr/bin/git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip();self.pr=2612;self.ids=",
    "self.s=subprocess.check_output(['/usr/bin/git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip();self.main='9'*40;self.pr=2612;self.ids=",
)
rep(
    tests,
    "'base':{'ref':'main'}},f'/actions/artifacts/{self.aid}'",
    "'base':{'ref':'main','sha':self.main}},'/git/ref/heads/main':{'ref':'refs/heads/main','object':{'type':'commit','sha':self.main}},f'/compare/{self.main}...{self.s}':{'status':'ahead','ahead_by':1,'behind_by':0,'merge_base_commit':{'sha':self.main}},f'/compare/{self.main}...{'e'*40}':{'status':'ahead','ahead_by':1,'behind_by':0,'merge_base_commit':{'sha':self.main}},f'/actions/artifacts/{self.aid}'",
)
rep(
    tests,
    "def control(self,repo,pr,run,get):return {'authority':'nembra-authenticated-stationary-go-control-plane-v1','sourceCommitSHA':'e'*40,'prNumber':2638,'headBranch':'control/final','state':'open','merged':False,'draft':False,",
    "def control(self,repo,pr,run,get):return {'authority':'nembra-authenticated-stationary-go-control-plane-v1','sourceCommitSHA':'e'*40,'prNumber':2638,'headBranch':'control/final','baseSHA':self.main,'state':'open','merged':False,'draft':False,",
)
rep(
    tests,
    "r=self.f.build();self.assertEqual(r['status'],'GO');self.assertFalse(r['physicalResultCollected']);self.assertEqual(r['visualReview']['reviewID'],self.f.rid);",
    "r=self.f.build();self.assertEqual(r['status'],'GO');self.assertEqual(r['acceptedMainCommitSHA'],self.f.main);self.assertFalse(r['physicalResultCollected']);self.assertEqual(r['visualReview']['reviewID'],self.f.rid);",
)
rep(
    tests,
    ' def test_post_install_revalidation_rejects_control_plane_drift(self):',
    ''' def test_current_main_must_be_ancestor_of_both_candidates_before_install(self):
  calls=[]
  def run(r,s,d,lock):calls.append((s,lock));return self.f.inst(r,s,d,lock)
  moved='b'*40;self.f.map['/git/ref/heads/main']['object']['sha']=moved;self.f.map[f'/pulls/{self.f.pr}']['base']['sha']=moved
  self.f.map[f'/compare/{moved}...{self.f.s}']={'status':'diverged','ahead_by':1,'behind_by':1,'merge_base_commit':{'sha':self.f.main}}
  self.f.map[f'/compare/{moved}...{'e'*40}']={'status':'diverged','ahead_by':1,'behind_by':1,'merge_base_commit':{'sha':self.f.main}}
  def moved_control(repo,pr,run_id,get):return {**self.f.control(repo,pr,run_id,get),'baseSHA':moved}
  self.no(lambda:self.f.build(control_authority=moved_control,run_installer=run));self.assertEqual(calls,[])
 def test_current_main_base_mismatch_suppresses_installer(self):
  calls=[]
  def run(r,s,d,lock):calls.append((s,lock));return self.f.inst(r,s,d,lock)
  self.f.map[f'/pulls/{self.f.pr}']['base']['sha']='b'*40;self.no(lambda:self.f.build(run_installer=run));self.assertEqual(calls,[])
 def test_post_install_revalidation_rejects_main_movement(self):
  def move_main(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.map['/git/ref/heads/main']['object']['sha']='b'*40;return x
  self.no(lambda:self.f.build(run_installer=move_main))
 def test_post_install_revalidation_rejects_control_plane_drift(self):''',
)
