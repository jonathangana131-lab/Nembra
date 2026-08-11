#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/ci/es80_authenticated_stationary_final_go.py")
text = path.read_text(encoding="utf-8")

constant = 'INSTALLER="scripts/field/install_one_time_capture.command"; RUNBOOK="docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"; IDENTITY="NembraApp/App/NembraCaptureBuildIdentity.swift"'
replacement = constant + '\nSIGNED_ARTIFACT_MODULE="scripts/ci/es80_authenticated_stationary_signed_artifact.py"'
if text.count(constant) != 1:
    raise SystemExit("issuer constant anchor drifted")
text = text.replace(constant, replacement, 1)

installer_anchor = '\ndef installer(repo:Path,source:str,device:Path,device_digest:str,accepted_lock_sha256:str):\n'
if text.count(installer_anchor) != 1:
    raise SystemExit("installer anchor drifted")
helpers = r'''
def _git_blob_oid(raw:bytes,accepted_blob:str)->str:
    if not isinstance(accepted_blob,str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",accepted_blob.lower()): raise GoError("accepted control-module Git blob invalid")
    normalized=accepted_blob.lower(); digest=hashlib.sha1() if len(normalized)==40 else hashlib.sha256()
    digest.update(f"blob {len(raw)}\0".encode("ascii")); digest.update(raw)
    return digest.hexdigest()

def _accepted_control_source(repo:Path,relative:str,accepted_blob:str)->bytes:
    root=repo.expanduser().resolve(strict=True); rel=Path(relative)
    if rel.is_absolute() or ".." in rel.parts: raise GoError("accepted control-module path invalid")
    raw=regular(root/rel,f"accepted control module {relative}")
    if _git_blob_oid(raw,accepted_blob)!=accepted_blob.lower(): raise GoError("control-module execution bytes differ from accepted Git blob")
    return raw
'''
text = text.replace(installer_anchor, helpers + installer_anchor, 1)

start = text.index("def retained_signed_artifact(")
end = text.index("\ndef build(", start)
new_block = r'''def _signed_artifact_namespace(module_source:bytes)->dict[str,Any]:
    if not isinstance(module_source,bytes) or not module_source: raise GoError("pinned retained signed-artifact module bytes are required")
    module_path=Path(__file__).with_name("es80_authenticated_stationary_signed_artifact.py")
    namespace={"__name__":"nembra_authenticated_signed_artifact","__file__":str(module_path),"__package__":None,"__builtins__":__builtins__}
    try: exec(compile(module_source,str(module_path),"exec"),namespace)
    except Exception as error: raise GoError(f"pinned retained signed-artifact module could not execute: {error}") from error
    return namespace

def retained_signed_artifact(repo:Path,source:str,device:Path,install:dict[str,Any],output:Path,module_source:bytes|None=None)->dict[str,Any]:
    if module_source is None: raise GoError("retained signed-artifact execution requires pinned accepted module bytes")
    module=_signed_artifact_namespace(module_source); operation=module.get("retain_and_reinspect")
    if not callable(operation): raise GoError("pinned retained signed-artifact module is missing retain_and_reinspect")
    try: return operation(repo,source,device,install,output)
    except Exception as error: raise GoError(f"retained signed-artifact production failed: {error}") from error

def retained_signed_artifact_reinspect(repo:Path,source:str,device:Path,install:dict[str,Any],output:Path,module_source:bytes|None=None)->dict[str,Any]:
    if module_source is None: raise GoError("retained signed-artifact reinspection requires pinned accepted module bytes")
    module=_signed_artifact_namespace(module_source); operation=module.get("reinspect_retained")
    if not callable(operation): raise GoError("pinned retained signed-artifact module is missing reinspect_retained")
    try: return operation(output,repo,source,device,install)
    except Exception as error: raise GoError(f"retained signed-artifact reinspection failed: {error}") from error
'''
text = text[:start] + new_block + text[end + 1:]

control_anchor = '    control=control_authority(authority_repo,authority_pr,authority_run,get)\n    source=canon(source,"source"); pr=pos(pr,"PR")\n'
control_replacement = '''    control=control_authority(authority_repo,authority_pr,authority_run,get)\n    signed_module_source=None\n    if inspect_signed_artifact is retained_signed_artifact or reinspect_signed_artifact is retained_signed_artifact_reinspect:\n        blobs=control.get("gitBlobs")\n        if not isinstance(blobs,dict): raise GoError("GO control plane did not retain accepted control-module Git blobs")\n        signed_module_source=_accepted_control_source(authority_repo,SIGNED_ARTIFACT_MODULE,blobs.get(SIGNED_ARTIFACT_MODULE))\n    source=canon(source,"source"); pr=pos(pr,"PR")\n'''
if text.count(control_anchor) != 1:
    raise SystemExit("build control anchor drifted")
text = text.replace(control_anchor, control_replacement, 1)

signed_call = '    signed=inspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)\n'
signed_replacement = '''    if inspect_signed_artifact is retained_signed_artifact:\n        signed=inspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa,module_source=signed_module_source)\n    else:\n        signed=inspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)\n'''
if text.count(signed_call) != 1:
    raise SystemExit("signed artifact call anchor drifted")
text = text.replace(signed_call, signed_replacement, 1)

reinspect_call = 'post_signed=reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa)'
reinspect_replacement = 'post_signed=(reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa,module_source=signed_module_source) if reinspect_signed_artifact is retained_signed_artifact_reinspect else reinspect_signed_artifact(candidate_repo,source,device_file,got,retained_ipa))'
if text.count(reinspect_call) != 1:
    raise SystemExit("signed artifact reinspection anchor drifted")
text = text.replace(reinspect_call, reinspect_replacement, 1)

path.write_text(text, encoding="utf-8")
