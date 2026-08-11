import hashlib, importlib.util, json, subprocess, tempfile, unittest, zipfile
from pathlib import Path
MODULE=Path(__file__).resolve().parents[1]/'es80_authenticated_stationary_final_go.py';spec=importlib.util.spec_from_file_location('go',MODULE);go=importlib.util.module_from_spec(spec);spec.loader.exec_module(go)
def H(b):return hashlib.sha256(b).hexdigest()
class F:
 def __init__(self,r):
  self.r=r;self.repo=r/'repo';self.repo.mkdir();subprocess.run(['/usr/bin/git','-C',str(self.repo),'init','-q'],check=True);subprocess.run(['/usr/bin/git','-C',str(self.repo),'config','user.email','x@y.z'],check=True);subprocess.run(['/usr/bin/git','-C',str(self.repo),'config','user.name','t'],check=True)
  installer=f'PROCEDURE_ID="{go.PROC}"\nBUNDLE_ID="{go.BUNDLE}"\n"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\n-- xcodebuild\n'
  bootstrap='NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256\n--resolve-lock-for-review\n[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]\n'
  for p,t in {go.INSTALLER:installer,go.BOOTSTRAP:bootstrap,go.RUNBOOK:f'PROCEDURE_ID: `{go.PROC}`\n',go.IDENTITY:f'static let requiredFieldProcedureIdentifier = "{go.PROC}"\n'}.items():q=self.repo/p;q.parent.mkdir(parents=True,exist_ok=True);q.write_text(t)
  subprocess.run(['/usr/bin/git','-C',str(self.repo),'add','.'],check=True);subprocess.run(['/usr/bin/git','-C',str(self.repo),'commit','-qm','f'],check=True);self.s=subprocess.check_output(['/usr/bin/git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip();self.pr=2612;self.ids={n:100+i for i,n in enumerate(go.WORKFLOWS)};self.aid=99;self.rid=88;self.lockrid=89;self.lock='a'*64
  self.std=b'std';self.ax=b'ax';self.arc=r/'v.zip';m={'schemaVersion':6,'authority':'standalone-capture-simulator-presentation-only','sourceCommitSHA':self.s,'buildIdentifier':f'capture-v14-{self.s[:12]}','bundleIdentifier':go.BUNDLE,'procedureIdentifier':go.PROC,'baselineDevice':go.DEVICE,'baselineOS':'iOS 27','expectedFieldBuildAuthority':False,'physicalAuthorityCreated':False,'protocolAuthorityCreated':False,'syntheticAuthorityEnvironmentRejected':True,'visualAcceptanceRequiresHumanReview':True,'requiredProcedureSourceVerified':True,'procedureBuildRendezvousVerified':True,'tuyaDependencyLockSHA256':'','screenshots':[{'state':'unprovisioned-dark-standard','relativePath':'s.png','sha256':H(self.std)},{'state':'unprovisioned-dark-accessibility-xxxl','relativePath':'a.png','sha256':H(self.ax)}]};self.mr=(json.dumps(m,sort_keys=True)+'\n').encode()
  with zipfile.ZipFile(self.arc,'w') as z:z.writestr(go.MANIFEST,self.mr);z.writestr('s.png',self.std);z.writestr('a.png',self.ax)
  self.dev=r/'device';self.dev.write_text('device-token\n');self.dev.chmod(0o600)
  self.map={f'/pulls/{self.pr}':{'state':'open','draft':False,'merged_at':None,'head':{'sha':self.s,'ref':'feature/final','repo':{'full_name':go.REPO}},'base':{'ref':'main'}},f'/actions/artifacts/{self.aid}':{'expired':False,'digest':'sha256:'+H(self.arc.read_bytes()),'workflow_run':{'id':self.ids[go.VISUAL]}}}
  for n,i in self.ids.items():self.map[f'/actions/runs/{i}']={'name':n,'path':go.WORKFLOW_PATHS[n],'head_sha':self.s,'status':'completed','conclusion':'success','event':'pull_request','head_branch':'feature/final','pull_requests':[{'number':self.pr}]}
  self.write_review();self.write_lock_review()
 def body(self,**x):
  d={'schemaVersion':1,'authority':'nembra-visual-human-review-github-v1','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'verdict':'accepted'};d.update(x);return json.dumps(d,sort_keys=True)
 def lock_body(self,**x):
  d={'schemaVersion':1,'authority':'nembra-tuya-dependency-lock-review-github-v1','sourceCommitSHA':self.s,'podfileLockSHA256':self.lock,'verdict':'accepted'};d.update(x);return json.dumps(d,sort_keys=True)
 def write_review(self,**x):
  d={'id':self.rid,'node_id':'PRR_visual','state':'COMMENTED','commit_id':self.s,'user':{'login':go.OWNER},'author_association':'OWNER','submitted_at':'2026-08-11T02:00:00Z','body':self.body()};d.update(x);self.map[f'/pulls/{self.pr}/reviews/{self.rid}']=d
 def write_lock_review(self,**x):
  d={'id':self.lockrid,'node_id':'PRR_lock','state':'COMMENTED','commit_id':self.s,'user':{'login':go.OWNER},'author_association':'OWNER','submitted_at':'2026-08-11T02:01:00Z','body':self.lock_body()};d.update(x);self.map[f'/pulls/{self.pr}/reviews/{self.lockrid}']=d
 def get(self,p):
  if p=='/branches/main':v={'commit':{'sha':getattr(self,'main','0'*40)}}
  elif p.startswith('/compare/'):
   base=p.split('/compare/',1)[1].split('...',1)[0];v={'status':getattr(self,'compare_status','ahead'),'merge_base_commit':{'sha':base}}
  else:v=self.map[p]
  return json.dumps(v).encode(),v
 def control(self,repo,pr,run,get):return {'authority':'nembra-authenticated-stationary-go-control-plane-v1','sourceCommitSHA':'e'*40,'prNumber':2638,'headBranch':'control/final','state':'open','merged':False,'draft':False,'workflowRunID':900,'workflowName':go.AUTH_WORKFLOW_NAME,'workflowPath':go.AUTH_WORKFLOW_PATH,'gitBlobs':{}}
 def inst(self,repo,s,dev,lock):return {'authority':'accepted-candidate-private-installer-execution-v1','result':'success','sourceCommitSHA':s,'buildIdentifier':f'capture-v14-{s[:12]}','bundleIdentifier':go.BUNDLE,'procedureIdentifier':go.PROC,'acceptedTuyaDependencyLockSHA256':lock,'baselineDevice':go.DEVICE,'baselineProductType':go.PRODUCT,'baselineOS':'iOS 27'}
 def signed(self,repo,s,dev,install,output):return {'authority':'nembra-authenticated-stationary-retained-signed-artifact-v1','sourceCommitSHA':s,'buildIdentifier':f'capture-v14-{s[:12]}','bundleIdentifier':go.BUNDLE,'procedureIdentifier':go.PROC,'tuyaDependencyLockSHA256':self.lock,'retainedIPASHA256':'b'*64,'retainedAppTreeSHA256':'c'*64,'embeddedProvisioningProfileSHA256':'d'*64,'signingTeamIdentifier':'TEAM','applicationIdentifier':'TEAM.'+go.BUNDLE,'codesignVerified':True,'intendedDeviceIncluded':True,'physicalAuthorityCreated':False}
 def build(self,**x):
  a=dict(authority_repo=self.repo,authority_pr=2638,authority_run=900,candidate_repo=self.repo,source=self.s,pr=self.pr,runs=self.ids,artifact_id=self.aid,review_id=self.rid,lock_review_id=self.lockrid,archive=self.arc,device_file=self.dev,retained_ipa=self.r/'retained.ipa',get=self.get,control_authority=self.control,run_installer=self.inst,inspect_signed_artifact=self.signed,reinspect_signed_artifact=self.signed);a.update(x);return go.build(**a)
class T(unittest.TestCase):
 def setUp(self):self.t=tempfile.TemporaryDirectory();self.f=F(Path(self.t.name))
 def tearDown(self):self.t.cleanup()
 def no(self,fn):
  with self.assertRaises(go.GoError):fn()
 def test_go_control_plane_authority_is_required(self):
  def bad(repo,pr,run,get):raise go.GoError("unaccepted GO control plane")
  self.no(lambda:self.f.build(control_authority=bad))
 def test_go_control_plane_requires_exact_current_main_ancestor(self):
  paths=("scripts/ci/es80_authenticated_stationary_final_go.py","scripts/ci/es80_authenticated_stationary_signed_artifact.py","scripts/ci/es80_today_final_go_publication.py",go.AUTH_WORKFLOW_PATH,"scripts/ci/tests/test_es80_authenticated_stationary_final_go.py","scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py")
  for rel in paths:
   q=self.f.repo/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_text(rel+'\n')
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'add','.'],check=True);subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'commit','-qm','control fixture'],check=True)
  source=subprocess.check_output(['/usr/bin/git','-C',str(self.f.repo),'rev-parse','HEAD'],text=True).strip();self.f.main='0'*40
  self.f.map['/pulls/2638']={'state':'open','draft':False,'merged_at':None,'head':{'sha':source,'ref':'control/final','repo':{'full_name':go.REPO}},'base':{'ref':'main'}}
  self.f.map['/actions/runs/900']={'name':go.AUTH_WORKFLOW_NAME,'path':go.AUTH_WORKFLOW_PATH,'head_sha':source,'status':'completed','conclusion':'success','event':'push','head_branch':'control/final','pull_requests':[]}
  self.f.compare_status='diverged';self.no(lambda:go.control_plane(self.f.repo,2638,900,self.f.get))
  self.f.compare_status='ahead';r=go.control_plane(self.f.repo,2638,900,self.f.get);self.assertEqual(r['mainSHA'],'0'*40)
 def test_production_default_refuses_go_without_retained_signed_artifact_authority(self):
  a=dict(authority_repo=self.f.repo,authority_pr=2638,authority_run=900,candidate_repo=self.f.repo,source=self.f.s,pr=self.f.pr,runs=self.f.ids,artifact_id=self.f.aid,review_id=self.f.rid,lock_review_id=self.f.lockrid,archive=self.f.arc,device_file=self.f.dev,retained_ipa=self.f.r/'retained.ipa',get=self.f.get,control_authority=self.f.control,run_installer=self.f.inst)
  self.no(lambda:go.build(**a))
 def test_malformed_retained_signed_artifact_authority_is_rejected(self):
  def bad(r,s,d,i,o):x=self.f.signed(r,s,d,i,o);x["retainedIPASHA256"]="not-a-digest";return x
  self.no(lambda:self.f.build(inspect_signed_artifact=bad))
 def test_retained_signed_lock_must_match_reviewed_digest(self):
  def bad(r,s,d,i,o):x=self.f.signed(r,s,d,i,o);x["tuyaDependencyLockSHA256"]='e'*64;return x
  self.no(lambda:self.f.build(inspect_signed_artifact=bad))
 def test_go_scope_and_remote_review_custody(self):
  r=self.f.build();self.assertEqual(r['status'],'GO');self.assertFalse(r['physicalResultCollected']);self.assertEqual(r['visualReview']['reviewID'],self.f.rid);self.assertEqual(r['tuyaDependencyLockReview']['reviewID'],self.f.lockrid);self.assertEqual(r['tuyaDependencyLockReview']['podfileLockSHA256'],self.f.lock);self.assertEqual(r['privateFieldInstall']['acceptedTuyaDependencyLockSHA256'],self.f.lock);self.assertEqual(r['visualReview']['reviewer'],go.OWNER);self.assertFalse(r['experiment']['ridingAuthorized']);self.assertFalse(r['experiment']['applicationWritesAuthorized']);self.assertEqual(r['visualArtifact']['manifestSHA256'],H(self.f.mr))
 def test_installer_receives_exact_reviewed_lock(self):
  seen=[]
  def run(r,s,d,lock):seen.append(lock);return self.f.inst(r,s,d,lock)
  self.assertEqual(self.f.build(run_installer=run)['status'],'GO');self.assertEqual(seen,[self.f.lock])
 def test_current_main_is_bound_and_must_be_candidate_ancestor(self):
  r=self.f.build();self.assertEqual(r['acceptedPR']['mainSHA'],'0'*40)
  self.f.compare_status='diverged';self.no(self.f.build)
 def test_draft_or_closed_unmerged_pr_rejected_but_exact_merged_allowed(self):
  p=self.f.map[f'/pulls/{self.f.pr}'];p['draft']=True;self.no(self.f.build);p['draft']=False;p['state']='closed';self.no(self.f.build);p['merged_at']='2026-08-11T02:00:00Z';self.assertTrue(self.f.build()['acceptedPR']['merged'])
 def test_missing_extra_queued_or_ancestor_workflow_rejected(self):
  d=dict(self.f.ids);d.pop(next(iter(d)));self.no(lambda:self.f.build(runs=d));d=dict(self.f.ids);d['extra']=1;self.no(lambda:self.f.build(runs=d));i=self.f.ids['Xcode 27 PR Exact-Head QA'];self.f.map[f'/actions/runs/{i}']['status']='queued';self.f.map[f'/actions/runs/{i}']['conclusion']=None;self.no(self.f.build);self.f.map[f'/actions/runs/{i}'].update(status='completed',conclusion='success',head_sha='1'*40);self.no(self.f.build)
 def test_duplicate_display_name_from_wrong_workflow_path_is_rejected(self):
  i=self.f.ids['Capture Field Build Provenance'];self.f.map[f'/actions/runs/{i}']['path']='.github/workflows/fake-green.yml';self.no(self.f.build)
 def test_empty_pull_list_requires_exact_head_branch(self):
  for i in self.f.ids.values():self.f.map[f'/actions/runs/{i}']['pull_requests']=[]
  self.assertEqual(self.f.build()['status'],'GO');i=self.f.ids[go.VISUAL];self.f.map[f'/actions/runs/{i}']['head_branch']='other';self.no(self.f.build)
 def test_artifact_or_screenshot_tamper_rejected(self):
  self.f.map[f'/actions/artifacts/{self.f.aid}']['digest']='sha256:'+'0'*64;self.no(self.f.build);self.f.map[f'/actions/artifacts/{self.f.aid}']['digest']='sha256:'+H(self.f.arc.read_bytes())
  with zipfile.ZipFile(self.f.arc,'a') as z:z.writestr('s.png',b'bad')
  self.f.map[f'/actions/artifacts/{self.f.aid}']['digest']='sha256:'+H(self.f.arc.read_bytes());self.no(self.f.build)
 def test_github_review_owner_commit_state_and_body_are_authority(self):
  path=f'/pulls/{self.f.pr}/reviews/{self.f.rid}';r=self.f.map[path]
  r['user']['login']='attacker';self.no(self.f.build);r['user']['login']=go.OWNER
  r['author_association']='MEMBER';self.no(self.f.build);r['author_association']='OWNER'
  r['commit_id']='1'*40;self.no(self.f.build);r['commit_id']=self.f.s
  r['state']='DISMISSED';self.no(self.f.build);r['state']='COMMENTED'
  r['body']='{"schemaVersion":1,"schemaVersion":1}';self.no(self.f.build)
  r['body']=self.f.body(verdict='rejected');self.no(self.f.build)
  r['body']=self.f.body(standardScreenshotSHA256='0'*64);self.no(self.f.build)
 def test_dependency_lock_review_owner_commit_state_and_body_are_authority(self):
  path=f'/pulls/{self.f.pr}/reviews/{self.f.lockrid}';r=self.f.map[path]
  r['user']['login']='attacker';self.no(self.f.build);r['user']['login']=go.OWNER
  r['author_association']='MEMBER';self.no(self.f.build);r['author_association']='OWNER'
  r['commit_id']='1'*40;self.no(self.f.build);r['commit_id']=self.f.s
  r['state']='DISMISSED';self.no(self.f.build);r['state']='COMMENTED'
  r['body']='{"schemaVersion":1,"schemaVersion":1}';self.no(self.f.build)
  r['body']=self.f.lock_body(verdict='rejected');self.no(self.f.build)
  r['body']=self.f.lock_body(podfileLockSHA256='A'*64);self.no(self.f.build)
  r['body']=self.f.lock_body(podfileLockSHA256='0'*64);self.no(lambda:self.f.build(inspect_signed_artifact=self.f.signed))
 def test_candidate_dirty_retired_or_missing_lock_authority_rejected(self):
  (self.f.repo/'dirty').write_text('x');self.no(self.f.build);(self.f.repo/'dirty').unlink();p=self.f.repo/go.INSTALLER;p.write_text(p.read_text()+'ES80-FINGERPRINT-v1\n');subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'add','.'],check=True);subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'commit','-qm','old'],check=True);s=subprocess.check_output(['/usr/bin/git','-C',str(self.f.repo),'rev-parse','HEAD'],text=True).strip();self.no(lambda:go.candidate(self.f.repo,s))
 def test_private_device_custody_and_installer_drift_rejected(self):
  self.f.dev.chmod(0o644);self.no(self.f.build);self.f.dev.chmod(0o600)
  def bad(r,s,d,lock):x=self.f.inst(r,s,d,lock);x['bundleIdentifier']='bad';return x
  self.no(lambda:self.f.build(run_installer=bad))
 def test_private_device_path_rejects_symlinked_parent_and_noncanonical_paths(self):
  root=Path(self.t.name);real=root/'private';real.mkdir();dev=real/'device';dev.write_text('device-token');dev.chmod(0o600);alias=root/'alias';alias.symlink_to(real,target_is_directory=True)
  self.no(lambda:go.device_hash(alias/'device'))
  self.no(lambda:go.device_hash(Path('relative-device')))
 def test_installer_never_runs_before_public_visual_and_lock_acceptance(self):
  calls=[]
  def run(r,s,d,lock):calls.append((s,lock));return self.f.inst(r,s,d,lock)
  i=self.f.ids['Capture Field Build Provenance'];self.f.map[f'/actions/runs/{i}']['conclusion']='cancelled';self.no(lambda:self.f.build(run_installer=run));self.assertEqual(calls,[])
  self.f.map[f'/actions/runs/{i}']['conclusion']='success';self.f.map[f'/pulls/{self.f.pr}/reviews/{self.f.lockrid}']['body']=self.f.lock_body(verdict='rejected');self.no(lambda:self.f.build(run_installer=run));self.assertEqual(calls,[])
 def test_post_install_current_main_drift_is_rejected(self):
  def move_main(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.main='1'*40;return x
  self.no(lambda:self.f.build(run_installer=move_main))
 def test_post_install_revalidation_rejects_control_plane_drift(self):
  calls=0
  def moving(repo,pr,run,get):
   nonlocal calls;calls+=1;x=self.f.control(repo,pr,run,get);return x if calls==1 else {**x,"sourceCommitSHA":"f"*40}
  self.no(lambda:self.f.build(control_authority=moving))
 def test_post_install_revalidation_rejects_control_plane_pr_state_drift(self):
  calls=0
  def moving(repo,pr,run,get):
   nonlocal calls;calls+=1;x=self.f.control(repo,pr,run,get);return x if calls==1 else {**x,"state":"closed","merged":True}
  self.no(lambda:self.f.build(control_authority=moving))
 def test_post_install_revalidation_rejects_pr_artifact_reviews_or_device_drift(self):
  pull=f'/pulls/{self.f.pr}';review=f'/pulls/{self.f.pr}/reviews/{self.f.rid}';lockreview=f'/pulls/{self.f.pr}/reviews/{self.f.lockrid}';artifact=f'/actions/artifacts/{self.f.aid}'
  def merge_pr(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.map[pull]['state']='closed';self.f.map[pull]['merged_at']='2026-08-11T02:10:00Z';return x
  self.no(lambda:self.f.build(run_installer=merge_pr));self.f.map[pull]['state']='open';self.f.map[pull]['merged_at']=None
  def move_pr(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.map[pull]['head']['sha']='1'*40;return x
  self.no(lambda:self.f.build(run_installer=move_pr));self.f.map[pull]['head']['sha']=self.f.s
  def expire(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.map[artifact]['expired']=True;return x
  self.no(lambda:self.f.build(run_installer=expire));self.f.map[artifact]['expired']=False
  def dismiss(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.map[review]['state']='DISMISSED';return x
  self.no(lambda:self.f.build(run_installer=dismiss));self.f.map[review]['state']='COMMENTED'
  def change_lock_review(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.map[lockreview]['body']=self.f.lock_body(podfileLockSHA256='e'*64);return x
  self.no(lambda:self.f.build(run_installer=change_lock_review));self.f.map[lockreview]['body']=self.f.lock_body()
  def change_device(r,s,d,lock):x=self.f.inst(r,s,d,lock);self.f.dev.write_text('other-device\n');return x
  self.no(lambda:self.f.build(run_installer=change_device))
 def test_candidate_rejects_assume_unchanged_installer_tamper(self):
  path=self.f.repo/go.INSTALLER
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--assume-unchanged',go.INSTALLER],check=True)
  path.write_text(path.read_text()+'# hidden replacement bytes\n')
  self.no(lambda:go.candidate(self.f.repo,self.f.s))
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--no-assume-unchanged',go.INSTALLER],check=True)
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'checkout','--',go.INSTALLER],check=True)
 def test_candidate_rejects_skip_worktree_installer_tamper(self):
  path=self.f.repo/go.INSTALLER
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--skip-worktree',go.INSTALLER],check=True)
  path.write_text(path.read_text()+'# hidden replacement bytes\n')
  self.no(lambda:go.candidate(self.f.repo,self.f.s))
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--no-skip-worktree',go.INSTALLER],check=True)
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'checkout','--',go.INSTALLER],check=True)
 def test_candidate_rejects_assume_unchanged_bootstrap_tamper(self):
  path=self.f.repo/go.BOOTSTRAP
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--assume-unchanged',go.BOOTSTRAP],check=True)
  path.write_text(path.read_text()+'# hidden lock-bypass bytes\n')
  self.no(lambda:go.candidate(self.f.repo,self.f.s))
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--no-assume-unchanged',go.BOOTSTRAP],check=True)
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'checkout','--',go.BOOTSTRAP],check=True)
 def test_candidate_rejects_skip_worktree_bootstrap_tamper(self):
  path=self.f.repo/go.BOOTSTRAP
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--skip-worktree',go.BOOTSTRAP],check=True)
  path.write_text(path.read_text()+'# hidden lock-bypass bytes\n')
  self.no(lambda:go.candidate(self.f.repo,self.f.s))
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--no-skip-worktree',go.BOOTSTRAP],check=True)
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'checkout','--',go.BOOTSTRAP],check=True)
if __name__=='__main__':unittest.main(verbosity=2)