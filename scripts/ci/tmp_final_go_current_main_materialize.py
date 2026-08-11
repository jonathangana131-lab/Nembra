from pathlib import Path

def rep(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one replacement target, found {count}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))

src = "scripts/ci/es80_authenticated_stationary_final_go.py"
tests = "scripts/ci/tests/test_es80_authenticated_stationary_final_go.py"

rep(src,
    '    return raw,obj(raw,path)\n\ndef public(source:str,pr:int,runs:dict[str,int],get=api):',
    '    return raw,obj(raw,path)\n\ndef current_main(get=api):\n    _,ref=get("/git/ref/heads/main"); subject=ref.get("object",{})\n    if ref.get("ref")!="refs/heads/main" or subject.get("type")!="commit": raise GoError("current main ref is not canonical commit authority")\n    return canon(subject.get("sha"),"current main")\n\ndef public(source:str,pr:int,runs:dict[str,int],get=api):')

rep(src,
    '    _,p=get(f"/pulls/{pr}"); head=p.get("head",{}); base=p.get("base",{}); head_ref=head.get("ref"); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft")',
    '    _,p=get(f"/pulls/{pr}"); head=p.get("head",{}); base=p.get("base",{}); head_ref=head.get("ref"); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft"); base_sha=canon(base.get("sha"),"PR base")')
rep(src,
    '    return {"number":pr,"headSHA":source,"headBranch":head_ref,"base":"main","state":state,"merged":merged,"draft":draft},subjects',
    '    return {"number":pr,"headSHA":source,"headBranch":head_ref,"base":"main","baseSHA":base_sha,"state":state,"merged":merged,"draft":draft},subjects')

rep(src,
    '    _,p=get(f"/pulls/{pos(pr,\'GO control-plane PR\')}"); head=p.get("head",{}); base=p.get("base",{}); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft")',
    '    _,p=get(f"/pulls/{pos(pr,\'GO control-plane PR\')}"); head=p.get("head",{}); base=p.get("base",{}); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft"); base_sha=canon(base.get("sha"),"GO control-plane PR base")')
rep(src,
    '    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}',
    '    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"baseSHA":base_sha,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}')

rep(src,
    'def build(*,authority_repo:Path,authority_pr:int,authority_run:int,candidate_repo:Path,source:str,pr:int,runs:dict[str,int],artifact_id:int,review_id:int,archive:Path,device_file:Path,retained_ipa:Path,get=api,control_authority=control_plane,run_installer=installer,inspect_signed_artifact=retained_signed_artifact,reinspect_signed_artifact=retained_signed_artifact_reinspect,now=None):\n    control=control_authority(authority_repo,authority_pr,authority_run,get)\n    source=canon(source,"source"); pr=pos(pr,"PR")\n    ps,ws=public(source,pr,runs,get); vs=visual(source,runs[VISUAL],pos(artifact_id,"artifact"),archive,get); rv=review(pr,review_id,source,vs,get); cs=candidate(candidate_repo,source); dh=device_hash(device_file)',
    'def build(*,authority_repo:Path,authority_pr:int,authority_run:int,candidate_repo:Path,source:str,pr:int,runs:dict[str,int],artifact_id:int,review_id:int,archive:Path,device_file:Path,retained_ipa:Path,get=api,control_authority=control_plane,run_installer=installer,inspect_signed_artifact=retained_signed_artifact,reinspect_signed_artifact=retained_signed_artifact_reinspect,now=None):\n    main_sha=current_main(get); control=control_authority(authority_repo,authority_pr,authority_run,get)\n    source=canon(source,"source"); pr=pos(pr,"PR")\n    ps,ws=public(source,pr,runs,get); vs=visual(source,runs[VISUAL],pos(artifact_id,"artifact"),archive,get); rv=review(pr,review_id,source,vs,get); cs=candidate(candidate_repo,source); dh=device_hash(device_file)\n    if ps.get("baseSHA")!=main_sha or control.get("baseSHA")!=main_sha: raise GoError("accepted software/control subjects are not based on exact current main")')

rep(src,
    '    post_control=control_authority(authority_repo,authority_pr,authority_run,get); post_ps,post_ws=public(source,pr,runs,get); post_vs=visual(source,runs[VISUAL],artifact_id,archive,get); post_rv=review(pr,review_id,source,post_vs,get); post_cs=candidate(candidate_repo,source); post_dh=device_hash(device_file); post_signed=reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)',
    '    post_main_sha=current_main(get); post_control=control_authority(authority_repo,authority_pr,authority_run,get); post_ps,post_ws=public(source,pr,runs,get); post_vs=visual(source,runs[VISUAL],artifact_id,archive,get); post_rv=review(pr,review_id,source,post_vs,get); post_cs=candidate(candidate_repo,source); post_dh=device_hash(device_file); post_signed=reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)')
rep(src,
    '    if post_control!=control or any(post_ps[k]!=ps[k] for k in stable_pr) or post_ws!=ws or post_vs!=vs or post_rv!=rv or post_cs!=cs or post_dh!=dh or post_signed!=signed:',
    '    if post_main_sha!=main_sha or post_control!=control or any(post_ps[k]!=ps[k] for k in stable_pr) or post_ws!=ws or post_vs!=vs or post_rv!=rv or post_cs!=cs or post_dh!=dh or post_signed!=signed:')
rep(src,
    '    return {"schemaVersion":1,"authority":"nembra-authenticated-stationary-final-go-v1","status":"GO","createdAtUTC":stamp,"finalGOControlPlane":control,"acceptedSourceCommitSHA":source,',
    '    return {"schemaVersion":1,"authority":"nembra-authenticated-stationary-final-go-v1","status":"GO","createdAtUTC":stamp,"finalGOControlPlane":control,"acceptedMainCommitSHA":main_sha,"acceptedSourceCommitSHA":source,')

rep(tests,
    "self.s=subprocess.check_output(['/usr/bin/git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip();self.pr=2612;self.ids=",
    "self.s=subprocess.check_output(['/usr/bin/git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip();self.main='a'*40;self.pr=2612;self.ids=")
rep(tests,
    "'base':{'ref':'main'}},f'/actions/artifacts/{self.aid}'",
    "'base':{'ref':'main','sha':self.main}},'/git/ref/heads/main':{'ref':'refs/heads/main','object':{'type':'commit','sha':self.main}},f'/actions/artifacts/{self.aid}'")
rep(tests,
    "'prNumber':2638,'headBranch':'control/final'",
    "'prNumber':2638,'headBranch':'control/final','baseSHA':self.main")
rep(tests,
    "r=self.f.build();self.assertEqual(r['status'],'GO');self.assertFalse(r['physicalResultCollected']);",
    "r=self.f.build();self.assertEqual(r['status'],'GO');self.assertEqual(r['acceptedMainCommitSHA'],self.f.main);self.assertFalse(r['physicalResultCollected']);")
rep(tests,
    ' def test_post_install_revalidation_rejects_control_plane_drift(self):',
    ''' def test_current_main_and_subject_bases_are_bound_before_install(self):
  calls=[]
  def run(r,s,d):calls.append(s);return self.f.inst(r,s,d)
  main=self.f.map['/git/ref/heads/main'];pull=self.f.map[f'/pulls/{self.f.pr}']
  main['object']['sha']='b'*40;self.no(lambda:self.f.build(run_installer=run));self.assertEqual(calls,[]);main['object']['sha']=self.f.main
  pull['base']['sha']='b'*40;self.no(lambda:self.f.build(run_installer=run));self.assertEqual(calls,[]);pull['base']['sha']=self.f.main
  def wrong_control(repo,pr,run_id,get):x=self.f.control(repo,pr,run_id,get);x['baseSHA']='b'*40;return x
  self.no(lambda:self.f.build(control_authority=wrong_control,run_installer=run));self.assertEqual(calls,[])
 def test_post_install_revalidation_rejects_main_movement(self):
  def move_main(r,s,d):x=self.f.inst(r,s,d);self.f.map['/git/ref/heads/main']['object']['sha']='b'*40;return x
  self.no(lambda:self.f.build(run_installer=move_main))
 def test_post_install_revalidation_rejects_control_plane_drift(self):''')
