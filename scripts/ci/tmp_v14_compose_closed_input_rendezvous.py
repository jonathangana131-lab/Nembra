#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
DEVICE_HEAD='a33bce5c8083a13f349c1a974c28dc0df1e50c79'
LOCK_HEAD='d8416aeba19b826cfb50bde9e0b3e2778766a286'
BASE='5fc7eb8f0eb08ae309e021ed4c8c3c62d543300c'
ISS='scripts/ci/es80_authenticated_stationary_final_go.py'
TEST='scripts/ci/tests/test_es80_authenticated_stationary_final_go.py'
ENVTEST='scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py'
SIGNEDTEST='scripts/ci/tests/test_es80_authenticated_stationary_signed_artifact.py'

def sh(*args:str, capture=False)->str:
    p=subprocess.run(list(args),cwd=ROOT,check=True,text=True,stdout=subprocess.PIPE if capture else None)
    return p.stdout if capture else ''

def show(sha:str,path:str)->str:
    return sh('git','show',f'{sha}:{path}',capture=True)

def block(text:str,start:str,end:str)->str:
    a=text.index(start); b=text.index(end,a); return text[a:b]

sh('git','fetch','--no-tags','origin',DEVICE_HEAD,LOCK_HEAD)

# Production: preserve live control/public authority, transplant only proven device and review blocks.
issuer_path=ROOT/ISS
issuer=issuer_path.read_text()
device_issuer=show(DEVICE_HEAD,ISS)
lock_issuer=show(LOCK_HEAD,ISS)
review_block=block(lock_issuer,'def review(','\ndef git(')
issuer=issuer[:issuer.index('def review(')] + review_block + issuer[issuer.index('\ndef git(',issuer.index('def review('))+1:]
device_block=block(device_issuer,'def candidate(','\ndef retained_signed_artifact(')
cs=issuer.index('def candidate('); ce=issuer.index('\ndef retained_signed_artifact(',cs)
issuer=issuer[:cs]+device_block+issuer[ce:]

old='''def installer_environment(device:Path,device_digest:str)->dict[str,str]:
    account=pwd.getpwuid(os.getuid()); device_path=canonical_private_path(device,"private intended-device identifier")
    digest=device_digest.lower()
    if not HEX64.fullmatch(digest): raise GoError("private intended-device digest invalid")
    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest}

def installer(repo:Path,source:str,device:Path,device_digest:str):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest)
'''
new='''def installer_environment(device:Path,device_digest:str,accepted_lock_sha256:str)->dict[str,str]:
    account=pwd.getpwuid(os.getuid()); device_path=canonical_private_path(device,"private intended-device identifier")
    digest=device_digest.lower()
    if not HEX64.fullmatch(digest): raise GoError("private intended-device digest invalid")
    if not isinstance(accepted_lock_sha256,str) or not HEX64.fullmatch(accepted_lock_sha256) or accepted_lock_sha256!=accepted_lock_sha256.lower(): raise GoError("accepted Tuya dependency-lock digest is not canonical lowercase SHA-256")
    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest,"NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256":accepted_lock_sha256}

def installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha256:str):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest,accepted_lock_sha256)
'''
if issuer.count(old)!=1: raise SystemExit('strong device installer block drifted')
issuer=issuer.replace(old,new,1)
old_call='    got=run_installer(candidate_repo,source,device_file,dh); expected='
if issuer.count(old_call)!=1: raise SystemExit('device build handoff seam drifted')
issuer=issuer.replace(old_call,'    got=run_installer(candidate_repo,source,device_file,dh,rv["tuyaDependencyLockSHA256"]); expected=',1)
needle='    if not HEX64.fullmatch(signed["tuyaDependencyLockSHA256"]) or not HEX64.fullmatch(signed["retainedIPASHA256"]) or not HEX64.fullmatch(signed["retainedAppTreeSHA256"]) or not HEX64.fullmatch(signed["embeddedProvisioningProfileSHA256"]): raise GoError("retained signed artifact digest invalid")\n'
if issuer.count(needle)!=1: raise SystemExit('signed digest seam drifted')
issuer=issuer.replace(needle,needle+'    if signed["tuyaDependencyLockSHA256"]!=rv["tuyaDependencyLockSHA256"]: raise GoError("retained signed artifact Tuya dependency lock does not match prebuild GitHub review")\n',1)
ret='"visualReview":rv,"candidateSource":cs'
if issuer.count(ret)!=1: raise SystemExit('result seam drifted')
issuer=issuer.replace(ret,'"visualReview":rv,"acceptedTuyaDependencyLockSHA256":rv["tuyaDependencyLockSHA256"],"candidateSource":cs',1)
for token in ('mainSHA","state"','GO control plane does not contain the exact current main authority','NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256','hmac.compare_digest(actual_digest, expected_digest)','nembra-capture-human-review-github-v2','NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256'):
    if token not in issuer: raise SystemExit(f'missing preserved/composed authority token: {token}')
issuer_path.write_text(issuer)

# Main adversarial suite: start from exact-green strong-device fixture, preserve live control-main regression, then bind lock.
current_test=(ROOT/TEST).read_text()
control_method=block(current_test,' def test_go_control_plane_requires_exact_current_main_ancestor(self):',' def test_production_default_refuses_go_without_retained_signed_artifact_authority')
t=show(DEVICE_HEAD,TEST)
insert=' def test_production_default_refuses_go_without_retained_signed_artifact_authority'
if control_method not in t:
    t=t.replace(insert,control_method+insert,1)
old="  subprocess.run(['/usr/bin/git','-C',str(self.repo),'add','.'],check=True);subprocess.run(['/usr/bin/git','-C',str(self.repo),'commit','-qm','f'],check=True);self.s=subprocess.check_output(['/usr/bin/git','-C',str(self.repo),'rev-parse','HEAD'],text=True).strip();self.pr=2612;self.ids={n:100+i for i,n in enumerate(go.WORKFLOWS)};self.aid=99;self.rid=88\n"
new=old.rstrip('\n')+";self.lock='a'*64\n"
if t.count(old)!=1: raise SystemExit('fixture identity seam drifted')
t=t.replace(old,new,1)
old_body="  d={'schemaVersion':1,'authority':'nembra-visual-human-review-github-v1','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'verdict':'accepted'};d.update(x);return json.dumps(d,sort_keys=True)"
new_body="  d={'schemaVersion':2,'authority':'nembra-capture-human-review-github-v2','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'tuyaDependencyLockSHA256':self.lock,'verdict':'accepted'};d.update(x);return json.dumps(d,sort_keys=True)"
if t.count(old_body)!=1: raise SystemExit('review fixture seam drifted')
t=t.replace(old_body,new_body,1)
old_inst=" def inst(self,repo,s,dev,h):\n  assert h==H(b'device-token')\n"
new_inst=" def inst(self,repo,s,dev,h,lock):\n  assert h==H(b'device-token');assert lock==self.lock\n"
if t.count(old_inst)!=1: raise SystemExit('fixture installer seam drifted')
t=t.replace(old_inst,new_inst,1)
t=t.replace("'tuyaDependencyLockSHA256':'a'*64","'tuyaDependencyLockSHA256':self.lock",1)
# Every injected installer callback on the strong-device suite now receives both closed-input hashes.
t=t.replace('(r,s,d,h):','(r,s,d,h,lock):')
t=t.replace('self.f.inst(r,s,d,h)','self.f.inst(r,s,d,h,lock)')
# Strengthen the dedicated handoff test to prove both exact values cross together.
t=t.replace("def capture(r,s,d,h,lock):seen.append(h);return self.f.inst(r,s,d,h,lock)","def capture(r,s,d,h,lock):seen.append((h,lock));return self.f.inst(r,s,d,h,lock)")
t=t.replace("self.assertEqual(seen,[H(b'device-token')])","self.assertEqual(seen,[(H(b'device-token'),self.f.lock)])")
# Lock-specific acceptance regressions.
marker=" def test_private_device_custody_and_installer_drift_rejected(self):\n"
extra=""" def test_reviewed_tuya_lock_is_bound_to_signed_artifact(self):
  r=self.f.build();self.assertEqual(r['acceptedTuyaDependencyLockSHA256'],self.f.lock);self.assertEqual(r['visualReview']['tuyaDependencyLockSHA256'],self.f.lock)
  def bad(repo,s,dev,install,output):x=self.f.signed(repo,s,dev,install,output);x['tuyaDependencyLockSHA256']='f'*64;return x
  self.no(lambda:self.f.build(inspect_signed_artifact=bad))
 def test_noncanonical_or_drifting_reviewed_tuya_lock_rejected_before_install(self):
  calls=[]
  def capture(r,s,d,h,lock):calls.append(lock);return self.f.inst(r,s,d,h,lock)
  self.f.lock='A'*64;self.f.write_review();self.no(lambda:self.f.build(run_installer=capture));self.assertEqual(calls,[])
  self.f.lock='a'*64;self.f.write_review();review=f'/pulls/{self.f.pr}/reviews/{self.f.rid}'
  def drift(r,s,d,h,lock):x=self.f.inst(r,s,d,h,lock);self.f.map[review]['body']=self.f.body(tuyaDependencyLockSHA256='b'*64);return x
  self.no(lambda:self.f.build(run_installer=drift))
"""
if t.count(marker)!=1: raise SystemExit('test insertion seam drifted')
t=t.replace(marker,extra+marker,1)
# Update malformed duplicate schema sample for current authority vocabulary.
t=t.replace("r['body']='{\"schemaVersion\":1,\"schemaVersion\":1}'","r['body']='{\"schemaVersion\":2,\"schemaVersion\":2}'")
(ROOT/TEST).write_text(t)

# Environment suite: exact-green strong-device custody + reviewed lock, no ambient inheritance.
e=show(DEVICE_HEAD,ENVTEST)
e=e.replace('            installer = repository / GO.INSTALLER\n','            accepted_lock = "e" * 64\n            installer = repository / GO.INSTALLER\n',1)
e=e.replace('                f"[[ \\\"${{PATH:-}}\\\" == {GO.TRUSTED_INSTALLER_PATH!r} ]] || exit 46\\n"\n','                f"[[ \\\"${{PATH:-}}\\\" == {GO.TRUSTED_INSTALLER_PATH!r} ]] || exit 46\\n"\n                f"[[ \\\"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\\\" == {accepted_lock!r} ]] || exit 48\\n"\n',1)
e=e.replace('            os.environ["NEMBRA_TUYA_APP_KEY"] = "caller-key-must-not-cross"\n','            os.environ["NEMBRA_TUYA_APP_KEY"] = "caller-key-must-not-cross"\n            os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "f" * 64\n',1)
e=e.replace('result = GO.installer(repository, source, private_device, GO.device_hash(private_device))','result = GO.installer(repository, source, private_device, GO.device_hash(private_device), accepted_lock)',1)
e=e.replace('            env = GO.installer_environment(device, digest)\n','            accepted_lock = "e" * 64\n            env = GO.installer_environment(device, digest, accepted_lock)\n',1)
e=e.replace('            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], digest)\n','            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], digest)\n            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"], accepted_lock)\n',1)
e=e.replace('GO.installer_environment(alias / "device", "a" * 64)','GO.installer_environment(alias / "device", "a" * 64, "e" * 64)',1)
marker='    def test_installer_environment_rejects_symlinked_private_device_parent(self) -> None:\n'
extra='''    def test_installer_environment_rejects_noncanonical_reviewed_lock(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-lock-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            digest = GO.device_hash(device)
            for lock in ("A" * 64, "a" * 63, "not-a-digest"):
                with self.assertRaises(GO.GoError):
                    GO.installer_environment(device, digest, lock)

'''
if e.count(marker)!=1: raise SystemExit('environment test insertion seam drifted')
e=e.replace(marker,extra+marker,1)
(ROOT/ENVTEST).write_text(e)

os.environ['PYTHONDONTWRITEBYTECODE']='1'
for p in (ISS,TEST,ENVTEST): compile((ROOT/p).read_text(),p,'exec')
sh('python3','-B',TEST)
sh('python3','-B',ENVTEST)
sh('python3','-B',SIGNEDTEST)
if any(ROOT.glob('scripts/ci/**/__pycache__')): raise SystemExit('bytecode residue created')
changed=sorted(x for x in sh('git','diff','--name-only',BASE,capture=True).splitlines() if x!='scripts/ci/tmp_v14_compose_closed_input_rendezvous.py')
expected=sorted([ISS,TEST,ENVTEST])
if changed!=expected: raise SystemExit(f'unexpected product scope {changed!r}')
print('closed-input rendezvous composition validated')
