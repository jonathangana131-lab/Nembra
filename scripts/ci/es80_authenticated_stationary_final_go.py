#!/usr/bin/env python3
"""Fail-closed GO issuer for ES80-AUTHENTICATED-STATIONARY-v1.

External control-plane only: verifies one exact software/visual candidate, runs its reviewed private
installer on the intended iPhone, then publishes authorization for one stationary read-only attempt.
Runtime account/membership/correlation/observation/seal remain app-enforced experiment gates.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, re, stat, subprocess, sys, urllib.request, zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO="jonathangana131-lab/Nembra"; OWNER="jonathangana131-lab"; PROC="ES80-AUTHENTICATED-STATIONARY-v1"
BUNDLE="com.jonathangana131.nembra.capturelearn"; DEVICE="iPhone 12"; PRODUCT="iPhone13,2"
WORKFLOWS=("Capture Main Selective Graft Diagnostic","Capture Field Build Provenance","Xcode 27 PR Exact-Head QA","Capture Standalone Visual Evidence")
WORKFLOW_PATHS={
    "Capture Main Selective Graft Diagnostic":".github/workflows/capture-main-selective-graft-diagnostic.yml",
    "Capture Field Build Provenance":".github/workflows/capture-field-build-provenance.yml",
    "Xcode 27 PR Exact-Head QA":".github/workflows/xcode27-pr-command.yml",
    "Capture Standalone Visual Evidence":".github/workflows/capture-standalone-visual-evidence.yml",
}
VISUAL=WORKFLOWS[-1]; MANIFEST="NembraCaptureStandaloneVisualEvidence.json"
AUTH_WORKFLOW_NAME="Capture Authenticated Stationary Final GO"
AUTH_WORKFLOW_PATH=".github/workflows/capture-authenticated-stationary-final-go.yml"
STATES={"unprovisioned-dark-standard","unprovisioned-dark-accessibility-xxxl"}
INSTALLER="scripts/field/install_one_time_capture.command"; BOOTSTRAP="Scripts/bootstrap_capture_tuya_sdk.sh"; RUNBOOK="docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"; IDENTITY="NembraApp/App/NembraCaptureBuildIdentity.swift"
HEX40=re.compile(r"^[0-9a-f]{40}$"); HEX64=re.compile(r"^[0-9a-f]{64}$"); DIGEST=re.compile(r"^sha256:([0-9a-f]{64})$")

class GoError(RuntimeError): pass

def sha(raw:bytes)->str:return hashlib.sha256(raw).hexdigest()
def dup(pairs):
    out={}
    for k,v in pairs:
        if k in out: raise GoError(f"duplicate JSON key: {k}")
        out[k]=v
    return out

def obj(raw:bytes,label:str)->dict[str,Any]:
    try:v=json.loads(raw,object_pairs_hook=dup)
    except (UnicodeDecodeError,json.JSONDecodeError) as e: raise GoError(f"{label} invalid JSON") from e
    if not isinstance(v,dict): raise GoError(f"{label} must be an object")
    return v

def regular(path:Path,label:str,mode600=False)->bytes:
    if not hasattr(os,"O_NOFOLLOW"): raise GoError("O_NOFOLLOW required")
    try: fd=os.open(path.expanduser(),os.O_RDONLY|os.O_NOFOLLOW|(getattr(os,"O_CLOEXEC",0)))
    except OSError as e: raise GoError(f"{label} unavailable/non-regular") from e
    try:
        a=os.fstat(fd)
        if not stat.S_ISREG(a.st_mode) or a.st_size<=0: raise GoError(f"{label} must be non-empty regular file")
        if mode600 and stat.S_IMODE(a.st_mode)!=0o600: raise GoError(f"{label} must be mode 0600")
        chunks=[]
        while True:
            c=os.read(fd,1<<20)
            if not c: break
            chunks.append(c)
        raw=b"".join(chunks); b=os.fstat(fd)
    finally: os.close(fd)
    if (a.st_dev,a.st_ino,a.st_size,a.st_mtime_ns,a.st_ctime_ns)!=(b.st_dev,b.st_ino,b.st_size,b.st_mtime_ns,b.st_ctime_ns) or len(raw)!=a.st_size: raise GoError(f"{label} changed while reading")
    s=path.expanduser().lstat()
    if stat.S_ISLNK(s.st_mode) or (s.st_dev,s.st_ino)!=(b.st_dev,b.st_ino): raise GoError(f"{label} path identity changed")
    return raw

def canon(v,label):
    if not isinstance(v,str) or not HEX40.fullmatch(v.lower()): raise GoError(f"{label} not canonical 40-hex")
    return v.lower()
def pos(v,label):
    if not isinstance(v,int) or isinstance(v,bool) or v<=0: raise GoError(f"{label} not positive integer")
    return v

def api(path:str):
    url=f"https://api.github.com/repos/{REPO}{path}"; h={"Accept":"application/vnd.github+json","User-Agent":"Nembra-V14-Auth-Stationary-GO","X-GitHub-Api-Version":"2022-11-28"}
    if os.getenv("GITHUB_TOKEN"," ").strip():h["Authorization"]="Bearer "+os.environ["GITHUB_TOKEN"].strip()
    try:
        with urllib.request.urlopen(urllib.request.Request(url,headers=h),timeout=20) as r:
            if r.geturl().split("?",1)[0]!=url: raise GoError("GitHub API redirected")
            raw=r.read()
    except OSError as e: raise GoError("GitHub API unavailable") from e
    return raw,obj(raw,path)

def public(source:str,pr:int,runs:dict[str,int],get=api):
    if set(runs)!=set(WORKFLOWS): raise GoError("exact required workflow set mismatch")
    _,p=get(f"/pulls/{pr}"); head=p.get("head",{}); base=p.get("base",{}); head_ref=head.get("ref"); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft")
    if canon(head.get("sha"),"PR head")!=source or head.get("repo",{}).get("full_name")!=REPO or base.get("ref")!="main" or not isinstance(head_ref,str) or not head_ref: raise GoError("canonical PR subject mismatch")
    if not ((state=="open" and draft is False) or (state=="closed" and merged)):
        raise GoError("canonical PR is draft or closed without merge; software acceptance is not promotable")
    subjects=[]
    for name in WORKFLOWS:
        rid=pos(runs[name],name); _,r=get(f"/actions/runs/{rid}")
        pulls=r.get("pull_requests",[])
        bound=(isinstance(pulls,list) and any(isinstance(x,dict) and x.get("number")==pr for x in pulls)) or (pulls==[] and r.get("head_branch")==head_ref)
        if r.get("name")!=name or r.get("path")!=WORKFLOW_PATHS[name] or canon(r.get("head_sha"),name)!=source or r.get("status")!="completed" or r.get("conclusion")!="success" or r.get("event")!="pull_request" or not bound: raise GoError(f"{name} is not exact terminal SUCCESS from its canonical workflow for PR #{pr}")
        subjects.append({"name":name,"path":WORKFLOW_PATHS[name],"runID":rid,"headSHA":source,"conclusion":"success"})
    return {"number":pr,"headSHA":source,"headBranch":head_ref,"base":"main","state":state,"merged":merged,"draft":draft},subjects

def control_plane(authority_repo:Path,pr:int,run_id:int,get=api):
    root=authority_repo.expanduser().resolve(strict=True); source=canon(git(root,"rev-parse","HEAD"),"GO control-plane HEAD")
    if git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("GO control-plane checkout is not clean")
    _,p=get(f"/pulls/{pos(pr,'GO control-plane PR')}"); head=p.get("head",{}); base=p.get("base",{}); state=p.get("state"); merged=bool(p.get("merged_at")); draft=p.get("draft")
    if canon(head.get("sha"),"GO control-plane PR head")!=source or head.get("repo",{}).get("full_name")!=REPO or base.get("ref")!="main" or not ((state=="open" and draft is False) or (state=="closed" and merged)): raise GoError("GO control-plane PR is not exact/promotable")
    _,run=get(f"/actions/runs/{pos(run_id,'GO control-plane workflow run')}")
    if run.get("name")!=AUTH_WORKFLOW_NAME or run.get("path")!=AUTH_WORKFLOW_PATH or canon(run.get("head_sha"),"GO control-plane workflow head")!=source or run.get("status")!="completed" or run.get("conclusion")!="success" or run.get("event") not in {"push","pull_request"}: raise GoError("GO control-plane exact authority workflow is not terminal SUCCESS")
    branch=head.get("ref"); pulls=run.get("pull_requests",[])
    if run.get("event")=="pull_request":
        bound=(isinstance(pulls,list) and any(isinstance(x,dict) and x.get("number")==pr for x in pulls)) or (pulls==[] and run.get("head_branch")==branch)
        if not bound: raise GoError("GO control-plane workflow is not bound to canonical PR")
    elif run.get("head_branch")!=branch: raise GoError("GO control-plane push workflow is not bound to canonical PR branch")
    paths=("scripts/ci/es80_authenticated_stationary_final_go.py","scripts/ci/es80_authenticated_stationary_signed_artifact.py","scripts/ci/es80_today_final_go_publication.py",AUTH_WORKFLOW_PATH,"scripts/ci/tests/test_es80_authenticated_stationary_final_go.py")
    blobs={path:git(root,"rev-parse",f"HEAD:{path}").lower() for path in paths}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",value) for value in blobs.values()): raise GoError("GO control-plane Git blob identity invalid")
    return {"authority":"nembra-authenticated-stationary-go-control-plane-v1","sourceCommitSHA":source,"prNumber":pr,"headBranch":branch,"state":state,"merged":merged,"draft":draft,"workflowRunID":run_id,"workflowName":AUTH_WORKFLOW_NAME,"workflowPath":AUTH_WORKFLOW_PATH,"gitBlobs":blobs}

def visual(source:str,run:int,aid:int,archive:Path,get=api):
    _,a=get(f"/actions/artifacts/{aid}"); m=DIGEST.fullmatch(a.get("digest","") if isinstance(a.get("digest"),str) else "")
    if a.get("expired") is not False or a.get("workflow_run",{}).get("id")!=run or not m: raise GoError("visual artifact metadata mismatch")
    raw=regular(archive,"visual artifact")
    if sha(raw)!=m.group(1): raise GoError("visual artifact digest mismatch")
    try:
        with zipfile.ZipFile(archive) as z:
            names=z.namelist()
            if len(names)!=len(set(names)) or names.count(MANIFEST)!=1: raise GoError("visual archive has duplicate names or manifest count mismatch")
            mr=z.read(MANIFEST); man=obj(mr,"visual manifest"); shots={}; entries=man.get("screenshots")
            if not isinstance(entries,list) or len(entries)!=2: raise GoError("visual screenshot list mismatch")
            for x in entries:
                if not isinstance(x,dict): raise GoError("visual screenshot entry invalid")
                st=x.get("state"); rel=x.get("relativePath"); hx=x.get("sha256")
                if st not in STATES or st in shots or not isinstance(rel,str) or not isinstance(hx,str) or not HEX64.fullmatch(hx): raise GoError("visual screenshot entry invalid")
                if sha(z.read(rel))!=hx: raise GoError(f"visual screenshot digest mismatch: {st}")
                shots[st]={"relativePath":rel,"sha256":hx}
    except (zipfile.BadZipFile,KeyError) as e: raise GoError("visual archive malformed") from e
    required={"schemaVersion":6,"authority":"standalone-capture-simulator-presentation-only","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"baselineDevice":DEVICE,"baselineOS":"iOS 27","expectedFieldBuildAuthority":False,"physicalAuthorityCreated":False,"protocolAuthorityCreated":False,"syntheticAuthorityEnvironmentRejected":True,"visualAcceptanceRequiresHumanReview":True,"requiredProcedureSourceVerified":True,"procedureBuildRendezvousVerified":True,"tuyaDependencyLockSHA256":""}
    if any(man.get(k)!=v for k,v in required.items()) or set(shots)!=STATES: raise GoError("visual manifest authority mismatch")
    return {"runID":run,"artifactID":aid,"artifactDigest":a["digest"],"manifestSHA256":sha(mr),"screenshots":shots}

def review(pr:int,review_id:int,source:str,v:dict[str,Any],get=api):
    review_id=pos(review_id,"visual review ID"); raw,r=get(f"/pulls/{pr}/reviews/{review_id}")
    body=r.get("body")
    if not isinstance(body,str) or not body.strip(): raise GoError("GitHub visual review body missing")
    b=obj(body.encode(),"GitHub visual review body")
    keys={"schemaVersion","authority","sourceCommitSHA","visualRunID","visualArtifactID","standardScreenshotSHA256","accessibilityScreenshotSHA256","verdict"}
    user=r.get("user",{})
    if set(b)!=keys or b.get("schemaVersion")!=1 or b.get("authority")!="nembra-visual-human-review-github-v1" or canon(b.get("sourceCommitSHA"),"visual review source")!=source or b.get("visualRunID")!=v["runID"] or b.get("visualArtifactID")!=v["artifactID"] or b.get("verdict")!="accepted": raise GoError("GitHub visual review authority mismatch")
    if r.get("id")!=review_id or r.get("state") not in {"COMMENTED","APPROVED"} or canon(r.get("commit_id"),"visual review commit")!=source or user.get("login")!=OWNER or r.get("author_association")!="OWNER": raise GoError("GitHub visual review custody mismatch")
    stamp=r.get("submitted_at")
    if not isinstance(stamp,str) or not stamp.endswith("Z"): raise GoError("GitHub visual review timestamp invalid")
    try: datetime.fromisoformat(stamp[:-1]+"+00:00")
    except ValueError as e: raise GoError("GitHub visual review timestamp invalid") from e
    s=v["screenshots"]; std=s["unprovisioned-dark-standard"]["sha256"]; ax=s["unprovisioned-dark-accessibility-xxxl"]["sha256"]
    if b["standardScreenshotSHA256"]!=std or b["accessibilityScreenshotSHA256"]!=ax: raise GoError("GitHub visual review screenshot mismatch")
    return {"authority":b["authority"],"reviewID":review_id,"reviewNodeID":r.get("node_id"),"reviewBodySHA256":sha(body.encode()),"reviewedAtUTC":stamp,"reviewer":OWNER,"state":r["state"],"verdict":"accepted","standardScreenshotSHA256":std,"accessibilityScreenshotSHA256":ax}

def dependency_lock_review(pr:int,review_id:int,source:str,get=api):
    review_id=pos(review_id,"dependency-lock review ID"); _,r=get(f"/pulls/{pr}/reviews/{review_id}")
    body=r.get("body")
    if not isinstance(body,str) or not body.strip(): raise GoError("GitHub dependency-lock review body missing")
    b=obj(body.encode(),"GitHub dependency-lock review body")
    keys={"schemaVersion","authority","sourceCommitSHA","podfileLockSHA256","verdict"}; lock=b.get("podfileLockSHA256"); user=r.get("user",{})
    if set(b)!=keys or b.get("schemaVersion")!=1 or b.get("authority")!="nembra-tuya-dependency-lock-review-github-v1" or canon(b.get("sourceCommitSHA"),"dependency-lock review source")!=source or not isinstance(lock,str) or not HEX64.fullmatch(lock) or b.get("verdict")!="accepted": raise GoError("GitHub dependency-lock review authority mismatch")
    if r.get("id")!=review_id or r.get("state") not in {"COMMENTED","APPROVED"} or canon(r.get("commit_id"),"dependency-lock review commit")!=source or user.get("login")!=OWNER or r.get("author_association")!="OWNER": raise GoError("GitHub dependency-lock review custody mismatch")
    stamp=r.get("submitted_at")
    if not isinstance(stamp,str) or not stamp.endswith("Z"): raise GoError("GitHub dependency-lock review timestamp invalid")
    try: datetime.fromisoformat(stamp[:-1]+"+00:00")
    except ValueError as e: raise GoError("GitHub dependency-lock review timestamp invalid") from e
    return {"authority":b["authority"],"reviewID":review_id,"reviewNodeID":r.get("node_id"),"reviewBodySHA256":sha(body.encode()),"reviewedAtUTC":stamp,"reviewer":OWNER,"state":r["state"],"verdict":"accepted","sourceCommitSHA":source,"podfileLockSHA256":lock}

def git(repo:Path,*args):
    try:return subprocess.run(["/usr/bin/git","-C",str(repo),*args],check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env={"PATH":"/usr/bin:/bin"}).stdout.strip()
    except (OSError,subprocess.CalledProcessError) as e: raise GoError("candidate Git custody failed") from e

def candidate(repo:Path,source:str):
    root=repo.expanduser().resolve(strict=True)
    if canon(git(root,"rev-parse","HEAD"),"candidate HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("candidate checkout is not exact clean accepted source")
    bindings=(("installer",INSTALLER),("bootstrap",BOOTSTRAP),("runbook",RUNBOOK),("buildIdentity",IDENTITY)); blobs={k:git(root,"rev-parse",f"HEAD:{p}").lower() for k,p in bindings}
    if any(not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",x) for x in blobs.values()): raise GoError("candidate Git blob invalid")
    paths={k:root/p for k,p in bindings}
    if any(not p.is_file() or p.is_symlink() for p in paths.values()): raise GoError("candidate authority path is not a regular non-symlink file")
    ins=paths["installer"].read_text(); boot=paths["bootstrap"].read_text(); rb=paths["runbook"].read_text(); ident=paths["buildIdentity"].read_text()
    lock_contract=("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" in boot and "--resolve-lock-for-review" in boot and '[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]]' in boot and '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"' in ins and "-- xcodebuild" in ins and ins.index('"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"')<ins.index("-- xcodebuild"))
    if f'PROCEDURE_ID="{PROC}"' not in ins or f'BUNDLE_ID="{BUNDLE}"' not in ins or f"PROCEDURE_ID: `{PROC}`" not in rb or f'static let requiredFieldProcedureIdentifier = "{PROC}"' not in ident or "ES80-FINGERPRINT-v1" in ins or "NEMBRA_ES80_TODAY_RESEARCH" in ins or not lock_contract: raise GoError("candidate carries wrong/retired/incomplete field authority")
    return {"sourceCommitSHA":source,"installerGitBlob":blobs["installer"],"bootstrapGitBlob":blobs["bootstrap"],"runbookGitBlob":blobs["runbook"],"buildIdentityGitBlob":blobs["buildIdentity"]}

def device_hash(path:Path):
    raw=regular(path,"private intended-device identifier",True)
    try:t=raw.decode().strip()
    except UnicodeDecodeError as e: raise GoError("private device identifier invalid") from e
    if not t or any(c.isspace() for c in t): raise GoError("private device identifier must be one token")
    return sha(t.encode())

def installer(repo:Path,source:str,device:Path,accepted_lock_sha:str):
    if not isinstance(accepted_lock_sha,str) or not HEX64.fullmatch(accepted_lock_sha): raise GoError("accepted Tuya dependency lock digest invalid")
    root=repo.expanduser().resolve(strict=True); env=os.environ.copy(); env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"]=str(device.expanduser().resolve(strict=True)); env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"]=accepted_lock_sha
    try:p=subprocess.run(["/bin/bash",str(root/INSTALLER),source],cwd=root,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    except OSError as e: raise GoError("private installer execution failed") from e
    if p.returncode or "SDK-INTEGRATED CAPTURE LAUNCHED" not in p.stdout or canon(git(root,"rev-parse","HEAD"),"post-install HEAD")!=source or git(root,"status","--porcelain=v1","--untracked-files=all"): raise GoError("private installer did not preserve exact accepted field subject")
    return {"authority":"accepted-candidate-private-installer-execution-v1","result":"success","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"acceptedTuyaDependencyLockSHA256":accepted_lock_sha,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}

def retained_signed_artifact(repo:Path,source:str,device:Path,install:dict[str,Any],output:Path)->dict[str,Any]:
    module_path=Path(__file__).with_name("es80_authenticated_stationary_signed_artifact.py")
    spec=importlib.util.spec_from_file_location("nembra_authenticated_signed_artifact",module_path)
    if not spec or not spec.loader: raise GoError("retained signed-artifact module unavailable")
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    try: return module.retain_and_reinspect(repo,source,device,install,output)
    except Exception as error: raise GoError(f"retained signed-artifact production failed: {error}") from error

def retained_signed_artifact_reinspect(repo:Path,source:str,device:Path,install:dict[str,Any],output:Path)->dict[str,Any]:
    module_path=Path(__file__).with_name("es80_authenticated_stationary_signed_artifact.py")
    spec=importlib.util.spec_from_file_location("nembra_authenticated_signed_artifact",module_path)
    if not spec or not spec.loader: raise GoError("retained signed-artifact module unavailable")
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    try: return module.reinspect_retained(output,repo,source,device,install)
    except Exception as error: raise GoError(f"retained signed-artifact reinspection failed: {error}") from error

def build(*,authority_repo:Path,authority_pr:int,authority_run:int,candidate_repo:Path,source:str,pr:int,runs:dict[str,int],artifact_id:int,review_id:int,lock_review_id:int,archive:Path,device_file:Path,retained_ipa:Path,get=api,control_authority=control_plane,run_installer=installer,inspect_signed_artifact=retained_signed_artifact,reinspect_signed_artifact=retained_signed_artifact_reinspect,now=None):
    control=control_authority(authority_repo,authority_pr,authority_run,get)
    source=canon(source,"source"); pr=pos(pr,"PR")
    ps,ws=public(source,pr,runs,get); vs=visual(source,runs[VISUAL],pos(artifact_id,"artifact"),archive,get); rv=review(pr,review_id,source,vs,get); lr=dependency_lock_review(pr,lock_review_id,source,get); cs=candidate(candidate_repo,source); dh=device_hash(device_file)
    accepted_lock=lr["podfileLockSHA256"]; got=run_installer(candidate_repo,source,device_file,accepted_lock); expected={"authority":"accepted-candidate-private-installer-execution-v1","result":"success","sourceCommitSHA":source,"buildIdentifier":f"capture-v14-{source[:12]}","bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"acceptedTuyaDependencyLockSHA256":accepted_lock,"baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27"}
    if got!=expected: raise GoError("private installer result drifted")
    signed=inspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)
    required_signed={"authority":"nembra-authenticated-stationary-retained-signed-artifact-v1","sourceCommitSHA":source,"buildIdentifier":expected["buildIdentifier"],"bundleIdentifier":BUNDLE,"procedureIdentifier":PROC,"codesignVerified":True,"intendedDeviceIncluded":True,"physicalAuthorityCreated":False}
    if not isinstance(signed,dict) or any(signed.get(k)!=v for k,v in required_signed.items()): raise GoError("retained signed artifact authority mismatch")
    for key in ("tuyaDependencyLockSHA256","retainedIPASHA256","retainedAppTreeSHA256","embeddedProvisioningProfileSHA256","signingTeamIdentifier","applicationIdentifier"):
        value=signed.get(key)
        if not isinstance(value,str) or not value: raise GoError(f"retained signed artifact missing {key}")
    if not HEX64.fullmatch(signed["tuyaDependencyLockSHA256"]) or not HEX64.fullmatch(signed["retainedIPASHA256"]) or not HEX64.fullmatch(signed["retainedAppTreeSHA256"]) or not HEX64.fullmatch(signed["embeddedProvisioningProfileSHA256"]): raise GoError("retained signed artifact digest invalid")
    if signed["tuyaDependencyLockSHA256"]!=accepted_lock: raise GoError("retained signed artifact dependency lock does not match GitHub-accepted lock subject")

    post_control=control_authority(authority_repo,authority_pr,authority_run,get); post_ps,post_ws=public(source,pr,runs,get); post_vs=visual(source,runs[VISUAL],artifact_id,archive,get); post_rv=review(pr,review_id,source,post_vs,get); post_lr=dependency_lock_review(pr,lock_review_id,source,get); post_cs=candidate(candidate_repo,source); post_dh=device_hash(device_file); post_signed=reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)
    stable_pr=("number","headSHA","headBranch","base","state","merged","draft")
    if post_control!=control or any(post_ps[k]!=ps[k] for k in stable_pr) or post_ws!=ws or post_vs!=vs or post_rv!=rv or post_lr!=lr or post_cs!=cs or post_dh!=dh or post_signed!=signed:
        raise GoError("GO authority changed during private install; re-run from fresh exact evidence")
    ps,ws,vs,rv,lr,cs,dh=post_ps,post_ws,post_vs,post_rv,post_lr,post_cs,post_dh

    stamp=(now or datetime.now(timezone.utc)).astimezone(timezone.utc).isoformat().replace("+00:00","Z")
    return {"schemaVersion":1,"authority":"nembra-authenticated-stationary-final-go-v1","status":"GO","createdAtUTC":stamp,"finalGOControlPlane":control,"acceptedSourceCommitSHA":source,"acceptedPR":ps,"procedureIdentifier":PROC,"buildIdentifier":expected["buildIdentifier"],"bundleIdentifier":BUNDLE,"softwareAcceptance":ws,"visualArtifact":vs,"visualReview":rv,"tuyaDependencyLockReview":lr,"candidateSource":cs,"privateFieldInstall":{**got,"intendedDeviceIdentifierSHA256":dh},"retainedSignedFieldArtifact":signed,"experiment":{"scope":"one stationary authenticated read-only ES80 Capture attempt","baselineDevice":DEVICE,"baselineProductType":PRODUCT,"baselineOS":"iOS 27","initialScooterState":"OFF and stationary","runtimeRequiredGates":["field-build provenance remains current","official Tuya SDK + owning account","fresh exact scooter membership/UID lease","fresh unique OFF1 -> ON1 -> OFF2 -> ON2 full-UUID correlation","explicit operator target confirmation","official Tuya SDK sole post-handoff BLE owner",">=45 monotonic seconds same-generation authenticated application evidence","seal accepted immutable prefix before share"],"expectedArtifact":"one immutable sanitized Nembra Capture JSON","expectedArtifactTruth":{"rawFD50BytesCaptured":False,"dpQueriesSent":False,"dpCommandsSent":False},"stopConditions":["authority/account/membership changes","correlation none/ambiguous","continuity/clock/lifecycle fails","no same-generation evidence by deadline","any secret leak","any DP query/publish, scooter command, reset/unbind/OTA, or second post-auth CoreBluetooth owner"],"ridingAuthorized":False,"applicationWritesAuthorized":False,"dpQueryOrPublishAuthorized":False,"scooterCommandsAuthorized":False},"physicalResultCollected":False}

def publication():
    p=Path(__file__).with_name("es80_today_final_go_publication.py"); s=importlib.util.spec_from_file_location("pub",p)
    if not s or not s.loader: raise GoError("publication helper unavailable")
    m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m

def main(argv=None):
    p=argparse.ArgumentParser(); p.add_argument("--authority-repo",type=Path,required=True); p.add_argument("--authority-pr-number",type=int,required=True); p.add_argument("--authority-workflow-run",type=int,required=True); p.add_argument("--candidate-repo",type=Path,required=True); p.add_argument("--source-sha",required=True); p.add_argument("--pr-number",type=int,required=True); p.add_argument("--workflow",action="append",required=True); p.add_argument("--visual-artifact-id",type=int,required=True); p.add_argument("--visual-artifact-archive",type=Path,required=True); p.add_argument("--visual-review-id",type=int,required=True); p.add_argument("--dependency-lock-review-id",type=int,required=True); p.add_argument("--intended-device-udid-file",type=Path,required=True); p.add_argument("--retained-field-ipa",type=Path,required=True); p.add_argument("--output",type=Path,required=True); p.add_argument("--run-private-installer",action="store_true"); a=p.parse_args(argv)
    if not a.run_private_installer: p.error("--run-private-installer is required")
    try:
        runs={}
        for x in a.workflow:
            n,sep,i=x.rpartition("=")
            if not sep or n in runs: raise GoError("--workflow must be unique NAME=RUN_ID")
            runs[n]=pos(int(i),n)
        r=build(authority_repo=a.authority_repo,authority_pr=a.authority_pr_number,authority_run=a.authority_workflow_run,candidate_repo=a.candidate_repo,source=a.source_sha,pr=a.pr_number,runs=runs,artifact_id=a.visual_artifact_id,review_id=a.visual_review_id,lock_review_id=a.dependency_lock_review_id,archive=a.visual_artifact_archive,device_file=a.intended_device_udid_file,retained_ipa=a.retained_field_ipa)
        raw=(json.dumps(r,indent=2,sort_keys=True)+"\n").encode(); d=publication().publish_record_no_replace(a.output,raw)
    except (GoError,OSError,ValueError) as e: print(f"AUTHENTICATED STATIONARY FINAL GO: NO-GO: {e}",file=sys.stderr); return 2
    print(f"AUTHENTICATED STATIONARY FINAL GO: GO: {a.output.resolve(strict=True)}\nrecord_sha256={d}\nPHYSICAL RESULT COLLECTED: NO"); return 0
if __name__=="__main__": raise SystemExit(main())
