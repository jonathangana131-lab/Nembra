import hashlib, importlib.util, json, subprocess, tempfile, unittest, zipfile
from pathlib import Path
MODULE=Path(__file__).resolve().parents[1]/'es80_authenticated_stationary_final_go.py'; spec=importlib.util.spec_from_file_location('go',MODULE); go=importlib.util.module_from_spec(spec); spec.loader.exec_module(go)
def H(b):return hashlib.sha256(b).hexdigest()
class F:
 def __init__(self,r):
  self.r=r; self.repo=r/'repo'; self.repo.mkdir(); subprocess.run(['/usr/bin/git','-C',str(self.repo),'init','-q'],check=True); subprocess.run(['/usr/bin/git','-C',str(self.repo),'config','user.email','x@y.z'],check=True); subprocess.run(['/usr/bin/git','-C',str(self.repo),'config','user.name','t'],check=True)
  for p,t in {go.INSTALLER:f'PROCEDURE_ID="{go.PROC}"\nBUNDLE_ID="{go.BUNDLE}"\n',go.RUNBOOK:f'PROCEDURE_ID: `{go.PROC}`\n',go.IDENTITY:f'static let requiredFieldProcedureIdentifier = "{go.PROC}"\n'}.items(): q=self.repo/p;q.parent.mkdir(parents=True,exist_ok=True);q.write_text(t)
  subprocess.run(['/usr/bin/git','-C',str(self.repo),'add','.'],check=True); subprocess.run(['/usr/bin/git','-C',str(self.repo),'commit','-qm','f'],check=True); self.s=subprocess.check_output(['/usr/bin/git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip(); self.pr=2612; self.ids={n:100+i for i,n in enumerate(go.WORKFLOWS)}; self.aid=99
  self.std=b'std';self.ax=b'ax';self.arc=r/'v.zip'; m={'schemaVersion':6,'authority':'standalone-capture-simulator-presentation-only','sourceCommitSHA':self.s,'buildIdentifier':f'capture-v14-{self.s[:12]}','bundleIdentifier':go.BUNDLE,'procedureIdentifier':go.PROC,'baselineDevice':go.DEVICE,'baselineOS':'iOS 27','expectedFieldBuildAuthority':False,'physicalAuthorityCreated':False,'protocolAuthorityCreated':False,'syntheticAuthorityEnvironmentRejected':True,'visualAcceptanceRequiresHumanReview':True,'requiredProcedureSourceVerified':True,'procedureBuildRendezvousVerified':True,'tuyaDependencyLockSHA256':'','screenshots':[{'state':'unprovisioned-dark-standard','relativePath':'s.png','sha256':H(self.std)},{'state':'unprovisioned-dark-accessibility-xxxl','relativePath':'a.png','sha256':H(self.ax)}]}; self.mr=(json.dumps(m,sort_keys=True)+'\n').encode()
  with zipfile.ZipFile(self.arc,'w') as z:z.writestr(go.MANIFEST,self.mr);z.writestr('s.png',self.std);z.writestr('a.png',self.ax)
  self.rev=r/'review.json'; self.write_review(); self.dev=r/'device';self.dev.write_text('device-token\n');self.dev.chmod(0o600)
  self.map={f'/pulls/{self.pr}':{'state':'open','draft':False,'merged_at':None,'head':{'sha':self.s,'ref':'feature/final','repo':{'full_name':go.REPO}},'base':{'ref':'main'}},f'/actions/artifacts/{self.aid}':{'expired':False,'digest':'sha256:'+H(self.arc.read_bytes()),'workflow_run':{'id':self.ids[go.VISUAL]}}}
  for n,i in self.ids.items():self.map[f'/actions/runs/{i}']={'name':n,'head_sha':self.s,'status':'completed','conclusion':'success','event':'pull_request','head_branch':'feature/final','pull_requests':[{'number':self.pr}]}
 def write_review(self,**x):
  d={'schemaVersion':1,'authority':'human-visual-review-v1','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'verdict':'accepted','reviewedAtUTC':'2026-08-11T02:00:00Z','reviewer':'visual-reviewer'};d.update(x);self.rev.write_text(json.dumps(d))
 def get(self,p):v=self.map[p];return json.dumps(v).encode(),v
 def inst(self,repo,s,dev):return {'authority':'accepted-candidate-private-installer-execution-v1','result':'success','sourceCommitSHA':s,'buildIdentifier':f'capture-v14-{s[:12]}','bundleIdentifier':go.BUNDLE,'procedureIdentifier':go.PROC,'baselineDevice':go.DEVICE,'baselineProductType':go.PRODUCT,'baselineOS':'iOS 27'}
 def build(self,**x):
  a=dict(candidate_repo=self.repo,source=self.s,pr=self.pr,runs=self.ids,artifact_id=self.aid,archive=self.arc,attestation=self.rev,device_file=self.dev,get=self.get,run_installer=self.inst);a.update(x);return go.build(**a)
class T(unittest.TestCase):
 def setUp(self):self.t=tempfile.TemporaryDirectory();self.f=F(Path(self.t.name))
 def tearDown(self):self.t.cleanup()
 def no(self,fn):
  with self.assertRaises(go.GoError):fn()
 def test_go_scope_and_exact_manifest_bytes(self):
  r=self.f.build();self.assertEqual(r['status'],'GO');self.assertFalse(r['physicalResultCollected']);self.assertFalse(r['experiment']['ridingAuthorized']);self.assertFalse(r['experiment']['applicationWritesAuthorized']);self.assertEqual(r['visualArtifact']['manifestSHA256'],H(self.f.mr))
 def test_draft_or_closed_unmerged_pr_rejected_but_exact_merged_allowed(self):
  p=self.f.map[f'/pulls/{self.f.pr}'];p['draft']=True;self.no(self.f.build);p['draft']=False;p['state']='closed';self.no(self.f.build);p['merged_at']='2026-08-11T02:00:00Z';self.assertEqual(self.f.build()['acceptedPR']['merged'],True)
 def test_missing_extra_queued_or_ancestor_workflow_rejected(self):
  d=dict(self.f.ids);d.pop(next(iter(d)));self.no(lambda:self.f.build(runs=d));d=dict(self.f.ids);d['extra']=1;self.no(lambda:self.f.build(runs=d));i=self.f.ids['Xcode 27 PR Exact-Head QA'];self.f.map[f'/actions/runs/{i}']['status']='queued';self.f.map[f'/actions/runs/{i}']['conclusion']=None;self.no(self.f.build);self.f.map[f'/actions/runs/{i}'].update(status='completed',conclusion='success',head_sha='1'*40);self.no(self.f.build)
 def test_empty_pull_list_uses_exact_canonical_head_branch_fallback(self):
  for i in self.f.ids.values():self.f.map[f'/actions/runs/{i}']['pull_requests']=[]
  self.assertEqual(self.f.build()['status'],'GO')
  i=self.f.ids[go.VISUAL];self.f.map[f'/actions/runs/{i}']['head_branch']='other';self.no(self.f.build)
 def test_artifact_or_screenshot_tamper_rejected(self):
  self.f.map[f'/actions/artifacts/{self.f.aid}']['digest']='sha256:'+'0'*64;self.no(self.f.build)
  self.f.map[f'/actions/artifacts/{self.f.aid}']['digest']='sha256:'+H(self.f.arc.read_bytes());
  with zipfile.ZipFile(self.f.arc,'a') as z:z.writestr('s.png',b'bad')
  self.f.map[f'/actions/artifacts/{self.f.aid}']['digest']='sha256:'+H(self.f.arc.read_bytes());self.no(self.f.build)
 def test_human_review_rejected_or_digest_drift_rejected(self):
  self.f.write_review(verdict='rejected');self.no(self.f.build);self.f.write_review(standardScreenshotSHA256='0'*64);self.no(self.f.build)
 def test_candidate_dirty_and_retired_authority_rejected(self):
  (self.f.repo/'dirty').write_text('x');self.no(self.f.build);(self.f.repo/'dirty').unlink();p=self.f.repo/go.INSTALLER;p.write_text(p.read_text()+'ES80-FINGERPRINT-v1\n');subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'add','.'],check=True);subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'commit','-qm','old'],check=True);s=subprocess.check_output(['/usr/bin/git','-C',str(self.f.repo),'rev-parse','HEAD'],text=True).strip();self.no(lambda:go.candidate(self.f.repo,s))
 def test_private_device_custody_and_installer_drift_rejected(self):
  self.f.dev.chmod(0o644);self.no(self.f.build);self.f.dev.chmod(0o600)
  def bad(r,s,d):x=self.f.inst(r,s,d);x['bundleIdentifier']='bad';return x
  self.no(lambda:self.f.build(run_installer=bad))
 def test_installer_never_runs_before_public_visual_acceptance(self):
  calls=[]
  def run(r,s,d):calls.append(s);return self.f.inst(r,s,d)
  i=self.f.ids['Capture Field Build Provenance'];self.f.map[f'/actions/runs/{i}']['conclusion']='cancelled';self.no(lambda:self.f.build(run_installer=run));self.assertEqual(calls,[])
 def test_post_install_revalidation_rejects_authority_drift(self):
  pull=f'/pulls/{self.f.pr}'
  def move_pr(r,s,d):x=self.f.inst(r,s,d);self.f.map[pull]['head']['sha']='1'*40;return x
  self.no(lambda:self.f.build(run_installer=move_pr));self.f.map[pull]['head']['sha']=self.f.s
  artifact=f'/actions/artifacts/{self.f.aid}'
  def expire(r,s,d):x=self.f.inst(r,s,d);self.f.map[artifact]['expired']=True;return x
  self.no(lambda:self.f.build(run_installer=expire));self.f.map[artifact]['expired']=False
  def change_device(r,s,d):x=self.f.inst(r,s,d);self.f.dev.write_text('other-device\n');return x
  self.no(lambda:self.f.build(run_installer=change_device))
if __name__=='__main__':unittest.main(verbosity=2)
