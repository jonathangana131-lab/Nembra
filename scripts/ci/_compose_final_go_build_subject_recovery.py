#!/usr/bin/env python3
from pathlib import Path
import re

S=Path('scripts/ci/es80_authenticated_stationary_final_go.py')
T=Path('scripts/ci/tests/test_es80_authenticated_stationary_final_go.py')
E=Path('scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py')

def one(text, old, new, label):
    n=text.count(old)
    if n!=1: raise SystemExit(f'{label}: expected 1 anchor, found {n}')
    return text.replace(old,new,1)

s=S.read_text()
s=one(s,'INSTALLER="scripts/field/install_one_time_capture.command"; RUNBOOK="docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"; IDENTITY="NembraApp/App/NembraCaptureBuildIdentity.swift"\n','INSTALLER="scripts/field/install_one_time_capture.command"; RUNBOOK="docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"; IDENTITY="NembraApp/App/NembraCaptureBuildIdentity.swift"\nBOOTSTRAP="Scripts/bootstrap_capture_tuya_sdk.sh"; BUILD_SUBJECT_HELPER="Scripts/capture_cocoapods_build_subject.py"\n','constants')
old='''def review(pr:int,review_id:int,source:str,v:dict[str,Any],get=api):
    review_id=pos(review_id,"candidate review ID"); raw,r=get(f"/pulls/{pr}/reviews/{review_id}")
    body=r.get("body")
    if not isinstance(body,str) or not body.strip(): raise GoError("GitHub candidate review body missing")
    b=obj(body.encode(),"GitHub candidate review body")
    keys={"schemaVersion","authority","sourceCommitSHA","visualRunID","visualArtifactID","standardScreenshotSHA256","accessibilityScreenshotSHA256","tuyaDependencyLockSHA256","verdict"}; lock=b.get("tuyaDependencyLockSHA256")
    user=r.get("user",{})
    if set(b)!=keys or b.get("schemaVersion")!=2 or b.get("authority")!="nembra-capture-human-review-github-v2" or canon(b.get("sourceCommitSHA"),"candidate review source")!=source or b.get("visualRunID")!=v["runID"] or b.get("visualArtifactID")!=v["artifactID"] or not isinstance(lock,str) or not HEX64.fullmatch(lock) or lock!=lock.lower() or b.get("verdict")!="accepted": raise GoError("GitHub candidate review authority mismatch")
    if r.get("id")!=review_id or r.get("state") not in {"COMMENTED","APPROVED"} or canon(r.get("commit_id"),"candidate review commit")!=source or user.get("login")!=OWNER or r.get("author_association")!="OWNER": raise GoError("GitHub candidate review custody mismatch")
    stamp=r.get("submitted_at")
    if not isinstance(stamp,str) or not stamp.endswith("Z"): raise GoError("GitHub candidate review timestamp invalid")
    try: datetime.fromisoformat(stamp[:-1]+"+00:00")
    except ValueError as e: raise GoError("GitHub candidate review timestamp invalid") from e
    s=v["screenshots"]; std=s["unprovisioned-dark-standard"]["sha256"]; ax=s["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    if b["standardScreenshotSHA256"]!=std or b["accessibilityScreenshotSHA256"]!=ax: raise GoError("GitHub candidate review screenshot mismatch")
    return {"authority":b["authority"],"reviewID":review_id,"reviewNodeID":r.get("node_id"),"reviewBodySHA256":sha(body.encode()),"reviewedAtUTC":stamp,"reviewer":OWNER,"state":r["state"],"verdict":"accepted","standardScreenshotSHA256":std,"accessibilityScreenshotSHA256":ax,"tuyaDependencyLockSHA256":lock}
'''
new=old.replace('"tuyaDependencyLockSHA256","verdict"}; lock=b.get("tuyaDependencyLockSHA256")','"tuyaDependencyLockSHA256","cocoaPodsBuildSubjectSHA256","verdict"}; lock=b.get("tuyaDependencyLockSHA256"); build_subject=b.get("cocoaPodsBuildSubjectSHA256")').replace('b.get("schemaVersion")!=2 or b.get("authority")!="nembra-capture-human-review-github-v2"','b.get("schemaVersion")!=3 or b.get("authority")!="nembra-capture-human-review-github-v3"').replace('or b.get("verdict")!="accepted"','or not isinstance(build_subject,str) or not HEX64.fullmatch(build_subject) or build_subject!=build_subject.lower() or b.get("verdict")!="accepted"').replace('"tuyaDependencyLockSHA256":lock}','"tuyaDependencyLockSHA256":lock,"cocoaPodsBuildSubjectSHA256":build_subject}')
s=one(s,old,new,'review')
start=s.index('def candidate(repo:Path,source:str):\n'); end=s.index('\ndef device_hash(path:Path):\n',start)
s=s[:start]+'''def candidate(repo:Path,source:str):
    root=repo.expanduser().resolve(strict=True)
    if canon(git(root,"rev-parse","HEAD"),"candidate HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("candidate checkout is not exact clean accepted source")
    authority_paths={"installer":INSTALLER,"runbook":RUNBOOK,"buildIdentity":IDENTITY,"bootstrap":BOOTSTRAP,"cocoaPodsBuildSubjectHelper":BUILD_SUBJECT_HELPER}
    blobs={k:git(root,"rev-parse",f"HEAD:{p}").lower() for k,p in authority_paths.items()}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",x) for x in blobs.values()): raise GoError("candidate Git blob invalid")
    paths={key:root/relative for key,relative in authority_paths.items()}
    if any(not p.is_file() or p.is_symlink() for p in paths.values()): raise GoError("candidate authority path is not a regular non-symlink file")
    for key,relative in authority_paths.items():
        verbose=git(root,"ls-files","-v","--",relative); tagged=git(root,"ls-files","-t","--",relative)
        if not verbose or verbose[:1].islower() or tagged.startswith("S "): raise GoError("candidate authority path has suppressed index worktree tracking")
        if git(root,"hash-object","--no-filters","--",relative).lower()!=blobs[key]: raise GoError("candidate authority worktree bytes differ from accepted Git blob")
    ins=paths["installer"].read_text(); rb=paths["runbook"].read_text(); ident=paths["buildIdentity"].read_text(); bootstrap=paths["bootstrap"].read_text(); helper=paths["cocoaPodsBuildSubjectHelper"].read_text()
    if "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" not in ins or "hmac.compare_digest(actual_digest, expected_digest)" not in ins: raise GoError("candidate installer lacks intended-device digest rendezvous")
    if "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" not in bootstrap or "nembra-cocoapods-build-subject-v1" not in helper: raise GoError("candidate lacks reviewed generated CocoaPods build-subject authority")
    if f'PROCEDURE_ID="{PROC}"' not in ins or f'BUNDLE_ID="{BUNDLE}"' not in ins or f"PROCEDURE_ID: `{PROC}`" not in rb or f'static let requiredFieldProcedureIdentifier = "{PROC}"' not in ident or "ES80-FINGERPRINT-v1" in ins or "NEMBRA_ES80_TODAY_RESEARCH" in ins: raise GoError("candidate carries wrong/retired field authority")
    return {"sourceCommitSHA":source,"installerGitBlob":blobs["installer"],"runbookGitBlob":blobs["runbook"],"buildIdentityGitBlob":blobs["buildIdentity"],"bootstrapGitBlob":blobs["bootstrap"],"cocoaPodsBuildSubjectHelperGitBlob":blobs["cocoaPodsBuildSubjectHelper"]}
'''+s[end:]
start=s.index('def installer_environment(device:Path,device_digest:str,accepted_lock_sha256:str)->dict[str,str]:\n'); end=s.index('\ndef _accepted_installer_bytes',start)
s=s[:start]+'''def installer_environment(device:Path,device_digest:str,accepted_lock_sha256:str,accepted_build_subject_sha256:str)->dict[str,str]:
    account=pwd.getpwuid(os.getuid()); device_path=canonical_private_path(device,"private intended-device identifier")
    digest=device_digest.lower()
    if not HEX64.fullmatch(digest): raise GoError("private intended-device digest invalid")
    if not isinstance(accepted_lock_sha256,str) or not HEX64.fullmatch(accepted_lock_sha256) or accepted_lock_sha256!=accepted_lock_sha256.lower(): raise GoError("accepted Tuya dependency-lock digest is not canonical lowercase SHA-256")
    if not isinstance(accepted_build_subject_sha256,str) or not HEX64.fullmatch(accepted_build_subject_sha256) or accepted_build_subject_sha256!=accepted_build_subject_sha256.lower(): raise GoError("accepted CocoaPods generated build-subject digest is not canonical lowercase SHA-256")
    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","GIT_NO_REPLACE_OBJECTS":"1","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest,"NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256":accepted_lock_sha256,"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256":accepted_build_subject_sha256}
'''+s[end:]
s=one(s,'def installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha256:str):\n    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest,accepted_lock_sha256)\n','def installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha256:str,accepted_build_subject_sha256:str):\n    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest,accepted_lock_sha256,accepted_build_subject_sha256)\n','installer signature')
s=one(s,'got=run_installer(candidate_repo,source,device_file,dh,rv["tuyaDependencyLockSHA256"]); expected=','got=run_installer(candidate_repo,source,device_file,dh,rv["tuyaDependencyLockSHA256"],rv["cocoaPodsBuildSubjectSHA256"]); expected=','handoff')
s=one(s,'"acceptedTuyaDependencyLockSHA256":rv["tuyaDependencyLockSHA256"],"candidateSource":cs,','"acceptedTuyaDependencyLockSHA256":rv["tuyaDependencyLockSHA256"],"acceptedCocoaPodsBuildSubjectSHA256":rv["cocoaPodsBuildSubjectSHA256"],"candidateSource":cs,','record')
S.write_text(s)

t=T.read_text()
t=one(t,"go.IDENTITY:f'static let requiredFieldProcedureIdentifier = \"{go.PROC}\"\\n'}.items()","go.IDENTITY:f'static let requiredFieldProcedureIdentifier = \"{go.PROC}\"\\n',go.BOOTSTRAP:'# NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256\\n',go.BUILD_SUBJECT_HELPER:'SCHEMA = b\"nembra-cocoapods-build-subject-v1\"\\n'}.items()",'test paths')
t=one(t,"self.lock='a'*64\n","self.lock='a'*64;self.build_subject='9'*64\n",'test subject')
t=one(t,"d={'schemaVersion':2,'authority':'nembra-capture-human-review-github-v2','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'tuyaDependencyLockSHA256':self.lock,'verdict':'accepted'}","d={'schemaVersion':3,'authority':'nembra-capture-human-review-github-v3','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'tuyaDependencyLockSHA256':self.lock,'cocoaPodsBuildSubjectSHA256':self.build_subject,'verdict':'accepted'}",'test review')
t=one(t," def inst(self,repo,s,dev,h,lock):\n  assert h==H(b'device-token');assert lock==self.lock\n"," def inst(self,repo,s,dev,h,lock,build_subject):\n  assert h==H(b'device-token');assert lock==self.lock;assert build_subject==self.build_subject\n",'test installer')
t=t.replace("r['body']='{\"schemaVersion\":2,\"schemaVersion\":2}'","r['body']='{\"schemaVersion\":3,\"schemaVersion\":3}'")
t=re.sub(r'def (capture|drift|bad|run|merge_pr|move_pr|expire|dismiss|change_device|move_main)\((r,s,d,h,lock)\):',r'def \1(\2,build_subject):',t)
t=t.replace('self.f.inst(r,s,d,h,lock)','self.f.inst(r,s,d,h,lock,build_subject)')
t=one(t," def test_prechecked_device_digest_is_passed_to_installer(self):\n  seen=[]\n  def capture(r,s,d,h,lock,build_subject):seen.append((h,lock));return self.f.inst(r,s,d,h,lock,build_subject)\n  self.assertEqual(self.f.build(run_installer=capture)['status'],'GO')\n  self.assertEqual(seen,[(H(b'device-token'),self.f.lock)])\n"," def test_prechecked_device_and_reviewed_build_digests_are_passed_to_installer(self):\n  seen=[]\n  def capture(r,s,d,h,lock,build_subject):seen.append((h,lock,build_subject));return self.f.inst(r,s,d,h,lock,build_subject)\n  self.assertEqual(self.f.build(run_installer=capture)['status'],'GO')\n  self.assertEqual(seen,[(H(b'device-token'),self.f.lock,self.f.build_subject)])\n",'test handoff')
anchor=" def test_reviewed_tuya_lock_rejected_before_installer_if_noncanonical(self):\n"
extra=''' def test_reviewed_cocoapods_subject_is_bound_to_go_record(self):
  r=self.f.build();self.assertEqual(r['acceptedCocoaPodsBuildSubjectSHA256'],self.f.build_subject);self.assertEqual(r['visualReview']['cocoaPodsBuildSubjectSHA256'],self.f.build_subject)
 def test_reviewed_cocoapods_subject_rejected_before_installer_if_noncanonical(self):
  calls=[]
  def capture(r,s,d,h,lock,build_subject):calls.append(build_subject);return self.f.inst(r,s,d,h,lock,build_subject)
  self.f.build_subject='A'*64;self.f.write_review();self.no(lambda:self.f.build(run_installer=capture));self.assertEqual(calls,[])
 def test_reviewed_cocoapods_subject_drift_after_install_is_rejected(self):
  review=f'/pulls/{self.f.pr}/reviews/{self.f.rid}'
  def drift(r,s,d,h,lock,build_subject):x=self.f.inst(r,s,d,h,lock,build_subject);self.f.map[review]['body']=self.f.body(cocoaPodsBuildSubjectSHA256='8'*64);return x
  self.no(lambda:self.f.build(run_installer=drift))
'''
t=one(t,anchor,extra+anchor,'subject tests')
anchor=" def test_current_main_is_bound_and_must_be_candidate_ancestor(self):\n"
extra=''' def test_candidate_rejects_hidden_build_subject_helper_tamper(self):
  path=self.f.repo/go.BUILD_SUBJECT_HELPER
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--assume-unchanged',go.BUILD_SUBJECT_HELPER],check=True)
  path.write_text('# substituted helper\\n')
  self.no(lambda:go.candidate(self.f.repo,self.f.s))
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--no-assume-unchanged',go.BUILD_SUBJECT_HELPER],check=True)
  subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'checkout','--',go.BUILD_SUBJECT_HELPER],check=True)
'''
t=one(t,anchor,extra+anchor,'hidden test')
T.write_text(t)

e=E.read_text()
e=one(e,'            accepted_lock = "e" * 64\n','            accepted_lock = "e" * 64\n            accepted_build_subject = "d" * 64\n','env subject')
e=one(e,'                f"[[ \\\"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\\\" == {accepted_lock!r} ]] || exit 48\\n"\n                "[[ \\\"${GIT_NO_REPLACE_OBJECTS:-}\\\" == 1 ]] || exit 49\\n"','                f"[[ \\\"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\\\" == {accepted_lock!r} ]] || exit 48\\n"\n                f"[[ \\\"${{NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256:-}}\\\" == {accepted_build_subject!r} ]] || exit 49\\n"\n                "[[ \\\"${GIT_NO_REPLACE_OBJECTS:-}\\\" == 1 ]] || exit 50\\n"','env assertions')
e=e.replace('                f"[[ \\\"$0\\\" == {str(installer)!r} ]] || exit 50\\n"','                f"[[ \\\"$0\\\" == {str(installer)!r} ]] || exit 51\\n"')
e=one(e,'            os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "f" * 64\n','            os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "f" * 64\n            os.environ["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"] = "c" * 64\n','env ambient')
e=one(e,'                result = GO.installer(repository, source, private_device, GO.device_hash(private_device), accepted_lock)\n','                result = GO.installer(repository, source, private_device, GO.device_hash(private_device), accepted_lock, accepted_build_subject)\n','env call')
e=e.replace('GO.installer(repository, source, device, GO.device_hash(device), "e" * 64)','GO.installer(repository, source, device, GO.device_hash(device), "e" * 64, "d" * 64)')
e=one(e,'            accepted_lock = "e" * 64\n            env = GO.installer_environment(device, digest, accepted_lock)\n','            accepted_lock = "e" * 64\n            accepted_build_subject = "d" * 64\n            env = GO.installer_environment(device, digest, accepted_lock, accepted_build_subject)\n','env allowlist')
e=one(e,'            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"], accepted_lock)\n','            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"], accepted_lock)\n            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256"], accepted_build_subject)\n','env assert')
e=e.replace('GO.installer_environment(device, digest, lock)','GO.installer_environment(device, digest, lock, "d" * 64)')
e=e.replace('GO.installer_environment(alias / "device", "a" * 64, "e" * 64)','GO.installer_environment(alias / "device", "a" * 64, "e" * 64, "d" * 64)')
anchor='    def test_installer_environment_rejects_symlinked_private_device_parent(self) -> None:\n'
extra='''    def test_installer_environment_rejects_noncanonical_reviewed_build_subject(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-subject-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"; device.write_text("device", encoding="utf-8"); device.chmod(0o600)
            digest = GO.device_hash(device)
            for subject in ("A" * 64, "a" * 63, "not-a-digest"):
                with self.assertRaises(GO.GoError): GO.installer_environment(device, digest, "e" * 64, subject)

'''
e=one(e,anchor,extra+anchor,'env invalid subject')
E.write_text(e)
