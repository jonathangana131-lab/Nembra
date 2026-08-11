#!/usr/bin/env python3
from pathlib import Path
import re

issuer_path = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
issuer = issuer_path.read_text()

# 1) Advance the exact GitHub owner review from pixel-only v1 to one strict
# candidate review that binds pixels + the reviewed dependency lock + the
# CocoaPods generated build subject to the same exact candidate SHA.
start = issuer.index("def review(pr:int,review_id:int,source:str,v:dict[str,Any],get=api):\n")
end = issuer.index("def git(repo:Path,*args):\n", start)
review_fn = '''def review(pr:int,review_id:int,source:str,v:dict[str,Any],get=api):
    review_id=pos(review_id,"candidate review ID"); raw,r=get(f"/pulls/{pr}/reviews/{review_id}")
    body=r.get("body")
    if not isinstance(body,str) or not body.strip(): raise GoError("GitHub candidate review body missing")
    b=obj(body.encode(),"GitHub candidate review body")
    keys={"schemaVersion","authority","sourceCommitSHA","visualRunID","visualArtifactID","standardScreenshotSHA256","accessibilityScreenshotSHA256","tuyaDependencyLockSHA256","cocoaPodsBuildSubjectSHA256","verdict"}
    lock=b.get("tuyaDependencyLockSHA256"); cocoa=b.get("cocoaPodsBuildSubjectSHA256"); user=r.get("user",{})
    if set(b)!=keys or b.get("schemaVersion")!=3 or b.get("authority")!="nembra-capture-human-review-github-v3" or canon(b.get("sourceCommitSHA"),"candidate review source")!=source or b.get("visualRunID")!=v["runID"] or b.get("visualArtifactID")!=v["artifactID"] or not isinstance(lock,str) or not HEX64.fullmatch(lock) or lock!=lock.lower() or not isinstance(cocoa,str) or not HEX64.fullmatch(cocoa) or cocoa!=cocoa.lower() or b.get("verdict")!="accepted": raise GoError("GitHub candidate review authority mismatch")
    if r.get("id")!=review_id or r.get("state") not in {"COMMENTED","APPROVED"} or canon(r.get("commit_id"),"candidate review commit")!=source or user.get("login")!=OWNER or r.get("author_association")!="OWNER": raise GoError("GitHub candidate review custody mismatch")
    stamp=r.get("submitted_at")
    if not isinstance(stamp,str) or not stamp.endswith("Z"): raise GoError("GitHub candidate review timestamp invalid")
    try: datetime.fromisoformat(stamp[:-1]+"+00:00")
    except ValueError as e: raise GoError("GitHub candidate review timestamp invalid") from e
    s=v["screenshots"]; std=s["unprovisioned-dark-standard"]["sha256"]; ax=s["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    if b["standardScreenshotSHA256"]!=std or b["accessibilityScreenshotSHA256"]!=ax: raise GoError("GitHub candidate review screenshot mismatch")
    return {"authority":b["authority"],"reviewID":review_id,"reviewNodeID":r.get("node_id"),"reviewBodySHA256":sha(body.encode()),"reviewedAtUTC":stamp,"reviewer":OWNER,"state":r["state"],"verdict":"accepted","standardScreenshotSHA256":std,"accessibilityScreenshotSHA256":ax,"tuyaDependencyLockSHA256":lock,"cocoaPodsBuildSubjectSHA256":cocoa}

'''
issuer = issuer[:start] + review_fn + issuer[end:]

# 2) Candidate custody must cover the executable field-build authority chain,
# not only the top-level installer. Reject assume-unchanged/skip-worktree flags
# globally so arbitrary accepted source/build inputs cannot be hidden from the
# clean-check before a private build.
start = issuer.index("def candidate(repo:Path,source:str):\n")
end = issuer.index("def device_hash(path:Path):\n", start)
candidate_fn = '''def candidate(repo:Path,source:str):
    root=repo.expanduser().resolve(strict=True)
    if canon(git(root,"rev-parse","HEAD"),"candidate HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("candidate checkout is not exact clean accepted source")
    verbose_all=git(root,"ls-files","-v","-z").split("\\0"); tagged_all=git(root,"ls-files","-t","-z").split("\\0")
    if any(record and record[0].islower() for record in verbose_all) or any(record.startswith("S ") for record in tagged_all): raise GoError("candidate checkout has suppressed index worktree tracking")
    authority_paths={
        "installer":INSTALLER,
        "runbook":RUNBOOK,
        "buildIdentity":IDENTITY,
        "bootstrap":"Scripts/bootstrap_capture_tuya_sdk.sh",
        "privateDeviceReader":"scripts/ci/es80_signed_field_artifact_private_runner.py",
        "privateInputProvenance":"Scripts/capture_tuya_private_input_provenance.py",
        "privateBuildGuard":"Scripts/capture_tuya_private_input_build_guard.py",
        "cocoaPodsBuildSubject":"Scripts/capture_cocoapods_build_subject.py",
    }
    blobs={k:git(root,"rev-parse",f"HEAD:{p}").lower() for k,p in authority_paths.items()}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",x) for x in blobs.values()): raise GoError("candidate Git blob invalid")
    paths={key:root/relative for key,relative in authority_paths.items()}
    if any(not p.is_file() or p.is_symlink() for p in paths.values()): raise GoError("candidate authority path is not a regular non-symlink file")
    for key,relative in authority_paths.items():
        actual_blob=git(root,"hash-object","--no-filters","--",relative).lower()
        if actual_blob!=blobs[key]: raise GoError("candidate authority worktree bytes differ from accepted Git blob")
    ins=paths["installer"].read_text(); rb=paths["runbook"].read_text(); ident=paths["buildIdentity"].read_text(); bootstrap=paths["bootstrap"].read_text(); reader=paths["privateDeviceReader"].read_text(); provenance=paths["privateInputProvenance"].read_text(); guard=paths["privateBuildGuard"].read_text(); cocoa_helper=paths["cocoaPodsBuildSubject"].read_text()
    if "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" not in ins or "hmac.compare_digest(actual_digest, expected_digest)" not in ins: raise GoError("candidate installer lacks intended-device digest rendezvous")
    if "NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" not in bootstrap or "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SHA256" not in bootstrap or "capture_cocoapods_build_subject.py" not in bootstrap: raise GoError("candidate bootstrap lacks reviewed dependency/generated-build rendezvous")
    if "def read_private_identifier(" not in reader or "O_NOFOLLOW" not in reader or "O_DIRECTORY" not in reader: raise GoError("candidate private intended-device reader authority missing")
    if "nembra-capture-tuya-dependencies-v2" not in provenance or "KqueueVnodeBackend" not in guard or "nembra-capture-cocoapods-build-subject-v1" not in cocoa_helper: raise GoError("candidate field-build provenance authority missing")
    if f'PROCEDURE_ID="{PROC}"' not in ins or f'BUNDLE_ID="{BUNDLE}"' not in ins or f"PROCEDURE_ID: `{PROC}`" not in rb or f'static let requiredFieldProcedureIdentifier = "{PROC}"' not in ident or "ES80-FINGERPRINT-v1" in ins or "NEMBRA_ES80_TODAY_RESEARCH" in ins: raise GoError("candidate carries wrong/retired field authority")
    return {"sourceCommitSHA":source,**{f"{key}GitBlob":value for key,value in blobs.items()}}

'''
issuer = issuer[:start] + candidate_fn + issuer[end:]

# 3) Keep the already accepted prechecked device digest and add exactly the two
# GitHub-reviewed generated-build subjects to the otherwise closed environment.
start = issuer.index("def installer_environment(device:Path,device_digest:str)->dict[str,str]:\n")
end = issuer.index("def retained_signed_artifact(", start)
install_fns = '''def installer_environment(device:Path,device_digest:str,accepted_lock_sha256:str,accepted_cocoa_sha256:str)->dict[str,str]:
    account=pwd.getpwuid(os.getuid()); device_path=canonical_private_path(device,"private intended-device identifier")
    digest=device_digest.lower()
    if not HEX64.fullmatch(digest): raise GoError("private intended-device digest invalid")
    if not isinstance(accepted_lock_sha256,str) or not HEX64.fullmatch(accepted_lock_sha256) or accepted_lock_sha256!=accepted_lock_sha256.lower(): raise GoError("accepted Tuya dependency-lock digest is not canonical lowercase SHA-256")
    if not isinstance(accepted_cocoa_sha256,str) or not HEX64.fullmatch(accepted_cocoa_sha256) or accepted_cocoa_sha256!=accepted_cocoa_sha256.lower(): raise GoError("accepted CocoaPods generated-build digest is not canonical lowercase SHA-256")
    return {"PATH":TRUSTED_INSTALLER_PATH,"HOME":account.pw_dir,"USER":account.pw_name,"LOGNAME":account.pw_name,"LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","BASH_ENV":"/dev/null","ENV":"/dev/null","NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE":str(device_path),"NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256":digest,"NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256":accepted_lock_sha256,"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SHA256":accepted_cocoa_sha256}

def installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha256:str,accepted_cocoa_sha256:str):
    root=repo.expanduser().resolve(strict=True); env=installer_environment(device,device_digest,accepted_lock_sha256,accepted_cocoa_sha256)
    try:p=subprocess.run(["/bin/bash","--noprofile","--norc","-p",str(root/INSTALLER),source],cwd=root,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    except OSError as e: raise GoError("private installer execution failed") from e
    if p.returncode or "SDK-INTEGRATED CAPTURE LAUNCHED" not in p.stdout or canon(git(root,"rev-parse","HEAD"),"post-install HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("private installer did not preserve exact accepted field subject")
    return {"authority":"accepted-candidate-private-installer-execution-v1","result":"success","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}

'''
issuer = issuer[:start] + install_fns + issuer[end:]

old = 'got=run_installer(candidate_repo,source,device_file,dh); expected='
new = 'got=run_installer(candidate_repo,source,device_file,dh,rv["tuyaDependencyLockSHA256"],rv["cocoaPodsBuildSubjectSHA256"]); expected='
if old not in issuer:
    raise SystemExit("build installer-call anchor missing")
issuer = issuer.replace(old,new,1)
lock_anchor = 'if not HEX64.fullmatch(signed["tuyaDependencyLockSHA256"]) or not HEX64.fullmatch(signed["retainedIPASHA256"]) or not HEX64.fullmatch(signed["retainedAppTreeSHA256"]) or not HEX64.fullmatch(signed["embeddedProvisioningProfileSHA256"]): raise GoError("retained signed artifact digest invalid")\n'
if lock_anchor not in issuer:
    raise SystemExit("signed-artifact digest anchor missing")
issuer = issuer.replace(lock_anchor, lock_anchor + '    if signed["tuyaDependencyLockSHA256"]!=rv["tuyaDependencyLockSHA256"]: raise GoError("retained signed artifact Tuya dependency lock does not match prebuild GitHub review")\n',1)
record_anchor='"visualReview":rv,'
if record_anchor not in issuer:
    raise SystemExit("GO record anchor missing")
issuer=issuer.replace(record_anchor,'"visualReview":rv,"acceptedTuyaDependencyLockSHA256":rv["tuyaDependencyLockSHA256"],"acceptedCocoaPodsBuildSubjectSHA256":rv["cocoaPodsBuildSubjectSHA256"],',1)
issuer_path.write_text(issuer)

# Main issuer suite: update fixture authority chain, strict review body, installer
# mock signatures, and add global suppressed-index + reviewed digest assertions.
test_path=Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
test=test_path.read_text()
fixture_old="go.IDENTITY:f'static let requiredFieldProcedureIdentifier = \"{go.PROC}\"\\n'}.items()"
fixture_new="go.IDENTITY:f'static let requiredFieldProcedureIdentifier = \"{go.PROC}\"\\n','Scripts/bootstrap_capture_tuya_sdk.sh':'# NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256\\n# NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SHA256\\n# capture_cocoapods_build_subject.py\\n','scripts/ci/es80_signed_field_artifact_private_runner.py':'def read_private_identifier(path, root): pass\\n# O_NOFOLLOW O_DIRECTORY\\n','Scripts/capture_tuya_private_input_provenance.py':'SCHEMA = \"nembra-capture-tuya-dependencies-v2\"\\n','Scripts/capture_tuya_private_input_build_guard.py':'class KqueueVnodeBackend: pass\\n','Scripts/capture_cocoapods_build_subject.py':'SCHEMA = b\"nembra-capture-cocoapods-build-subject-v1\\\\0\"\\n'}.items()"
if fixture_old not in test:
    raise SystemExit("main fixture authority-chain anchor missing")
test=test.replace(fixture_old,fixture_new,1)
body_old="d={'schemaVersion':1,'authority':'nembra-visual-human-review-github-v1','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'verdict':'accepted'}"
body_new="d={'schemaVersion':3,'authority':'nembra-capture-human-review-github-v3','sourceCommitSHA':self.s,'visualRunID':self.ids[go.VISUAL],'visualArtifactID':self.aid,'standardScreenshotSHA256':H(self.std),'accessibilityScreenshotSHA256':H(self.ax),'tuyaDependencyLockSHA256':'a'*64,'cocoaPodsBuildSubjectSHA256':'e'*64,'verdict':'accepted'}"
if body_old not in test: raise SystemExit("main review-body anchor missing")
test=test.replace(body_old,body_new,1)
test=test.replace("def inst(self,repo,s,dev,h):\n  assert h==H(b'device-token')", "def inst(self,repo,s,dev,h,lock,cocoa):\n  assert h==H(b'device-token');assert lock=='a'*64;assert cocoa=='e'*64",1)
# Update every local installer mock from 4 authority args to 6, and its forwarding call.
test=re.sub(r"def ([A-Za-z_][A-Za-z0-9_]*)\(r,s,d,h\):",r"def \1(r,s,d,h,lock,cocoa):",test)
test=test.replace("self.f.inst(r,s,d,h)","self.f.inst(r,s,d,h,lock,cocoa)")
# The prechecked digest test now proves all three pre-side-effect subjects cross together.
old_seen="def test_prechecked_device_digest_is_passed_to_installer(self):\n  seen=[]\n  def capture(r,s,d,h,lock,cocoa):seen.append(h);return self.f.inst(r,s,d,h,lock,cocoa)\n  self.assertEqual(self.f.build(run_installer=capture)['status'],'GO')\n  self.assertEqual(seen,[H(b'device-token')])"
new_seen="def test_prechecked_device_and_reviewed_build_digests_are_passed_to_installer(self):\n  seen=[]\n  def capture(r,s,d,h,lock,cocoa):seen.append((h,lock,cocoa));return self.f.inst(r,s,d,h,lock,cocoa)\n  result=self.f.build(run_installer=capture);self.assertEqual(result['status'],'GO');self.assertEqual(result['acceptedTuyaDependencyLockSHA256'],'a'*64);self.assertEqual(result['acceptedCocoaPodsBuildSubjectSHA256'],'e'*64)\n  self.assertEqual(seen,[(H(b'device-token'),'a'*64,'e'*64)])"
if old_seen not in test: raise SystemExit("prechecked-digest test anchor missing")
test=test.replace(old_seen,new_seen,1)
# Review body duplicate remains intentionally invalid; add explicit malformed build-digest cases after the existing review authority test.
insert=' def test_candidate_dirty_and_retired_authority_rejected(self):\n'
extra=''' def test_candidate_review_requires_canonical_build_subject_digests(self):
  path=f'/pulls/{self.f.pr}/reviews/{self.f.rid}'
  self.f.map[path]['body']=self.f.body(tuyaDependencyLockSHA256='A'*64);self.no(self.f.build)
  self.f.map[path]['body']=self.f.body(cocoaPodsBuildSubjectSHA256='E'*64);self.no(self.f.build)
 def test_candidate_rejects_suppressed_index_flags_globally(self):
  extra=self.f.repo/'NembraApp'/'Hidden.swift';extra.parent.mkdir(parents=True,exist_ok=True);extra.write_text('accepted\\n');subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'add',str(extra)],check=True);subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'commit','-qm','extra tracked source'],check=True);source=subprocess.check_output(['/usr/bin/git','-C',str(self.f.repo),'rev-parse','HEAD'],text=True).strip();subprocess.run(['/usr/bin/git','-C',str(self.f.repo),'update-index','--assume-unchanged',str(extra)],check=True);extra.write_text('hidden replacement\\n');self.no(lambda:go.candidate(self.f.repo,source))
'''
if insert not in test: raise SystemExit("candidate test insertion anchor missing")
test=test.replace(insert,extra+insert,1)
test_path.write_text(test)

# Environment suite: require both reviewed build subjects while retaining the
# already-accepted prechecked intended-device digest and closed startup env.
env_path=Path("scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py")
env=env_path.read_text()
env=env.replace('"[[ \\\"${NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256:-}\\\" =~ ^[0-9a-f]{64}$ ]] || exit 47\\n"\n', '"[[ \\\"${NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256:-}\\\" =~ ^[0-9a-f]{64}$ ]] || exit 47\\n"\n                "[[ \\\"${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}\\\" == ' + "'a'" + '$(printf %063d 0 2>/dev/null) ]] || true\\n"\n',1)
# Replace the intentionally awkward inserted shell check above with exact static checks.
env=env.replace('                "[[ \\\"${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}\\\" == \'a\'$(printf %063d 0 2>/dev/null) ]] || true\\n"\n','                "[[ \\\"${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}\\\" == ' + ('a'*64) + ' ]] || exit 48\\n"\n                "[[ \\\"${NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SHA256:-}\\\" == ' + ('e'*64) + ' ]] || exit 49\\n"\n')
env=env.replace('result = GO.installer(repository, source, private_device, GO.device_hash(private_device))','result = GO.installer(repository, source, private_device, GO.device_hash(private_device), "a" * 64, "e" * 64)',1)
env=env.replace('os.environ["NEMBRA_TUYA_APP_KEY"] = "caller-key-must-not-cross"','os.environ["NEMBRA_TUYA_APP_KEY"] = "caller-key-must-not-cross"\n            os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "b" * 64\n            os.environ["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SHA256"] = "c" * 64',1)
env=env.replace('env = GO.installer_environment(device, digest)','env = GO.installer_environment(device, digest, "a" * 64, "e" * 64)',1)
env=env.replace('self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], digest)','self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"], digest)\n            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"], "a" * 64)\n            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SHA256"], "e" * 64)',1)
env=env.replace('GO.installer_environment(alias / "device", "a" * 64)','GO.installer_environment(alias / "device", "a" * 64, "b" * 64, "c" * 64)',1)
insert='    def test_installer_environment_rejects_symlinked_private_device_parent(self) -> None:\n'
extra='''    def test_noncanonical_reviewed_build_subject_digests_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-build-subject-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            digest = GO.device_hash(device)
            for lock, cocoa in (("A" * 64, "e" * 64), ("a" * 64, "E" * 64), ("a" * 63, "e" * 64), ("a" * 64, "bad")):
                with self.assertRaises(GO.GoError):
                    GO.installer_environment(device, digest, lock, cocoa)

'''
if insert not in env: raise SystemExit("environment test insertion anchor missing")
env=env.replace(insert,extra+insert,1)
env_path.write_text(env)
